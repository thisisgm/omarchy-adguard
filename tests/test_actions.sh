# Actions, and the refusals they must notice. adguard-cli exits 0 whether or not it did the
# work, so every case here asserts the state the helper observed rather than a status code.

reset_state
printf 'false' >"$STUB_STATE/running"
out=$("$helper" protection on)
assert_eq "protection on starts the proxy" "true" "$(printf '%s' "$out" | field running)"
assert_eq "protection on reports ok" "true" "$(printf '%s' "$out" | field ok)"

out=$("$helper" protection off)
assert_eq "protection off stops the proxy" "false" "$(printf '%s' "$out" | field running)"

reset_state
out=$("$helper" https off)
assert_eq "https off turns filtering off" "false" "$(printf '%s' "$out" | field httpsFiltering)"
out=$("$helper" https on)
assert_eq "https on turns filtering on" "true" "$(printf '%s' "$out" | field httpsFiltering)"

reset_state
out=$("$helper" filter enable 4)
assert_eq "filter enable flips that filter" "True" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print([f for f in json.load(sys.stdin)["filters"] if f["id"]==4][0]["enabled"])')"
assert_eq "filter enable leaves the others alone" "True" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print([f for f in json.load(sys.stdin)["filters"] if f["id"]==2][0]["enabled"])')"

out=$("$helper" filter disable 2)
assert_eq "filter disable flips only its own filter" "False" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print([f for f in json.load(sys.stdin)["filters"] if f["id"]==2][0]["enabled"])')"
assert_eq "a later enabled filter is not mistaken for this one" "True" \
  "$(printf '%s' "$out" | python3 -c 'import sys,json;print([f for f in json.load(sys.stdin)["filters"] if f["id"]==4][0]["enabled"])')"

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
out=$(STUB_REFUSE=1 "$helper" https off)
assert_eq "refused https change is caught" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "refused https change names the failure" '"Could not turn HTTPS filtering off."' "$(printf '%s' "$out" | field error)"

reset_state
out=$(STUB_REFUSE=1 "$helper" filter enable 4)
assert_eq "refused filter enable is caught" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "refused filter enable names the failure" '"Could not enable that filter."' "$(printf '%s' "$out" | field error)"

# Trust boundary: the id comes from the panel and reaches a command line.
reset_state
out=$("$helper" filter enable '4; touch /tmp/adguard-test-pwned')
assert_eq "a non-numeric filter id is refused" "false" "$(printf '%s' "$out" | field ok)"
assert_eq "a non-numeric filter id says why" '"Filter id must be a number."' "$(printf '%s' "$out" | field error)"
assert_eq "the injected command never ran" "absent" "$([[ -e /tmp/adguard-test-pwned ]] && echo present || echo absent)"

reset_state
assert_eq "an unknown command is refused" '"Unknown command."' "$("$helper" frobnicate | field error)"
assert_eq "an unknown filter action is refused" '"Unknown filter action."' "$("$helper" filter sideways 4 | field error)"
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
