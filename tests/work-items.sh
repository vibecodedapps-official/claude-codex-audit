#!/bin/sh
# work-items.sh: tests for skills/cca/scripts/work-items.sh.
#
# Usage: sh tests/work-items.sh
#
# Writes a small report body, a claims.md, and a valid work-items.jsonl in a temp
# directory, then compares the output and exit status of `check` with literals for the
# valid file and for each broken copy. The literal line numbers are the line numbers of
# the valid file written below. Prints one line per mismatch and `work-items test: ok`
# on success; exits 1 on any mismatch. When jq is missing it prints a note and exits 0.
set -u

if ! command -v jq >/dev/null 2>&1; then
	echo "work-items test: note: jq not found, nothing was tested"
	exit 0
fi

root=$(cd "$(dirname "$0")/.." && pwd)
ws=$root/skills/cca/scripts/work-items.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

nl='
'

fails=0
fail() {
	echo "work-items test: $*"
	fails=$((fails + 1))
}

cat > "$tmp/body.md" <<'EOF'
# cca audit report: 2026-09-01-0900

## 2. Findings

#### C1: Deactivate deletes the row
Text.

#### C2: A skipped test hides it
Text.
EOF

cat > "$tmp/claims.md" <<'EOF'
# Claims

1. [claim:code] app/APP-1 handoff.md:14 (tickets/APP-1/problem): The row is deleted. -> g1
2. [claim:verification] app/APP-1 handoff.md:27 (tickets/APP-1/verified/2): The suite runs. -> g1
3. [other] none/none notes.md:2: Hello. -> none
EOF

cat > "$tmp/valid.jsonl" <<'EOF'
{"run":"2026-09-01-0900","id":"W1","op":"create","target":"$new:follow-up","items":["C1"],"reason":"Track the fix.","key":"follow-up","type":"Bug","title":"Deactivate keeps the row","description":"The command deletes the row.","fields":{"priority":"high"},"links":[{"type":"related","to":"owner/repo#4"}]}
{"run":"2026-09-01-0900","id":"W2","op":"add_link","target":"owner/repo#4","items":["C1","claim 1"],"reason":"Link the two.","link_type":"related","to":"$new:follow-up"}
{"run":"2026-09-01-0900","id":"W3","op":"add_comment","target":"$new:follow-up","target_url":"https://tickets.example.invalid/browse/APP-9","items":["C2"],"reason":"Say why.","text":"The test is skipped."}
{"run":"2026-09-01-0900","id":"W4","op":"set_field","target":"owner/repo#4","items":["claim 2"],"reason":"Raise it.","field":"priority","value":"high"}
{"run":"2026-09-01-0900","id":"W5","op":"set_state","target":"owner/repo#4","items":["C1"],"reason":"Reopen.","value":"Active"}
{"run":"2026-09-01-0900","id":"W6","op":"set_description","target":"owner/repo#4","items":["C1"],"reason":"Fix the text.","text":"New text."}
{"run":"2026-09-01-0900","id":"W7","op":"set_acceptance_criteria","target":"owner/repo#4","items":["C1"],"reason":"Add one.","text":"The row stays."}
{"run":"2026-09-01-0900","id":"W8","op":"set_pr_description","target":"owner/repo#7","items":["C2"],"reason":"Describe it.","text":"Notes."}
{"run":"2026-09-01-0900","id":"W9","op":"update_comment","target":"owner/repo#4","items":["C1"],"reason":"Correct it.","comment_id":"c-17","text":"Thanks {mention:owner}, fixed.","mentions":[{"name":"Pat Lee","placeholder":"{mention:owner}"}]}
{"run":"2026-09-01-0900","id":"W10","op":"remove_link","target":"owner/repo#4","items":["claim 1"],"reason":"Wrong link.","link_type":"related","to":"owner/repo#5"}
{"run":"2026-09-01-0900","id":"W11","op":"set_fields","target":"owner/repo#4","items":["W12"],"reason":"Needed before the state change.","fields":{"resolution":"fixed"}}
{"run":"2026-09-01-0900","id":"W12","op":"set_state","target":"owner/repo#4","items":["C1"],"reason":"Close it.","value":"Resolved"}
EOF

# run <label> <expected exit> <expected output> <file>: check <file> in the temp dir.
run() {
	if out=$(cd "$tmp" && sh "$ws" check "$4" body.md claims.md 2>&1); then st=0; else st=$?; fi
	[ "$st" = "$2" ] || fail "$1: expected exit $2, got $st"
	[ "$out" = "$3" ] || fail "$1: expected output '$3', got '$out'"
}

