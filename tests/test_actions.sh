# Actions, and the refusals they must notice. adguard-cli exits 0 whether or not it did the
# work, so every case here asserts the state the helper observed rather than a status code.

reset_state
printf 'false' >"$STUB_STATE/running"
out=$("$helper" protection on)
assert_eq "protection on starts the proxy" "true" "$(printf '%s' "$out" | field running)"
assert_eq "protection on reports ok" "true" "$(printf '%s' "$out" | field ok)"

out=$("$helper" protection off)
assert_eq "protection off stops the proxy" "false" "$(printf '%s' "$out" | field running)"

# The refusal cases. STUB_REFUSE makes every write a no-op while still exiting 0, which is
# exactly the failure the helper must not report as success.
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

# Absent AdGuard is the self-hide signal, so it must be reported rather than crashed on.
# The PATH here holds only the coreutils the helper needs, because this box really does
# ship adguard-cli in /usr/bin and a coarser PATH would still find it.
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
reset_state
assert_eq "a real refresh says so instead" '"Filters updated"' \
  "$(STUB_UPDATED=1 "$helper" update | field updateSummary)"
assert_eq "status alone never claims an update" '""' "$("$helper" status | field updateSummary)"

# A failing adguard-cli must be reported, never rendered as a healthy zero. Each of these
# reproduced against the pre-fix helper as ok:true with an empty error.
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

# A control byte in a remote-sourced title used to make the whole document unparseable.
reset_state
assert_eq "a control byte in a title still parses" "0" \
  "$(STUB_CTRL=1 "$helper" status | python3 -m json.tool >/dev/null 2>&1 && echo 0 || echo 1)"
assert_eq "the control byte is stripped from the title" "0" \
  "$(STUB_CTRL=1 "$helper" status | python3 -c 'import sys,json
bad = [f for f in json.load(sys.stdin)["filters"] if any(ord(c) < 32 for c in f["title"])]
print(len(bad))')"
