#!/bin/bash

# apps-by-usage: приложения в стартовом меню Omarchy (Приложения -> сетка)
# сортируются по числу запусков ИМЕННО ИЗ ЭТОЙ СЕТКИ, а не по глобальной
# статистике. Первая плитка — самая частая, и фокус при открытии стоит на ней.
#
# Ставится как клон плагина omarchy.dock (<user>.dock) с двумя патчами:
#   AppGrid.qml — учёт запусков + сортировка
#   Dock.qml    — клон читает shell.json сам (scoped shell его не отдаёт)
# и правкой manifest.json: kinds += "menu" (только так шелл выдаёт клону
# app library через прокси).
#
# В /usr/share/omarchy/ ничего не пишется.

set -euo pipefail

USER_NAME=${USER:-$(id -un)}
CLONE_ID="$USER_NAME.dock"
CLONE_DIR="$HOME/.config/omarchy/plugins/$CLONE_ID"
STOCK_DIR="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins/dock"
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY_RUN=0
NO_RESTART=0

usage() {
  cat <<USAGE
Usage: ./install.sh [--dry-run] [--no-restart]

  --dry-run     показать, что будет сделано, ничего не меняя
  --no-restart  не перезапускать omarchy-shell в конце (изменения подхватятся
                при следующем запуске шелла)

Клонирует плагин omarchy.dock в ~/.config/omarchy/plugins/$CLONE_ID и накладывает
патчи из этого каталога.
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-restart) NO_RESTART=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: неизвестный аргумент: $1" >&2; exit 2 ;;
  esac
  shift
done

run() {
  if (( DRY_RUN )); then
    printf '  + %s\n' "$*"
  else
    "$@"
  fi
}

say() { printf '== %s\n' "$*"; }
die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

command -v omarchy >/dev/null || die "omarchy не найден в PATH"
command -v jq >/dev/null || die "нужен jq"
command -v patch >/dev/null || die "нужен patch"
[[ -d $STOCK_DIR ]] || die "нет $STOCK_DIR"

say "клон плагина: $CLONE_DIR"
if [[ -d $CLONE_DIR ]]; then
  echo "  уже существует, не клонирую заново"
else
  run omarchy plugin clone omarchy.dock
  [[ -d $CLONE_DIR ]] || die "клон не создался (omarchy-shell не ответил? повторите запуск)"
fi

say "патчи"
for p in AppGrid Dock; do
  target="$CLONE_DIR/$p.qml"
  [[ -f $target ]] || die "нет файла $target"
  if grep -q 'appUsage' "$target" 2>/dev/null || grep -q 'stockConfigFile' "$target" 2>/dev/null; then
    echo "  $p.qml: уже пропатчен, пропускаю"
    continue
  fi
  if (( DRY_RUN )); then
    echo "  + patch -p1 -d $CLONE_DIR < $p.patch"
  else
    if ! patch -p1 --forward --batch -d "$CLONE_DIR" < "$HERE/$p.patch"; then
      die "$p.patch не наложился — похоже, стоковый файл изменился после обновления Omarchy. Обновите патч."
    fi
  fi
done

say "manifest: kinds += menu"
manifest="$CLONE_DIR/manifest.json"
if [[ -f $manifest ]]; then
  if (( DRY_RUN )); then
    echo "  + jq kinds |= unique + [\"menu\"]"
  else
    tmp=$(mktemp)
    jq '.kinds = ((.kinds // []) + ["menu"] | unique)' "$manifest" > "$tmp"
    mv "$tmp" "$manifest"
  fi
else
  echo "  manifest.json не найден — пропускаю"
fi

if (( NO_RESTART || DRY_RUN )); then
  say "готово (шелл не перезапускаю)"
else
  say "перезапуск omarchy-shell"
  omarchy restart shell >/dev/null 2>&1 || echo "  (перезапустите вручную: omarchy restart shell)"
fi

cat <<'DONE'

Готово. Проверка: bash verify.sh
Начальные счётчики (по желанию): bash seed.sh
DONE
