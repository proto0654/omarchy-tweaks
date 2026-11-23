#!/bin/bash

# Проверка telegram-webview: конфиги на месте, у живого Telegram в окружении
# правильные переменные, SHM-костыль не включён, свежих крашей нет.
#
#   bash verify.sh        итог OK/FAIL по каждому пункту
#   bash verify.sh -q     только итог

set -uo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
ENV_FILE="$CONFIG_DIR/environment.d/90-webkit-dmabuf.conf"
UNIT_FILE="$CONFIG_DIR/systemd/user/dbus-:1.1-org.telegram.desktop@.service.d/telegram-webview.conf"
EGL_MESA="/usr/share/glvnd/egl_vendor.d/50_mesa.json"
QUIET=0
[[ ${1:-} == -q || ${1:-} == --quiet ]] && QUIET=1

fail=0
ok() { ((QUIET)) || printf 'OK    %s\n' "$*"; }
bad() { printf 'FAIL  %s\n' "$*"; fail=1; }
warn() { printf 'WARN  %s\n' "$*"; }

if [[ -f $ENV_FILE ]] && grep -q '^WEBKIT_DISABLE_DMABUF_RENDERER=1$' "$ENV_FILE"; then
  ok "environment.d: глобальный WEBKIT_DISABLE_DMABUF_RENDERER=1 на месте"
else
  bad "нет $ENV_FILE с WEBKIT_DISABLE_DMABUF_RENDERER=1"
fi

if [[ -f $UNIT_FILE ]]; then
  ok "drop-in юнита Telegram на месте"
else
  bad "нет $UNIT_FILE"
fi

if [[ -f $UNIT_FILE ]] && grep -q "^Environment=__EGL_VENDOR_LIBRARY_FILENAMES=$EGL_MESA$" "$UNIT_FILE"; then
  ok "EGL на Mesa (Intel iGPU) задан для Telegram"
else
  bad "в drop-in нет __EGL_VENDOR_LIBRARY_FILENAMES=$EGL_MESA"
fi

if [[ -f $UNIT_FILE ]] && grep -q '^UnsetEnvironment=WEBKIT_DISABLE_DMABUF_RENDERER$' "$UNIT_FILE"; then
  ok "SHM-костыль отключён именно для Telegram"
else
  bad "drop-in не снимает WEBKIT_DISABLE_DMABUF_RENDERER (мини-апка будет рисоваться частями)"
fi

if [[ -f $UNIT_FILE ]] && grep -q '^Environment=GDK_SCALE=1$' "$UNIT_FILE"; then
  ok "GDK_SCALE=1 для окна мини-апки"
else
  warn "GDK_SCALE не задан: окно мини-апки будет вдвое крупнее"
fi

pid=$(pgrep -x Telegram | head -1 || true)
if [[ -n ${pid} ]]; then
  env_dump=$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null || true)
  if grep -qx "WEBKIT_DISABLE_DMABUF_RENDERER=1" <<<"$env_dump"; then
    bad "у запущенного Telegram (pid $pid) всё ещё WEBKIT_DISABLE_DMABUF_RENDERER=1 — перезапустите его"
  else
    ok "у живого Telegram (pid $pid) SHM-костыля нет"
  fi
  if grep -qx "__EGL_VENDOR_LIBRARY_FILENAMES=$EGL_MESA" <<<"$env_dump"; then
    ok "у живого Telegram EGL на Mesa"
  else
    bad "у живого Telegram нет __EGL_VENDOR_LIBRARY_FILENAMES"
  fi
else
  warn "Telegram не запущен — проверены только файлы"
fi

if command -v coredumpctl >/dev/null 2>&1; then
  if coredumpctl list --since '1 day ago' 2>/dev/null | grep -q '/usr/bin/Telegram'; then
    warn "за сутки есть core dump Telegram: coredumpctl list | grep Telegram"
  else
    ok "за сутки Telegram не падал"
  fi
fi

if ((fail)); then
  printf 'telegram-webview: FAIL\n'
  exit 1
fi
((QUIET)) || printf 'telegram-webview: OK\n'
