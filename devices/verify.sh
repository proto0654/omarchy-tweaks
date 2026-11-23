#!/usr/bin/env bash
# Проверка каталога devices: udev-правило, keyd-шаблон и наличие железа.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
readonly RULES="${SCRIPT_DIR}/udev/99-input-kit.rules"
readonly KEYD_CONF="${SCRIPT_DIR}/keyd/zelotes-c18.conf"

usage() {
  cat <<'EOF'
использование: verify.sh [--live]

Проверяет:
  - синтаксис udev-правила и наличие uaccess для обоих устройств;
  - синтаксис keyd-шаблона (keyd check, если keyd установлен) и нужные секции;
  - что ядро видит 3 интерфейса мыши Zelotes C-18 и 2 интерфейса
    клавиатуры DEXP First Blood.

Параметры:
  --live      дополнительно требовать uaccess-ACL на /dev/hidraw* (после
              установки правила и переподключения устройства)
  -h, --help  показать эту справку
EOF
}

live=false
if (($#)); then
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --live)
      live=true
      ;;
    *)
      printf 'verify.sh: неизвестный аргумент: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
fi

status=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  status=1
}
ok() {
  printf 'OK: %s\n' "$*"
}
warn() {
  printf 'ПРЕДУПРЕЖДЕНИЕ: %s\n' "$*" >&2
}

for file in "${RULES}" "${KEYD_CONF}"; do
  if [[ ! -f ${file} ]]; then
    fail "нет файла ${file}"
  fi
done

if [[ ${status} -ne 0 ]]; then
  printf 'devices: FAIL\n' >&2
  exit 1
fi

# --- udev ---------------------------------------------------------------

if command -v udevadm >/dev/null 2>&1; then
  if udevadm verify "${RULES}" >/dev/null 2>&1; then
    ok "udevadm verify: правило синтаксически корректно"
  else
    fail "udevadm verify не принял ${RULES}"
  fi
else
  warn "udevadm не найден, синтаксис правила не проверен"
fi

for id in '12c9' '2003' '1a2c' '635a'; do
  if ! grep -Fq "${id}" "${RULES}"; then
    fail "в udev-правиле нет id ${id}"
  fi
done

if [[ "$(grep -c 'TAG+="uaccess"' "${RULES}" || true)" -ne 2 ]]; then
  fail 'в udev-правиле должно быть ровно два TAG+="uaccess"'
else
  ok "udev: uaccess для обоих устройств"
fi

# --- keyd ---------------------------------------------------------------

if command -v keyd >/dev/null 2>&1; then
  if keyd check "${KEYD_CONF}" >/dev/null 2>&1; then
    ok "keyd check: шаблон корректен"
  else
    fail "keyd check не принял ${KEYD_CONF}"
  fi
