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
  - в bindings.snippet.lua четыре привязки с release = true;
  - hyprctl -j binds показывает SHIFT/ALT + PAUSE/BREAK с release;
  - старых press-привязок на этих клавишах нет;
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
  release_count="$(grep -c 'release = true' "${SNIPPET}" || true)"
  if [[ ${release_count} -ne 4 ]]; then
    fail "в сниппете ${release_count} привязок release = true, ожидалось 4"
  else
    ok "в сниппете четыре привязки release = true"
  fi

  for combination in "SHIFT + PAUSE" "SHIFT + BREAK" "ALT + PAUSE" "ALT + BREAK"; do
    if ! grep -Fq "\"${combination}\"" "${SNIPPET}"; then
      fail "в сниппете нет привязки ${combination}"
    fi
  done
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

if ! hyprctl -j binds >"${tmp_dir}/binds.json" 2>"${tmp_dir}/binds.err"; then
  fail "hyprctl -j binds не сработал: $(tr '\n' ' ' <"${tmp_dir}/binds.err")"
else
  if ! python3 - "${tmp_dir}/binds.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        binds = json.load(handle)
except (OSError, json.JSONDecodeError) as exc:
    print(f"FAIL: не удалось разобрать hyprctl -j binds: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not isinstance(binds, list):
    print("FAIL: hyprctl -j binds вернул не список", file=sys.stderr)
    raise SystemExit(1)

# modmask: Shift = 1, Alt = 8 (так их печатает Hyprland).
expected = {("PAUSE", 1), ("BREAK", 1), ("PAUSE", 8), ("BREAK", 8)}
release_found = set()
press_found = set()

for bind in binds:
    if not isinstance(bind, dict):
        continue
    key = str(bind.get("key") or "")
    if key not in ("PAUSE", "BREAK"):
        continue
    mask = bind.get("modmask")
    if mask not in (1, 8):
        continue
    pair = (key, mask)
    if bind.get("release") is True:
        release_found.add(pair)
    else:
        press_found.add(pair)

missing = sorted(expected - release_found)
if missing:
    names = ", ".join(f"{key} (modmask {mask})" for key, mask in missing)
    print(f"FAIL: нет release-привязок: {names}", file=sys.stderr)
    print("      добавьте блок из bindings.snippet.lua в ~/.config/hypr/bindings.lua", file=sys.stderr)
    print("      и выполните: hyprctl reload", file=sys.stderr)

if press_found:
    names = ", ".join(f"{key} (modmask {mask})" for key, mask in sorted(press_found))
    print(f"FAIL: старые press-привязки всё ещё загружены: {names}", file=sys.stderr)
    print("      они сработают вместе с release-привязками; оставьте только release", file=sys.stderr)

if missing or press_found:
    raise SystemExit(1)

print("OK: release-привязки SHIFT/ALT + PAUSE/BREAK загружены, press-дублей нет")
PY
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
