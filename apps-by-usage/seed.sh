#!/bin/bash

# Начальные счётчики для сетки приложений: чтобы верх сетки не был алфавитным,
# пока счётчики не набрались сами.
#
#   bash seed.sh            заполнить только если журнала ещё нет
#   bash seed.sh --force    перезаписать журнал этими счётчиками
#
# Дальше всё считается по реальным нажатиям в сетке, это разовый старт.

set -euo pipefail

USAGE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/app-launch-usage"
force=0
[[ ${1:-} == --force ]] && force=1

# id desktop-файла и сколько «нажатий» ему приписать; порядок = порядок в сетке
seed=(
  "hermes-desktop:6"
  "google-chrome:5"
  "org.telegram.desktop:4"
  "obsidian:3"
  "incy:2"
)

if [[ -s $USAGE_LOG ]] && (( ! force )); then
  echo "журнал уже не пуст: $USAGE_LOG"
  echo "перезаписать: bash seed.sh --force"
  exit 0
fi

mkdir -p "$(dirname "$USAGE_LOG")"
: > "$USAGE_LOG"
for item in "${seed[@]}"; do
  id=${item%:*}
  count=${item##*:}
  for (( i = 0; i < count; i++ )); do printf '%s\n' "$id" >> "$USAGE_LOG"; done
done

echo "записано в $USAGE_LOG:"
sort "$USAGE_LOG" | uniq -c | sort -rn | sed 's/^/  /'
echo "порядок применится при следующем открытии «Приложения»."
