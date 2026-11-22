#!/usr/bin/env bash
# Установка и удаление lang-auto (systemd user unit).
set -euo pipefail

readonly UNIT_NAME="lang-auto.service"
readonly BIN_DIR="${HOME}/.local/bin"
readonly UNIT_DIR="${HOME}/.config/systemd/user"
readonly SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
install.sh — установка lang-auto.

Использование:
  ./install.sh              установить в ~/.local/bin и запустить службу
  ./install.sh --uninstall  остановить службу и удалить unit и бинарь
  ./install.sh --help       показать эту справку

Файлы:
  ~/.local/bin/lang-auto
  ~/.config/systemd/user/lang-auto.service
EOF
}

install_lang_auto() {
    install -Dm755 "${SRC_DIR}/lang-auto" "${BIN_DIR}/lang-auto"
    install -Dm644 "${SRC_DIR}/lang-auto.service" "${UNIT_DIR}/${UNIT_NAME}"

    systemctl --user daemon-reload
    systemctl --user enable --now "${UNIT_NAME}"

    echo "Установлено: ${BIN_DIR}/lang-auto"
    echo "Служба запущена: ${UNIT_NAME}"
    echo "Проверка: ./verify.sh"
}

uninstall_lang_auto() {
    # Служба может быть уже отключена — это не ошибка.
    systemctl --user disable --now "${UNIT_NAME}" 2>/dev/null || true
    rm -f "${UNIT_DIR}/${UNIT_NAME}" "${BIN_DIR}/lang-auto"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "lang-auto удалён."
}

case "${1:-}" in
    "")
        install_lang_auto
        ;;
    --uninstall)
        uninstall_lang_auto
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo "Неизвестный аргумент: $1" >&2
        usage >&2
        exit 2
        ;;
esac
