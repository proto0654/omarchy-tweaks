#!/usr/bin/env bash
# Проверка switcher на живой системе Hyprland.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
readonly SNIPPET="${SCRIPT_DIR}/bindings.snippet.lua"

usage() {
  cat <<'EOF'
использование: verify.sh

Проверяет сниппет и живую конфигурацию Hyprland:
  - SHIFT + PAUSE/BREAK срабатывают на отпускании;
  - CTRL + code:127/419 срабатывают на нажатии;
  - дублирующих и старых привязок нет;
  - hyprctl -j configerrors пуст.

Параметры:
  -h, --help  показать эту справку
EOF
}

if (($#)); then
  case "$1" in
    -h | --help)
      usage
      exit 0
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

if ! command -v hyprctl >/dev/null 2>&1; then
  printf 'FAIL: hyprctl не найден, живая проверка невозможна\n' >&2
  exit 1
fi

if [[ ! -f ${SNIPPET} ]]; then
  fail "нет файла ${SNIPPET}"
else
  for combination in "SHIFT + PAUSE" "SHIFT + BREAK" "CTRL + code:127" "CTRL + code:419"; do
    if ! grep -Fq "\"${combination}\"" "${SNIPPET}"; then
      fail "в сниппете нет привязки ${combination}"
    fi
  done
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

# Hyprland с Lua показывает code:N в текстовом выводе, даже когда в JSON
# у такой привязки key пуст, а keycode равен нулю.
if ! hyprctl binds >"${tmp_dir}/binds.txt" 2>"${tmp_dir}/binds.err"; then
  fail "hyprctl binds не сработал: $(tr '\n' ' ' <"${tmp_dir}/binds.err")"
else
  if ! python3 - "${tmp_dir}/binds.txt" <<'PYVERIFY'
from collections import Counter
from pathlib import Path
import re
import sys

expected = Counter({(1, 'PAUSE', True): 1, (1, 'BREAK', True): 1,
                    (4, 'CODE:127', False): 1, (4, 'CODE:419', False): 1})
found = Counter()
output = Path(sys.argv[1]).read_text(encoding='utf-8')
for entry in re.split(r'(?m)(?=^bind[a-z]*$)', output):
    flags = re.match(r'bind([a-z]*)\n', entry)
    mask = re.search(r'(?m)^\s*modmask: (\d+)$', entry)
    key = re.search(r'(?m)^\s*key: (.+)$', entry)
    if not (flags and mask and key):
        continue
    mask = int(mask[1])
    name = key[1].split('+')[-1].strip().upper()
    if mask in (1, 4, 8) and name in ('PAUSE', 'BREAK', 'XF86BREAK', 'CODE:127', 'CODE:419'):
        found[(mask, name, 'r' in flags[1])] += 1

for (mask, name, release), count in (expected - found).items():
    print(f'FAIL: отсутствует привязка {name} (modmask={mask}, release={release})', file=sys.stderr)
for (mask, name, release), count in (found - expected).items():
    print(f'FAIL: лишних привязок {name} (modmask={mask}, release={release}): {count}', file=sys.stderr)
if found != expected:
    raise SystemExit(1)
print('OK: Shift срабатывает на отпускании, Ctrl на нажатии, дублей нет')
PYVERIFY
  then
    status=1
  fi
fi

if ! hyprctl -j configerrors >"${tmp_dir}/errors.json" 2>"${tmp_dir}/errors.err"; then
  fail "hyprctl -j configerrors не сработал: $(tr '\n' ' ' <"${tmp_dir}/errors.err")"
else
  if ! python3 - "${tmp_dir}/errors.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        errors = json.load(handle)
except (OSError, json.JSONDecodeError) as exc:
    print(f"FAIL: не удалось разобрать configerrors: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(errors, list):
    print("FAIL: configerrors вернул не список", file=sys.stderr)
    raise SystemExit(1)

real_errors = [str(item).strip() for item in errors if str(item).strip()]
if real_errors:
    print("FAIL: Hyprland сообщает об ошибках конфигурации:", file=sys.stderr)
    for error in real_errors:
        print(f"      {error}", file=sys.stderr)
    raise SystemExit(1)

print("OK: hyprctl configerrors пуст")
PY
  then
    status=1
  fi
fi

if [[ ${status} -ne 0 ]]; then
  printf 'switcher: FAIL\n' >&2
  exit 1
fi

printf 'switcher: OK\n'
