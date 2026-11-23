#!/usr/bin/env bash
# Установка omarchy-tweaks: lang-auto, сниппет switcher, файлы devices и
# apps-by-usage (с --with-apps).
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly ROOT_DIR
readonly HYPR_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/hypr"

usage() {
  cat <<'EOF'
использование: install.sh [параметры]

Без параметров устанавливает только lang-auto (демон + user unit) и
включает службу.

Параметры:
  --with-switcher  скопировать switcher/bindings.snippet.lua в
                   ~/.config/hypr/bindings.snippet.lua и напомнить, как
                   заменить press-строки (файл сам не подключается)
  --with-udev      установить /etc/udev/rules.d/99-input-kit.rules (sudo)
  --with-keyd      установить /etc/keyd/zelotes-c18.conf (sudo)
  --with-apps      поставить apps-by-usage: клон плагина дока, в котором
                   сетка «Приложения» отсортирована по частоте запусков
  --uninstall      удалить lang-auto и сниппет; системные файлы удаляются
                   только вместе с --with-udev/--with-keyd
  --dry-run        показать команды, ничего не менять
  -h, --help       показать эту справку

Ничего не пишется в /usr/share/omarchy.
EOF
}

dry_run=false
with_switcher=false
with_udev=false
with_keyd=false
with_apps=false
uninstall=false

while (($#)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --dry-run)
      dry_run=true
      ;;
    --with-switcher)
      with_switcher=true
      ;;
    --with-udev)
      with_udev=true
      ;;
    --with-keyd)
      with_keyd=true
      ;;
    --with-apps)
      with_apps=true
      ;;
    --uninstall)
      uninstall=true
      ;;
    *)
      printf 'install.sh: неизвестный аргумент: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

run() {
  if [[ ${dry_run} == true ]]; then
    printf '  +'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

run_root() {
  if [[ ${EUID} -eq 0 ]]; then
    run "$@"
  elif command -v sudo >/dev/null 2>&1; then
    run sudo "$@"
  else
    printf 'ошибка: нужен root или sudo для: %s\n' "$*" >&2
    exit 1
  fi
}

if [[ ${uninstall} == true ]]; then
  printf 'Удаляю omarchy-tweaks\n'

  lang_args=(--uninstall)
  if [[ ${dry_run} == true ]]; then
    lang_args+=(--dry-run)
  fi
  run bash "${ROOT_DIR}/lang-auto/install.sh" "${lang_args[@]}"

  run rm -f "${HYPR_DIR}/bindings.snippet.lua"

  if [[ ${with_udev} == true ]]; then
    run_root rm -f /etc/udev/rules.d/99-input-kit.rules
    run_root udevadm control --reload-rules
    run_root udevadm trigger --subsystem-match=hidraw
  fi

  if [[ ${with_keyd} == true ]]; then
    run_root rm -f /etc/keyd/zelotes-c18.conf
    if command -v keyd >/dev/null 2>&1; then
      run_root keyd reload
    fi
  fi

  if [[ ${with_apps} == true ]]; then
    run omarchy plugin remove "${USER:-$(id -un)}.dock" --yes
  fi

  printf 'Готово\n'
  exit 0
fi

printf 'Устанавливаю lang-auto\n'
lang_args=()
if [[ ${dry_run} == true ]]; then
  lang_args+=(--dry-run)
fi
run bash "${ROOT_DIR}/lang-auto/install.sh" "${lang_args[@]}"

if [[ ${with_switcher} == true ]]; then
  printf 'Копирую сниппет switcher\n'
  run install -Dm644 "${ROOT_DIR}/switcher/bindings.snippet.lua" "${HYPR_DIR}/bindings.snippet.lua"
  printf '\nВажно: сниппет не подключается автоматически.\n'
  printf 'Замените четыре press-строки в %s\n' "${HYPR_DIR}/bindings.lua"
  printf 'на содержимое %s и выполните: hyprctl reload\n' "${HYPR_DIR}/bindings.snippet.lua"
fi

if [[ ${with_udev} == true ]]; then
  printf 'Устанавливаю udev-правило\n'
  run_root install -Dm644 "${ROOT_DIR}/devices/udev/99-input-kit.rules" /etc/udev/rules.d/99-input-kit.rules
  run_root udevadm control --reload-rules
  run_root udevadm trigger --subsystem-match=hidraw
  printf 'Проверка: getfacl -p /dev/hidraw0\n'
fi

if [[ ${with_keyd} == true ]]; then
  printf 'Устанавливаю конфигурацию keyd\n'
  run_root install -Dm644 "${ROOT_DIR}/devices/keyd/zelotes-c18.conf" /etc/keyd/zelotes-c18.conf
  if command -v keyd >/dev/null 2>&1; then
    run_root keyd reload
  else
    printf 'предупреждение: keyd не установлен; конфигурация скопирована, но не применена\n' >&2
  fi
fi

if [[ ${with_apps} == true ]]; then
  printf 'Устанавливаю apps-by-usage\n'
  apps_args=()
  if [[ ${dry_run} == true ]]; then
    apps_args+=(--dry-run)
  fi
  run bash "${ROOT_DIR}/apps-by-usage/install.sh" "${apps_args[@]}"
fi

printf '\nГотово. Проверка всего: bash %s/verify.sh\n' "${ROOT_DIR}"
printf 'Для строгой проверки ACL: bash %s/verify.sh --live\n' "${ROOT_DIR}"
