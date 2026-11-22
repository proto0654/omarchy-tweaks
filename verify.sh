#!/usr/bin/env bash
# Запускает все три проверки и печатает итог по каждой части.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly ROOT_DIR

usage() {
  cat <<'EOF'
использование: verify.sh [--live]

Запускает проверки:
  lang-auto/verify.sh  — синтаксис, справка и живой запуск демона;
  switcher/verify.sh   — release-привязки в живом Hyprland;
  devices/verify.sh    — udev, keyd и наличие интерфейсов устройств.

Параметры:
  --live      для devices дополнительно требовать uaccess-ACL;
  -h, --help  показать эту справку

Итог печатается как OK или FAIL по каждой части.
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

overall=0

run_part() {
  local part="$1"
  shift
  printf '\n=== %s ===\n' "${part}"
  if bash "${ROOT_DIR}/${part}/verify.sh" "$@"; then
    printf '%s: OK\n' "${part}"
  else
    printf '%s: FAIL\n' "${part}" >&2
    overall=1
  fi
}

run_part lang-auto
run_part switcher

if [[ ${live} == true ]]; then
  run_part devices --live
else
  run_part devices
fi

printf '\n'
if [[ ${overall} -eq 0 ]]; then
  printf 'Итог: OK — все три части прошли проверку\n'
else
  printf 'Итог: FAIL — есть непрошедшие проверки (см. вывод выше)\n' >&2
fi

exit "${overall}"
