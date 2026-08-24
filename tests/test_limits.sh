# Resource ceilings: a hostile or broken input must be refused, never half-reported.

log="$HOME/.local/share/adguard-cli/logs/access.log"

# A log with more distinct filter ids than the tally ceiling is malformed, not a busy day.
reset_state
today=$(date +%d.%m.%Y)
: >"$log"
for id in $(seq 1 200); do
  printf '%s 10:00:00 "curl" TLS - a%s.example.com - - any BLOCKED 1 ID=%s\n' "$today" "$id" "$id" >>"$log"
done
out=$("$helper" status)
assert_eq "an over-long tally is refused" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "a refused tally reports no count" "0" "$(printf '%s' "$out" | field blockedToday)"
assert_eq "a refused tally attributes nothing" "0" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print(sum(f["blocked"] for f in json.load(sys.stdin)["filters"]))')"

# A busy day within the ceiling still reports an exact count from the streaming pass.
reset_state
today=$(date +%d.%m.%Y)
: >"$log"
for _ in $(seq 1 5000); do
  printf '%s 10:00:00 "curl" TLS - ads.example.com - - any BLOCKED 1 ID=2\n' "$today" >>"$log"
done
out=$("$helper" status)
assert_eq "a busy day is counted exactly" "5000" "$(printf '%s' "$out" | field blockedToday)"
assert_eq "a busy day stays ok" "true" "$(printf '%s' "$out" | field ok)"
assert_eq "a busy day attributes to its filter" "5000" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print([f for f in json.load(sys.stdin)["filters"] if f["id"]==2][0]["blocked"])')"

# More filters than the whole AdGuard catalogue is a malformed reply from the CLI.
reset_state
: >"$STUB_STATE/filters"
for id in $(seq 1 200); do
  printf '%s|Filter %s|true|Ad blocking\n' "$id" "$id" >>"$STUB_STATE/filters"
done
out=$("$helper" status)
assert_eq "an over-long filter list is refused" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "the filter list is capped" "128" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["filters"]))')"

# A title longer than the JSON ceiling is truncated rather than passed through whole.
reset_state
long_title=$(printf 'T%.0s' $(seq 1 500))
printf '2|%s|true|Ad blocking\n' "$long_title" >"$STUB_STATE/filters"
out=$("$helper" status)
assert_eq "a long title is capped" "200" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["filters"][0]["title"]))')"
assert_eq "a capped title still parses" "0" \
  "$(printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1 && echo 0 || echo 1)"

unset today log long_title
