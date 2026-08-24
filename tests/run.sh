#!/usr/bin/env bash
# Plain bash runner: bats would add a dependency the plugin's users do not need.
set -uo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
export repo_root
export helper="$repo_root/bin/omarchy-adguard"
export stub_dir="$repo_root/tests/stubs"
# Stubs go on PATH here rather than in a test file, so no case depends on alphabetical ordering.
export PATH="$stub_dir:$PATH"
export STUB_STATE="$repo_root/tests/.work/state"
# The helper reads the access log out of HOME, so the suite must never see the real one.
export HOME="$repo_root/tests/.work/home"

tests_run=0
tests_failed=0

assert_eq() {
  local label=$1 expected=$2 actual=$3
  tests_run=$((tests_run + 1))
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok   %s\n' "$label"
  else
    tests_failed=$((tests_failed + 1))
    printf 'FAIL %s\n     expected: [%s]\n     actual:   [%s]\n' "$label" "$expected" "$actual"
  fi
}
export -f assert_eq

field() {
  python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin)[sys.argv[1]]))' "$1"
}
export -f field

reset_state() {
  rm -rf "$STUB_STATE" "$HOME"
  mkdir -p "$STUB_STATE" "$HOME/.local/share/adguard-cli/logs"
  printf 'true' >"$STUB_STATE/running"
  printf 'true' >"$STUB_STATE/https"
  cat >"$STUB_STATE/filters" <<'FILTERS'
2|AdGuard Base filter|true|Ad blocking
3|AdGuard Tracking Protection filter|true|Privacy
4|AdGuard Social Media filter|false|Social widgets
FILTERS
  unset STUB_REFUSE STUB_EXIT_NODE
}
export -f reset_state

# Two BLOCKED lines today and one yesterday, so a wrong date filter cannot pass.
seed_access_log() {
  local today yesterday log
  today=$(date +%d.%m.%Y)
  yesterday=$(date -d 'yesterday' +%d.%m.%Y 2>/dev/null || date -v-1d +%d.%m.%Y)
  log="$HOME/.local/share/adguard-cli/logs/access.log"
  {
    printf '%s 10:00:00 "curl" TLS - ads.example.com - - any BLOCKED 1 ID=2\n' "$today"
    printf '%s 10:00:01 "curl" TLS - example.com - - any NONE 0 -\n' "$today"
    printf '%s 10:00:02 "curl" TLS - ads2.example.com - - any BLOCKED 1 ID=2\n' "$today"
    printf '%s 09:00:00 "curl" TLS - old.example.com - - any BLOCKED 1 ID=2\n' "$yesterday"
  } >"$log"
}
export -f seed_access_log

for file in "$repo_root"/tests/test_*.sh; do
  # shellcheck disable=SC1090
  source "$file"
done

rm -rf "$repo_root/tests/.work"

printf '\n%d assertions, %d failed\n' "$tests_run" "$tests_failed"
[[ $tests_failed -eq 0 ]]
