# Status reading: every field the panel binds to, plus the shapes that must not be mistaken.

reset_state
seed_access_log
out=$("$helper" status)

assert_eq "status is valid JSON" "0" "$(printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1 && echo 0 || echo 1)"
assert_eq "ok when nothing failed" "true" "$(printf '%s' "$out" | field ok)"
assert_eq "installed" "true" "$(printf '%s' "$out" | field installed)"
assert_eq "running" "true" "$(printf '%s' "$out" | field running)"
assert_eq "httpsFiltering" "true" "$(printf '%s' "$out" | field httpsFiltering)"
assert_eq "error is empty" '""' "$(printf '%s' "$out" | field error)"

# Yesterday's BLOCKED line and today's NONE line must both be excluded.
assert_eq "blockedToday counts only today's blocks" "2" "$(printf '%s' "$out" | field blockedToday)"

assert_eq "three filters parsed" "3" "$(printf '%s' "$out" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["filters"]))')"
assert_eq "filter title has no timestamp column" '"AdGuard Base filter"' \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.dumps(json.load(sys.stdin)["filters"][0]["title"]))')"
assert_eq "disabled filter reads as disabled" "False" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print([f for f in json.load(sys.stdin)["filters"] if f["id"]==4][0]["enabled"])')"
assert_eq "disabled filter title drops the 'Filter is disabled' column" '"AdGuard Social Media filter"' \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print(json.dumps([f for f in json.load(sys.stdin)["filters"] if f["id"]==4][0]["title"]))')"

# The idle peer line says "offers exit node" and must not register as an active one.
assert_eq "idle tailscale peer is not a conflict" "false" "$(printf '%s' "$out" | field exitNodeActive)"
STUB_EXIT_NODE=1 assert_eq "active exit node is a conflict" "true" \
  "$(STUB_EXIT_NODE=1 "$helper" status | field exitNodeActive)"

# A stopped proxy is still a fully readable state, not an error.
reset_state
printf 'false' >"$STUB_STATE/running"
out=$("$helper" status)
assert_eq "stopped proxy still reports ok" "true" "$(printf '%s' "$out" | field ok)"
assert_eq "stopped proxy reports running false" "false" "$(printf '%s' "$out" | field running)"

# No access log at all is a legitimate zero rather than a failure.
reset_state
out=$("$helper" status)
assert_eq "missing access log gives zero, not an error" "0" "$(printf '%s' "$out" | field blockedToday)"
assert_eq "missing access log keeps ok true" "true" "$(printf '%s' "$out" | field ok)"

# An empty filter set must round-trip as an empty array, since the panel renders a message for it.
reset_state
: >"$STUB_STATE/filters"
out=$("$helper" status)
assert_eq "no filters gives an empty array" "[]" "$(printf '%s' "$out" | field filters)"
