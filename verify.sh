#!/usr/bin/env bash
# Проверка lang-auto на живой системе Omarchy.
set -euo pipefail

readonly BIN="${HOME}/.local/bin/lang-auto"
readonly SERVICE="lang-auto.service"

failures=0

ok() {
    printf '[OK]   %s\n' "$1"
}

bad() {
    printf '[FAIL] %s\n' "$1"
    failures=$((failures + 1))
}

usage() {
    cat <<'EOF'
verify.sh — проверка lang-auto на живой системе.

Проверяет:
  1. чтение раскладок (input:kb_layout);
  2. наличие клавиатуры и её active_keymap;
  3. служба lang-auto.service в статусе active;
  4. event-сокет Hyprland;
  5. запуск lang-auto --dry-run без ошибок.

Использование:
  ./verify.sh
  ./verify.sh --help

Итог: «ИТОГ: OK» (код 0) или «ИТОГ: FAIL (N)» (код 1).
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        ;;
    *)
        echo "Неизвестный аргумент: $1" >&2
        usage >&2
        exit 2
        ;;
esac

# 1. Раскладки из getoption.
layout_json="$(hyprctl -j getoption input:kb_layout 2>/dev/null || true)"
first_layout=""
if [[ -n "${layout_json}" ]]; then
    first_layout="$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
value = (data.get("str") or "").strip()
print(value.split(",")[0].strip() if value else "")
' <<<"${layout_json}" 2>/dev/null || true)"
fi

if [[ -n "${first_layout}" ]]; then
    ok "1. раскладки читаются, первая: ${first_layout}"
else
    bad "1. не удалось прочитать input:kb_layout"
fi

# 2. Клавиатуры из devices.
devices_json="$(hyprctl devices -j 2>/dev/null || true)"
keyboard_info=""
if [[ -n "${devices_json}" ]]; then
    keyboard_info="$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
keyboards = data.get("keyboards") or []
if not keyboards:
    sys.exit(0)
keyboard = keyboards[0]
name = keyboard.get("name") or "?"
keymap = keyboard.get("active_keymap") or "?"
print(f"{name} / {keymap}")
' <<<"${devices_json}" 2>/dev/null || true)"
fi

if [[ -n "${keyboard_info}" ]]; then
    ok "2. клавиатура: ${keyboard_info}"
else
    bad "2. клавиатуры не найдены (hyprctl devices -j)"
fi

# 3. Статус службы.
service_state="$(systemctl --user is-active "${SERVICE}" 2>/dev/null || true)"
if [[ "${service_state}" == "active" ]]; then
    ok "3. демон активен: ${SERVICE}"
else
    bad "3. демон не активен: ${SERVICE} (${service_state:-нет ответа})"
fi

# 4. Event-сокет Hyprland.
signature="${HYPRLAND_INSTANCE_SIGNATURE:-}"
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
socket_file="${runtime_dir}/hypr/${signature}/.socket2.sock"
if [[ -n "${signature}" && -S "${socket_file}" ]]; then
    ok "4. сокет: ${socket_file}"
else
    bad "4. сокет не найден: ${socket_file} (HYPRLAND_INSTANCE_SIGNATURE=${signature:-не задана})"
fi

# 5. Dry-run. Демон работает до остановки, поэтому 2 секунды и код 124 —
# нормальный результат; важно, чтобы не было падения и Traceback.
if [[ ! -x "${BIN}" ]]; then
    bad "5. не найден исполняемый файл ${BIN}"
else
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    rc=0
    timeout 2 "${BIN}" --dry-run >"${out_file}" 2>"${err_file}" || rc=$?
    if [[ "${rc}" -eq 0 || "${rc}" -eq 124 ]] && ! grep -q "Traceback" "${err_file}"; then
        ok "5. --dry-run проходит без ошибок"
    else
        bad "5. --dry-run завершился с кодом ${rc}"
    fi
    rm -f "${out_file}" "${err_file}"
fi

echo
if [[ "${failures}" -eq 0 ]]; then
    echo "ИТОГ: OK"
    exit 0
fi

echo "ИТОГ: FAIL (${failures})"
exit 1
