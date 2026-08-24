# adguard-cli exits 0 whether or not it did the work, so each case asserts observed state.

reset_state
printf 'false' >"$STUB_STATE/running"
out=$("$helper" protection on)
assert_eq "protection on starts the proxy" "true" "$(printf '%s' "$out" | field running)"
assert_eq "protection on reports ok" "true" "$(printf '%s' "$out" | field ok)"

out=$("$helper" protection off)
assert_eq "protection off stops the proxy" "false" "$(printf '%s' "$out" | field running)"

# STUB_REFUSE makes every write a no-op while still exiting 0, the failure to catch.
reset_state
printf 'false' >"$STUB_STATE/running"
out=$(STUB_REFUSE=1 "$helper" protection on)
assert_eq "refused start is not reported ok" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "refused start names the failure" '"Could not start AdGuard filtering."' "$(printf '%s' "$out" | field error)"

reset_state
out=$(STUB_REFUSE=1 "$helper" protection off)
assert_eq "refused stop is not reported ok" "false" "$(printf '%s' "$out" | field ok)"

reset_state
assert_eq "an unknown command is refused" '"Unknown command."' "$("$helper" frobnicate | field error)"
assert_eq "a missing protection argument is refused" '"Unknown protection argument."' "$("$helper" protection | field error)"

# Every subcommand must still emit the full object, because the panel re-renders from it.
reset_state
assert_eq "a refused action still emits every field" "0" \
  "$("$helper" frobnicate | python3 -c 'import sys,json;d=json.load(sys.stdin);keys={"ok","installed","running","httpsFiltering","blockedToday","filters","exitNodeActive","error"};print(0 if keys<=set(d) else 1)')"

# This PATH holds only the coreutils the helper needs, since the box ships adguard-cli in /usr/bin.
reset_state
bare_path="$repo_root/tests/.work/barepath"
mkdir -p "$bare_path"
for tool in sed grep date; do ln -sf "$(command -v "$tool")" "$bare_path/$tool"; done
assert_eq "the bare PATH really has no adguard-cli" "absent" \
  "$(PATH="$bare_path" command -v adguard-cli >/dev/null 2>&1 && echo present || echo absent)"

out=$(PATH="$bare_path" "$helper" status)
assert_eq "missing adguard-cli reports installed false" "false" "$(printf '%s' "$out" | field installed)"
assert_eq "missing adguard-cli says why" '"AdGuard is not installed."' "$(printf '%s' "$out" | field error)"
assert_eq "missing adguard-cli still exits 0" "0" "$(PATH="$bare_path" "$helper" status >/dev/null 2>&1; echo $?)"
assert_eq "missing adguard-cli still emits valid JSON" "0" \
  "$(PATH="$bare_path" "$helper" status | python3 -m json.tool >/dev/null 2>&1 && echo 0 || echo 1)"

# The Update control shows what actually happened, so the summary must distinguish the cases.
reset_state
assert_eq "an unchanged check-update says so" '"Everything is already up to date"' \
  "$("$helper" update | field updateSummary)"
# The live success line is the four-token "1 DNS filter(s) updated", inverted by an earlier regex.
reset_state
assert_eq "a four-token refresh line is recognised" '"Filters updated"' \
  "$(STUB_UPDATED=1 "$helper" update | field updateSummary)"
reset_state
assert_eq "a zero count is not a refresh" '"Everything is already up to date"' \
  "$(STUB_UPDATED_ZERO=1 "$helper" update | field updateSummary)"
assert_eq "status alone never claims an update" '""' "$("$helper" status | field updateSummary)"

# Each of these reproduced against the pre-fix helper as ok:true with an empty error.
reset_state
out=$(STUB_FAIL=1 "$helper" status)
assert_eq "a failing CLI is not reported ok" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "a failing CLI names the read that failed" '"adguard-cli status failed."' "$(printf '%s' "$out" | field error)"
assert_eq "a failing CLI still emits valid JSON" "0" \
  "$(STUB_FAIL=1 "$helper" status | python3 -m json.tool >/dev/null 2>&1 && echo 0 || echo 1)"
assert_eq "a failing CLI still exits 0" "0" "$(STUB_FAIL=1 "$helper" status >/dev/null 2>&1; echo $?)"

reset_state
out=$(STUB_FAIL=1 "$helper" update)
assert_eq "a failed update is not reported as up to date" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "a failed update says so" '"Could not check for filter updates."' "$(printf '%s' "$out" | field error)"
assert_eq "a failed update claims no summary" '""' "$(printf '%s' "$out" | field updateSummary)"

# A control byte in a remote title used to make the whole document unparseable.
reset_state
# Read the stub's own bytes, so a stub that stopped injecting turns this red.
assert_eq "the stub really emits a control byte" "1" \
  "$(STUB_CTRL=1 adguard-cli filters list | python3 -c 'import sys
raw = sys.stdin.buffer.read()
print(1 if any(b < 32 and b not in (9, 10, 13) for b in raw) else 0)')"
assert_eq "a control byte in a title still parses" "0" \
  "$(STUB_CTRL=1 "$helper" status | python3 -m json.tool >/dev/null 2>&1 && echo 0 || echo 1)"
assert_eq "the control byte is stripped from the title" "0" \
  "$(STUB_CTRL=1 "$helper" status | python3 -c 'import sys,json
bad = [f for f in json.load(sys.stdin)["filters"] if any(ord(c) < 32 for c in f["title"])]
print(len(bad))')"
reset_state
# Pairs with the case above: the prefix is absent when nothing is injected.
assert_eq "no hostile prefix appears without the stub flag" "0" \
  "$("$helper" status | python3 -c 'import sys,json
print(sum(1 for f in json.load(sys.stdin)["filters"] if f["title"].startswith("Bad")))')"

# The three branches added while fixing the rounds above, each reachable and each asserted.
reset_state
assert_eq "output this version cannot classify is not called up to date" '"Filters checked"' \
  "$(STUB_UPDATED_ODD=1 "$helper" update | field updateSummary)"

# A directory at the log path passes -e and -r, and GNU grep exits 2 on it.
reset_state
rm -f "$HOME/.local/share/adguard-cli/logs/access.log"
mkdir -p "$HOME/.local/share/adguard-cli/logs/access.log"
out=$("$helper" status)
assert_eq "a log grep cannot read is not a zero" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "an unreadable log says so" '"Could not read the AdGuard access log."' "$(printf '%s' "$out" | field error)"
rmdir "$HOME/.local/share/adguard-cli/logs/access.log"

# An existing log with no read permission returns before grep, so it needs its own case.
reset_state
seed_access_log
chmod 000 "$HOME/.local/share/adguard-cli/logs/access.log"
out=$("$helper" status)
assert_eq "an unreadable existing log is not a zero" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "a permission fault names the log" '"Could not read the AdGuard access log."' "$(printf '%s' "$out" | field error)"
chmod 644 "$HOME/.local/share/adguard-cli/logs/access.log"

# A log that is simply absent is a real zero and must stay quiet.
reset_state
assert_eq "an absent log is a real zero" "true" "$("$helper" status | field ok)"
assert_eq "an absent log reports no blocks" "0" "$("$helper" status | field blockedToday)"

# A counted line only means a refresh when it also says updated, or "3 lists could not be
# reached" would read as a successful update.
reset_state
assert_eq "a counted line that is not a success is not a refresh" '"Everything is already up to date"' \
  "$(STUB_UPDATED_COUNTED_NONSUCCESS=1 "$helper" update | field updateSummary)"
