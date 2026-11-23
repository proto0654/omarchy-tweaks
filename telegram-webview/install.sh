#!/bin/bash

# telegram-webview: мини-апки Telegram открываются и нормально рисуются.
#
# Ставит два файла:
#   ~/.config/environment.d/90-webkit-dmabuf.conf  — для всех WebKitGTK-приложений
#   ~/.config/systemd/user/dbus-:1.1-org.telegram.desktop@.service.d/telegram-webview.conf
#                                                    — только для юнита Telegram
# и перезапускает Telegram, чтобы переменные подхватились.
#
# В /usr/share/omarchy/ ничего не пишется.

set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
ENV_FILE="$CONFIG_DIR/environment.d/90-webkit-dmabuf.conf"
UNIT_DIR="$CONFIG_DIR/systemd/user/dbus-:1.1-org.telegram.desktop@.service.d"
UNIT_FILE="$UNIT_DIR/telegram-webview.conf"
DRY_RUN=0
NO_RESTART=0
UNINSTALL=0

usage() {
  cat <<USAGE
Usage: ./install.sh [--dry-run] [--no-restart] [--uninstall]

  --dry-run     показать, что будет сделано, ничего не меняя
  --no-restart  не перезапускать Telegram в конце
  --uninstall   удалить оба файла и снять переменную из окружения systemd

Что ставится: два конфига (environment.d для всех WebKitGTK-приложений и
drop-in для юнита Telegram) — см. README, раздел «telegram-webview».
USAGE
}

while (($# > 0)); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-restart) NO_RESTART=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h | --help) usage; exit 0 ;;
    *)
      printf 'install.sh: неизвестный аргумент: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

run() {
  if [[ $DRY_RUN == 1 ]]; then
    printf '  +'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

telegram_units() {
  systemctl --user list-units --all --plain --no-legend 'dbus-:1.1-org.telegram*' 2>/dev/null |
    awk '{ print $1 }'
}

stop_telegram() {
  local unit
  for unit in $(telegram_units); do
    run systemctl --user stop "$unit"
  done
  # вебвью-хелперы живут отдельными процессами и переживают остановку юнита
  if pgrep -f 'webviewhelper[ ]/tmp' >/dev/null 2>&1; then
    run pkill -f 'webviewhelper[ ]/tmp' || true
  fi
}

start_telegram() {
  run busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus StartServiceByName su org.telegram.desktop 0
}

if [[ $UNINSTALL == 1 ]]; then
  printf 'Удаляю telegram-webview\n'
  stop_telegram
  run rm -f "$UNIT_FILE" "$ENV_FILE"
  run rmdir --ignore-fail-on-non-empty "$UNIT_DIR" 2>/dev/null || true
  run systemctl --user daemon-reload
  run systemctl --user unset-environment WEBKIT_DISABLE_DMABUF_RENDERER
  if [[ $NO_RESTART == 0 ]]; then
    start_telegram
  fi
  printf 'Готово\n'
  exit 0
fi

printf 'Устанавливаю telegram-webview\n'
run install -Dm644 "$HERE/90-webkit-dmabuf.conf" "$ENV_FILE"
run install -Dm644 "$HERE/dropin.conf" "$UNIT_FILE"

# environment.d подхватывается при логине; для текущей сессии ставим
# переменную в окружение systemd user manager — её получают dbus-активируемые
# приложения.
run systemctl --user set-environment WEBKIT_DISABLE_DMABUF_RENDERER=1
run systemctl --user daemon-reload

if [[ $NO_RESTART == 0 ]]; then
  stop_telegram
  sleep 1
  start_telegram
  sleep 5
fi

printf '\nПроверка: bash %s/verify.sh\n' "$HERE"
printf 'Мини-апку надо открыть руками: Mercuryo/Wallet/Zarub — любая с веб-интерфейсом.\n'
