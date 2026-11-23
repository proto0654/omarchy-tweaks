#!/bin/bash

# Проверка apps-by-usage: клон на месте, патчи наложены, плагин включён,
# стоковый выключен.
#
#   bash verify.sh        итог OK/FAIL по каждому пункту
#   bash verify.sh -v     плюс найденные счётчики из журнала запусков

set -uo pipefail

USER_NAME=${USER:-$(id -un)}
CLONE_ID="$USER_NAME.dock"
CLONE_DIR="$HOME/.config/omarchy/plugins/$CLONE_ID"
USAGE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/app-launch-usage"
VERBOSE=0
[[ ${1:-} == -v || ${1:-} == --verbose ]] && VERBOSE=1

fail=0
ok()   { printf 'OK    %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }
note() { (( VERBOSE )) && printf '      %s\n' "$*"; return 0; }

if [[ -d $CLONE_DIR ]]; then ok "клон $CLONE_DIR на месте"; else bad "нет клона $CLONE_DIR (запустите install.sh)"; fi

if [[ -f $CLONE_DIR/AppGrid.qml ]] && grep -q 'appUsagePath' $CLONE_DIR/AppGrid.qml \
   && grep -q 'orderByUsage' $CLONE_DIR/AppGrid.qml \
   && grep -q 'recordAppLaunch' $CLONE_DIR/AppGrid.qml \
   && grep -q 'Util.execArgv' $CLONE_DIR/AppGrid.qml; then
  ok "AppGrid.qml: учёт запусков и сортировка по частоте"
else
  bad "AppGrid.qml не пропатчен"
fi

if [[ -f $CLONE_DIR/AppGrid.qml ]] && grep -q 'if (!root.filterText.trim()) rows = root.orderByUsage(rows)' $CLONE_DIR/AppGrid.qml; then
  ok "сортировка только для пустого поиска (поиск остаётся по релевантности)"
else
  bad "в AppGrid.qml нет вызова orderByUsage в rebuild()"
fi

if [[ -f $CLONE_DIR/Dock.qml ]] && grep -q 'stockConfigFile' $CLONE_DIR/Dock.qml \
   && grep -q 'root.shellConfig.dock' $CLONE_DIR/Dock.qml; then
  ok "Dock.qml: читает shell.json сам"
else
  bad "Dock.qml не пропатчен"
fi

if [[ -f $CLONE_DIR/manifest.json ]] && jq -e '.kinds | index("menu")' $CLONE_DIR/manifest.json >/dev/null 2>&1; then
  ok "manifest: kinds содержит menu (иначе шелл не выдаст app library)"
else
  bad "manifest.json без kind menu"
fi

if jq -e '.[] | select(.id|endswith(".dock")) | .enabled' <(omarchy-plugin-list --json 2>/dev/null) >/dev/null 2>&1; then
  ok "клон включён в шелле"
else
  bad "клон не включён (omarchy plugin enable $CLONE_ID)"
fi

if jq -e '.[] | select(.id == "omarchy.dock") | (.enabled|not)' <(omarchy-plugin-list --json 2>/dev/null) >/dev/null 2>&1; then
  ok "стоковый omarchy.dock выключен"
else
  bad "стоковый omarchy.dock всё ещё включён"
fi

if command -v omarchy-shell >/dev/null; then
  ok "omarchy-shell в PATH"
else
  bad "omarchy-shell не найден"
fi

if [[ -f $USAGE_LOG ]]; then
  total=$(wc -l < "$USAGE_LOG")
  note "журнал: $USAGE_LOG ($total строк)"
  if (( VERBOSE )); then
    while read -r n id; do printf '      %3d  %s\n' "$n" "$id"; done < <(sort "$USAGE_LOG" | uniq -c | sort -rn | head -8)
  fi
else
  note "журнала ещё нет: $USAGE_LOG (появится после первого запуска из сетки)"
fi

exit $fail