# edit <label> <expected output> <sed script>: edit the valid file, expect exit 1. The
# sed script uses '|' as its delimiter.
edit() {
	sed "$3" "$tmp/valid.jsonl" > "$tmp/b.jsonl"
	run "$1" 1 "$2" b.jsonl
}

run "valid" 0 "work-items: ok" valid.jsonl
: > "$tmp/empty.jsonl"
run "empty file" 0 "work-items: ok" empty.jsonl

edit "bad JSON" "work-items b.jsonl:3: not valid JSON" '3s|^{|{{|'
edit "not an object" "work-items b.jsonl:3: not a JSON object" '3s|^.*$|[1]|'
edit "empty line" "work-items b.jsonl:3: empty line" '2G'
edit "missing field" "work-items b.jsonl:3: missing field 'reason'" '3s|"reason":"Say why.",||'
edit "missing op field" "work-items b.jsonl:3: missing field 'text'" '3s|,"text":"The test is skipped."||'
edit "wrong type" "work-items b.jsonl:5: field 'value' must be a string" '5s|"value":"Active"|"value":3|'
edit "empty items" "work-items b.jsonl:5: field 'items' is empty" '5s|"items":\["C1"\]|"items":[]|'
edit "unknown op" "work-items b.jsonl:5: unknown op 'delete'" '5s|"op":"set_state"|"op":"delete"|'
edit "id gap" "work-items b.jsonl:5: id 'W6' should be 'W5'" '5s|"id":"W5"|"id":"W6"|'
edit "wrong id" "work-items b.jsonl:2: id 'W3' should be 'W2'" '2s|"id":"W2"|"id":"W3"|'
edit "unknown report item" "work-items b.jsonl:3: unknown report item 'C9'" '3s|"items":\["C2"\]|"items":["C9"]|'
edit "unknown claim" "work-items b.jsonl:3: unknown claim 'claim 3'" '3s|"items":\["C2"\]|"items":["claim 3"]|'
edit "malformed item" "work-items b.jsonl:3: item 'x' is not C<n>, W<n>, or claim <n>" '3s|"items":\["C2"\]|"items":["x"]|'
edit "wrong run" "work-items b.jsonl:4: run 'other' does not match the report run id '2026-09-01-0900'" '4s|"run":"2026-09-01-0900"|"run":"other"|'
edit "create with a wrong target" "work-items b.jsonl:1: target '\$new:other' must be '\$new:follow-up'" '1s|"target":"\$new:follow-up"|"target":"$new:other"|'
edit "set_pr_description on a placeholder" "work-items b.jsonl:8: set_pr_description target '\$new:follow-up' must be a PR forge id, not a placeholder" '8s|"target":"owner/repo#7"|"target":"$new:follow-up"|'

# W9 to W12 and the stricter checks.
edit "unknown key" "work-items b.jsonl:6: unknown field 'mentoins'" '6s|"text":"New text."|"text":"New text.","mentoins":[]|'
edit "mentions on set_state" "work-items b.jsonl:5: unknown field 'mentions'" '5s|"value":"Active"|"value":"Active","mentions":[]|'
edit "empty fields" "work-items b.jsonl:11: field 'fields' is empty" '11s|"fields":{[^}]*}|"fields":{}|'
edit "null in fields" "work-items b.jsonl:11: field 'fields' has a null value for 'resolution'" '11s|"resolution":"fixed"|"resolution":null|'
edit "item names no operation" "work-items b.jsonl:5: item 'W99' names no operation in the file" '5s|"items":\["C1"\]|"items":["C1","W99"]|'
edit "item names its own operation" "work-items b.jsonl:5: item 'W5' names this operation" '5s|"items":\["C1"\]|"items":["C1","W5"]|'
edit "item names only a missing operation" "work-items b.jsonl:5: item 'W99' names no operation in the file" '5s|"items":\["C1"\]|"items":["W99"]|'
edit "item names only its own operation" "work-items b.jsonl:5: item 'W5' names this operation" '5s|"items":\["C1"\]|"items":["W5"]|'
edit "remove_link on a placeholder" "work-items b.jsonl:10: remove_link target '\$new:follow-up' must be a forge id, not a placeholder" '10s|"target":"owner/repo#4"|"target":"$new:follow-up"|'
edit "update_comment on a placeholder" "work-items b.jsonl:9: update_comment target '\$new:follow-up' must be a forge id, not a placeholder" '9s|"target":"owner/repo#4"|"target":"$new:follow-up"|'
edit "remove_link to a placeholder" "work-items b.jsonl:10: remove_link to '\$new:follow-up' must be a forge id, not a placeholder" '10s|"to":"owner/repo#5"|"to":"$new:follow-up"|'
edit "placeholder missing from text" "work-items b.jsonl:9: mentions[0] placeholder '{mention:owner}' does not appear in text" '9s|Thanks {mention:owner}, fixed.|Thanks, fixed.|'
edit "duplicate placeholder" "work-items b.jsonl:9: mentions[1] placeholder '{mention:owner}' is a duplicate" '9s|"mentions":\[\(.*\)\]}$|"mentions":[\1,\1]}|'
edit "text placeholder with no entry" "work-items b.jsonl:6: text has '{mention:x}' with no entry in mentions" '6s|New text.|New {mention:x} text.|'
edit "bad placeholder shape" "work-items b.jsonl:9: mentions[0] placeholder '@owner' must be {mention:<key>}${nl}work-items b.jsonl:9: text has '{mention:owner}' with no entry in mentions" '9s|"placeholder":"{mention:owner}"|"placeholder":"@owner"|'