else
  warn "keyd не установлен, проверяю шаблон статически"
  if ! awk '
    /^\[ids\]$/ { in_ids = 1; next }
    /^\[/ { in_ids = 0 }
    in_ids && $0 == "12c9:2003" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "${KEYD_CONF}"; then
    fail "в [ids] нет 12c9:2003"
  fi
  for section in 'main' 'zelotes-c18'; do
    if ! grep -Fq "[${section}]" "${KEYD_CONF}"; then
      fail "нет секции [${section}]"
    fi
  done
  for binding in 'w = up' 's = down' 'a = left' 'd = right' 'layer(zelotes-c18)' 'macro('; do
    if ! grep -Fq "${binding}" "${KEYD_CONF}"; then
      fail "в шаблоне нет привязки «${binding}»"
    fi
  done
  if [[ ${status} -eq 0 ]]; then
    ok "keyd: шаблон содержит [ids], [main], [zelotes-c18] и примеры ремапа"
  fi
fi

# --- железо -------------------------------------------------------------

mouse_interfaces=0
keyboard_interfaces=0

for uevent in /sys/class/hidraw/hidraw*/device/uevent; do
  [[ -e ${uevent} ]] || continue
  hid_id="$(awk -F= '$1 == "HID_ID" { print $2 }' "${uevent}")"
  hid_id="${hid_id,,}"
  if [[ ${hid_id} =~ :0*12c9:0*2003$ ]]; then
    mouse_interfaces=$((mouse_interfaces + 1))
  elif [[ ${hid_id} =~ :0*1a2c:0*635a$ ]]; then
    keyboard_interfaces=$((keyboard_interfaces + 1))
  fi
done

if [[ ${mouse_interfaces} -eq 3 ]]; then
  ok "Zelotes C-18: 3 hidraw-интерфейса"
else
  fail "Zelotes C-18: найдено ${mouse_interfaces} hidraw-интерфейсов, ожидалось 3"
fi

# Клавиатура заявляет два HID-интерфейса: boot-клавиатуру и consumer/vendor
# (у этой прошивки там же RGB). Второй поднимается не всегда: на low-speed порту
# usbhid срывается на чтении дескриптора с таймаутом (-110, ETIMEDOUT), драйвер
# к интерфейсу не привязывается и hidraw у него не появляется. Клавиатура при
# этом полностью работает через первый интерфейс, а вендорный канал мы не
# используем — поэтому второй интерфейс это предупреждение, а не FAIL.
keyboard_inputs=$(grep -ls 'SEMICO' /sys/class/input/event*/device/name 2>/dev/null | wc -l)

if [[ ${keyboard_interfaces} -ge 2 ]]; then
  ok "DEXP First Blood: 2 hidraw-интерфейса (boot + consumer/vendor)"
elif [[ ${keyboard_interfaces} -eq 1 && ${keyboard_inputs} -ge 1 ]]; then
  ok "DEXP First Blood: клавиатура на месте (1 hidraw, event-устройство отвечает)"
  warn "DEXP First Blood: второй hidraw-интерфейс (consumer/vendor, RGB) не поднялся — на работу клавиатуры не влияет"
  reason=""
  if command -v journalctl >/dev/null 2>&1; then
    reason=$(journalctl -k --no-pager 2>/dev/null \
      | grep -E "usbhid 1-[0-9.]+:1\.[0-9]+: (can't add hid device|probe with driver usbhid failed)" \
      | tail -1 | sed 's/.*kernel: //')
  fi
  if [[ -n ${reason} ]]; then
    warn "  ядро: ${reason}"
  else
    warn "  причина в журнале ядра не найдена; проверьте: journalctl -k | grep usbhid"
  fi
  warn "  при необходимости: переподключить клавиатуру в другой порт (USB2) и посмотреть ls /sys/class/hidraw/"
elif [[ ${keyboard_interfaces} -eq 0 ]]; then
  fail "DEXP First Blood: hidraw-интерфейсов не найдено (клавиатура не подключена?)"
else
  fail "DEXP First Blood: найден ${keyboard_interfaces} hidraw, но event-устройства клавиатуры нет"
fi

# --- живая проверка ACL -------------------------------------------------

if [[ ${live} == true ]]; then
  if ! command -v getfacl >/dev/null 2>&1; then
    warn "getfacl не найден, live-проверка ACL пропущена"
  else
    current_user="$(id -un)"
    acl_found=0
    acl_missing=0
    for uevent in /sys/class/hidraw/hidraw*/device/uevent; do
      [[ -e ${uevent} ]] || continue
      hid_id="$(awk -F= '$1 == "HID_ID" { print $2 }' "${uevent}")"
      hid_id="${hid_id,,}"
      if [[ ${hid_id} =~ :0*12c9:0*2003$ ]]; then
        :
      elif [[ ${hid_id} =~ :0*1a2c:0*635a$ ]]; then
        :
      else
        continue
      fi
      # В пути .../hidraw0/device/uevent имя узла — предпоследний элемент.
      node="/dev/$(printf '%s\n' "${uevent}" | awk -F/ '{ print $(NF-2) }')"
      if getfacl -cp "${node}" 2>/dev/null | grep -Fq "user:${current_user}:rw-"; then
        acl_found=$((acl_found + 1))
      else
        acl_missing=$((acl_missing + 1))
      fi
    done
    if [[ ${acl_missing} -gt 0 ]]; then
      fail "uaccess-ACL нет у ${acl_missing} hidraw-узлов; установите правило и переподключите устройства"
    else
      ok "uaccess-ACL есть у всех hidraw-узлов (${acl_found})"
    fi
  fi
else
  warn "ACL не проверялся; для строгой проверки: bash devices/verify.sh --live"
fi

if [[ ${status} -ne 0 ]]; then
  printf 'devices: FAIL\n' >&2
  exit 1
fi

printf 'devices: OK\n'
