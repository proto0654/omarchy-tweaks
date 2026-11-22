#!/usr/bin/env bash
# Проверка lang-auto: синтаксис, справка, живой Hyprland и установка.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SCRIPT_DIR
readonly PROGRAM="${SCRIPT_DIR}/lang-auto"
readonly UNIT="${SCRIPT_DIR}/lang-auto.service"
readonly INSTALLED="${HOME}/.local/bin/lang-auto"

usage() {
  cat <<'EOF'
использование: verify.sh

Проверяет:
  - python3 -m py_compile для lang-auto;
  - русскую справку lang-auto --help;
  - lang-auto --once на живом Hyprland;
  - запуск --dry-run без Traceback;
  - unit-файл и ExecStart;
  - состояние установленной службы (предупреждение, не ошибка).

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
warn() {
  printf 'ПРЕДУПРЕЖДЕНИЕ: %s\n' "$*" >&2
}

if [[ ! -x ${PROGRAM} ]]; then
  fail "${PROGRAM} не найден или не исполняемый"
  printf 'lang-auto: FAIL\n' >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

if PYTHONPYCACHEPREFIX="${tmp_dir}/pycache" python3 -m py_compile "${PROGRAM}"; then
  ok "python3 -m py_compile"
else
  fail "python3 -m py_compile"
fi

help_text="$("${PROGRAM}" --help 2>&1 || true)"
if grep -Fq 'использование:' <<<"${help_text}" && grep -Fq 'параметры:' <<<"${help_text}"; then
  ok "lang-auto --help: русская справка"
else
  fail "lang-auto --help не печатает русскую справку"
fi

if "${PROGRAM}" --once >"${tmp_dir}/once.out" 2>"${tmp_dir}/once.err"; then
  ok "lang-auto --once"
else
  fail "lang-auto --once завершился ошибкой"
  sed 's/^/      /' "${tmp_dir}/once.err" >&2 || true
fi

if command -v timeout >/dev/null 2>&1; then
  rc=0
  timeout 1 "${PROGRAM}" --dry-run >"${tmp_dir}/dry.out" 2>"${tmp_dir}/dry.err" || rc=$?
  if [[ ${rc} -eq 0 || ${rc} -eq 124 ]] && ! grep -Fq 'Traceback' "${tmp_dir}/dry.err"; then
    ok "lang-auto --dry-run (без Traceback)"
  else
    fail "lang-auto --dry-run завершился с кодом ${rc}"
  fi
else
  warn "timeout не найден, --dry-run не проверен"
fi

if [[ -f ${UNIT} ]] && grep -Fq 'ExecStart=%h/.local/bin/lang-auto' "${UNIT}"; then
  ok "unit lang-auto.service"
else
  fail "в ${UNIT} нет ExecStart=%h/.local/bin/lang-auto"
fi

if [[ -x ${INSTALLED} ]]; then
  ok "установлен ${INSTALLED}"
else
  warn "lang-auto не установлен в ${INSTALLED} (запустите lang-auto/install.sh)"
fi

service_state="$(systemctl --user is-active lang-auto.service 2>/dev/null || true)"
if [[ ${service_state} == "active" ]]; then
  ok "служба lang-auto.service активна"
else
  warn "служба lang-auto.service не активна (${service_state:-нет ответа})"
fi

if [[ ${status} -ne 0 ]]; then
  printf 'lang-auto: FAIL\n' >&2
  exit 1
fi

printf 'lang-auto: OK\n'