# Operations that cite each other and no report item or claim.
{
	printf '%s\n' '{"run":"2026-09-01-0900","id":"W1","op":"add_comment","target":"owner/repo#4","items":["W2"],"reason":"Say it.","text":"One."}'
	printf '%s\n' '{"run":"2026-09-01-0900","id":"W2","op":"add_comment","target":"owner/repo#4","items":["W1"],"reason":"Say it.","text":"Two."}'
} > "$tmp/b.jsonl"
run "a W cycle" 1 "work-items b.jsonl:1: items reach no report item or claim${nl}work-items b.jsonl:2: items reach no report item or claim" b.jsonl

# A second create with the same key, a placeholder used before its create, and a bad
# target_url, each as its own small file.
{
	cat "$tmp/valid.jsonl"
	printf '%s\n' '{"run":"2026-09-01-0900","id":"W13","op":"create","target":"$new:follow-up","items":["C1"],"reason":"Again.","key":"follow-up","type":"Bug","title":"T","description":"D"}'
} > "$tmp/b.jsonl"
run "duplicate create key" 1 "work-items b.jsonl:13: duplicate create key 'follow-up'" b.jsonl

{
	printf '%s\n' '{"run":"2026-09-01-0900","id":"W1","op":"add_comment","target":"$new:later","items":["C1"],"reason":"Say it.","text":"Note."}'
	printf '%s\n' '{"run":"2026-09-01-0900","id":"W2","op":"create","target":"$new:later","items":["C1"],"reason":"Track it.","key":"later","type":"Bug","title":"T","description":"D"}'
} > "$tmp/b.jsonl"
run "placeholder before its create" 1 "work-items b.jsonl:1: '\$new:later' in target has no create on an earlier line" b.jsonl

sed '3s|"target_url":"https://tickets.example.invalid/browse/APP-9"|"target_url":5|' "$tmp/valid.jsonl" > "$tmp/b.jsonl"
run "bad target_url" 1 "work-items b.jsonl:3: field 'target_url' must be a string" b.jsonl

# A report body without the heading.
printf '%s\n' '# Something else' > "$tmp/nohead.md"
if out=$(cd "$tmp" && sh "$ws" check valid.jsonl nohead.md claims.md 2>&1); then st=0; else st=$?; fi
[ "$st" = 1 ] || fail "no run heading: expected exit 1, got $st"
[ "$out" = "work-items nohead.md:1: no '# cca audit report: <run-id>' heading" ] ||
	fail "no run heading: got '$out'"

# Usage and unreadable files.
if out=$(cd "$tmp" && sh "$ws" check valid.jsonl 2>&1); then st=0; else st=$?; fi
[ "$st" = 2 ] || fail "usage: expected exit 2, got $st"
[ "$out" = "usage: work-items.sh check <file> <report body> <claims.md>" ] || fail "usage: got '$out'"
run "unreadable file" 2 "work-items: cannot read nope.jsonl" nope.jsonl

if [ "$fails" -gt 0 ]; then
	exit 1
fi
echo "work-items test: ok"
