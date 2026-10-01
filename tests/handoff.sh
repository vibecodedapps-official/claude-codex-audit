#!/bin/sh
# handoff.sh: tests for skills/cca/scripts/handoff.sh.
#
# Usage: sh tests/handoff.sh
#
# Builds the solo fixture, takes its handoff.md as the valid file, and compares the
# output and exit status of `detect`, `check`, `claims`, and `commits` with literals.
# Each broken case is a copy of the valid file with one edit, written in a temp
# directory. The literal line numbers below are the line numbers of the fixture's
# handoff.md (tests/fixture/build.sh): change the handoff and these move with it.
#
# Prints one line per mismatch and `handoff test: ok` on success; exits 1 on any
# mismatch.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
hs=$root/skills/cca/scripts/handoff.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tab=$(printf '\t')
nl='
'

fails=0
fail() {
	echo "handoff test: $*"
	fails=$((fails + 1))
}

# The fixture builder makes its own temp directory; point it inside $tmp so the one trap
# removes it.
if ! m=$(TMPDIR=$tmp sh "$root/tests/fixture/build.sh" solo); then
	echo "handoff test: the solo fixture did not build"
	exit 1
fi
F=$(dirname "$m")
v=$tmp/valid.md
cp "$F/handoff.md" "$v"
cp "$F/session-summary.md" "$tmp/prose.md"

# run <label> <expected exit> <expected output> <handoff.sh args...>: run the script in
# the temp directory, so file names in messages are relative.
run() {
	label=$1
	want_st=$2
	want_out=$3
	shift 3
	if out=$(cd "$tmp" && sh "$hs" "$@" 2>&1); then st=0; else st=$?; fi
	[ "$st" = "$want_st" ] || fail "$label: expected exit $want_st, got $st"
	[ "$out" = "$want_out" ] || fail "$label: expected output '$want_out', got '$out'"
}

# Edits: each reads <in> and writes <out>; <n> is a line number of <in>.
set_line() { # <in> <out> <n> <text>
	{ head -n $(($3 - 1)) "$1"; printf '%s\n' "$4"; tail -n +$(($3 + 1)) "$1"; } > "$2"
}
ins_after() { # <in> <out> <n> <text>
	{ head -n "$3" "$1"; printf '%s\n' "$4"; tail -n +$(($3 + 1)) "$1"; } > "$2"
}
del_line() { # <in> <out> <n>
	{ head -n $(($3 - 1)) "$1"; tail -n +$(($3 + 1)) "$1"; } > "$2"
}

# broken <label> <message>... : run check on b.md, which holds one or more messages
# separated by newlines in the single argument <message>.
broken() {
	run "$1" 1 "$2" check b.md
}

# ---------------------------------------------------------------------------
# The valid file.
run "check valid" 0 "handoff: ok" check valid.md

cat > "$tmp/claims.exp" <<EOF
status${tab}tickets/APP-1/fields${tab}app${tab}APP-1${tab}14${tab}APP-1: type Story; state Active; iteration none; owner Developer
code${tab}tickets/APP-1/problem${tab}app${tab}APP-1${tab}14${tab}Removing a user deletes the record, so its history is lost.
code${tab}tickets/APP-1/decision${tab}app${tab}APP-1${tab}14${tab}Add a deactivate command that keeps the row and sets its status to inactive.
code${tab}tickets/APP-1/commit/app/9c5f77c${tab}app${tab}APP-1${tab}23${tab}app 9c5f77c: add the status column migration so every row has a status.
code${tab}tickets/APP-1/commit/app/0c23936${tab}app${tab}APP-1${tab}24${tab}app 0c23936: add the deactivate command, which keeps the row and sets its status to inactive.
verification${tab}tickets/APP-1/verified/1${tab}app${tab}APP-1${tab}26${tab}Deactivate was checked by hand against a copy of production data; check: not recorded
verification${tab}tickets/APP-1/verified/2${tab}app${tab}APP-1${tab}27${tab}The test suite runs with one test skipped; check: sh run-tests.sh
decision${tab}decisions/D1${tab}app${tab}APP-1${tab}31${tab}Deactivate removes the row instead of setting a status. | rationale: A removed row needs no change to the reads. | options: chosen: remove the row; rejected: keep the row and set a status; why: every read would need a status filter | decided_by: checkpoint (recommended option taken) | recorded_at: checkpoint: plan review | status: default taken
decision${tab}decisions/D2${tab}app${tab}APP-1${tab}42${tab}Whether a deactivated user can be reactivated is left for later. | rationale: not recorded | options: none recorded | decided_by: not recorded | recorded_at: not recorded | status: deferred
scope${tab}raised/R1${tab}app${tab}APP-6${tab}53${tab}APP-6: Add accepts a second row with an id that already exists. | rank 1, include: The bundle introduced it when it changed add_user.
status${tab}raised/R1/fields${tab}app${tab}APP-6${tab}53${tab}APP-6: type Bug; state New; iteration none; owner none
EOF
claims_exp=$(cat "$tmp/claims.exp")
run "claims valid" 0 "$claims_exp" claims valid.md

commits_exp="app${tab}9c5f77c${tab}APP-1${tab}23${nl}app${tab}0c23936${tab}APP-1${tab}24"
run "commits valid" 0 "$commits_exp" commits valid.md

# ---------------------------------------------------------------------------
# detect.
run "detect handoff" 0 "" detect valid.md
run "detect prose" 1 "" detect prose.md
set_line "$v" "$tmp/b.md" 2 "cca-handoff: 2"
run "detect another version" 0 "" detect b.md
awk 'BEGIN { ORS = "\r\n" } { print }' "$v" > "$tmp/crlf.md"
run "detect crlf" 0 "" detect crlf.md
printf '\357\273\277' > "$tmp/bom.md"
cat "$v" >> "$tmp/bom.md"
run "detect utf-8 bom" 0 "" detect bom.md
run "detect unreadable" 2 "handoff: cannot read nope.md" detect nope.md

# Usage errors.
run "no arguments" 2 "usage: handoff.sh detect|check|claims|commits <file>"
run "unknown mode" 2 "usage: handoff.sh detect|check|claims|commits <file>" parse valid.md
run "missing file" 2 "usage: handoff.sh detect|check|claims|commits <file>" check
run "check unreadable" 2 "handoff: cannot read nope.md" check nope.md

# ---------------------------------------------------------------------------
# Positive variants of check.
run "check crlf" 0 "handoff: ok" check crlf.md
run "claims crlf" 0 "$claims_exp" claims crlf.md
run "check utf-8 bom" 0 "handoff: ok" check bom.md
run "claims utf-8 bom" 0 "$claims_exp" claims bom.md
run "commits utf-8 bom" 0 "$commits_exp" commits bom.md

# One commit under two tickets is allowed: it can address both.
{
	head -n 28 "$v"
	sed -n 14,28p "$v" | sed 's/APP-1/APP-2/'
	sed -n '29,$p' "$v"
} > "$tmp/b.md"
run "check the same commit under two tickets" 0 "handoff: ok" check b.md
run "commits the same commit under two tickets" 0 "app${tab}9c5f77c${tab}APP-1${tab}23${nl}app${tab}0c23936${tab}APP-1${tab}24${nl}app${tab}9c5f77c${tab}APP-2${tab}38${nl}app${tab}0c23936${tab}APP-2${tab}39" commits b.md

sed 's|APP-1|github:owner/app #12|g' "$v" > "$tmp/b.md"
run "check ticket id with spaces and colons" 0 "handoff: ok" check b.md
first="status${tab}tickets/github:owner/app #12/fields${tab}app${tab}github:owner/app #12${tab}14${tab}github:owner/app #12: type Story; state Active; iteration none; owner Developer"
if out=$(cd "$tmp" && sh "$hs" claims b.md 2>&1); then st=0; else st=$?; fi
[ "$st" = 0 ] || fail "claims ticket id with spaces and colons: exit $st"
[ "$(printf '%s\n' "$out" | head -n 1)" = "$first" ] ||
	fail "claims ticket id with spaces and colons: first line '$(printf '%s\n' "$out" | head -n 1)'"

set_line "$v" "$tmp/b.md" 27 "  - The suite passes; check: sh run-tests.sh; check: again"
run "check verified entry with a second check" 0 "handoff: ok" check b.md
second="verification${tab}tickets/APP-1/verified/2${tab}app${tab}APP-1${tab}27${tab}The suite passes; check: sh run-tests.sh; check: again"
if out=$(cd "$tmp" && sh "$hs" claims b.md 2>&1); then st=0; else st=$?; fi
[ "$st" = 0 ] || fail "claims verified entry with a second check: exit $st"
[ "$(printf '%s\n' "$out" | sed -n 7p)" = "$second" ] ||
	fail "claims verified entry with a second check: line 7 '$(printf '%s\n' "$out" | sed -n 7p)'"

set_line "$v" "$tmp/b.md" 27 "  - The smoke test passes; check: env: staging; sh smoke.sh"
run "check verified entry with an env tag" 0 "handoff: ok" check b.md
envc="verification${tab}tickets/APP-1/verified/2${tab}app${tab}APP-1${tab}27${tab}The smoke test passes; check: env: staging; sh smoke.sh"
if out=$(cd "$tmp" && sh "$hs" claims b.md 2>&1); then st=0; else st=$?; fi
[ "$st" = 0 ] || fail "claims verified entry with an env tag: exit $st"
[ "$(printf '%s\n' "$out" | sed -n 7p)" = "$envc" ] ||
	fail "claims verified entry with an env tag: line 7 '$(printf '%s\n' "$out" | sed -n 7p)'"

set_line "$v" "$tmp/b1.md" 10 "- app: repo ./a; branch x; pr none; branch feature; base main"
run "check bundle path holding a separator" 0 "handoff: ok" check b1.md

# No commits, nothing verified, an empty last section.
{
	head -n 21 "$v"
	printf '%s\n' "- commits: none" "- verified: none" ""
	sed -n 29,52p "$v"
	printf '%s\n' "none"
} > "$tmp/b.md"
run "check none lists and an empty section" 0 "handoff: ok" check b.md
run "commits none" 0 "" commits b.md

# A bundle with no tickets: Tickets, Decisions, and Raised tickets each hold none.
{
	head -n 13 "$v"
	printf '%s\n' "none" "" "## Decisions" "" "none" "" "## Raised tickets" "" "none"
} > "$tmp/b.md"
run "check every item section none" 0 "handoff: ok" check b.md
run "claims every item section none" 0 "" claims b.md
run "commits every item section none" 0 "" commits b.md

# The enum and form variants.
set_line "$v" "$tmp/b1.md" 38 "- decided_by: person: Alex Doe"
set_line "$tmp/b1.md" "$tmp/b2.md" 39 "- recorded_at: commit 9c5f77c"
set_line "$tmp/b2.md" "$tmp/b3.md" 40 "- status: taken"
set_line "$tmp/b3.md" "$tmp/b.md" 49 "- status: deferred to Team Lead"
run "check person, commit record, taken, deferred to" 0 "handoff: ok" check b.md

# The optional parent and links keys, after owner: on a ticket, and on the raised ticket.
{
	head -n 18 "$v"
	printf '%s\n' "- parent: FEAT-1" "- links:" "  - closed by: github:owner/app#12" "  - related: APP-2"
	tail -n +19 "$v"
} > "$tmp/b.md"
run "check parent and links on a ticket" 0 "handoff: ok" check b.md
want="status${tab}tickets/APP-1/fields${tab}app${tab}APP-1${tab}14${tab}APP-1: type Story; state Active; iteration none; owner Developer; parent FEAT-1; links closed by github:owner/app#12, related APP-2"
if out=$(cd "$tmp" && sh "$hs" claims b.md 2>&1); then st=0; else st=$?; fi
[ "$st" = 0 ] || fail "claims parent and links on a ticket: exit $st"
[ "$(printf '%s\n' "$out" | head -n 1)" = "$want" ] ||
	fail "claims parent and links on a ticket: first line '$(printf '%s\n' "$out" | head -n 1)'"

ins_after "$v" "$tmp/b.md" 58 "- links: none"
run "check links none on a raised ticket" 0 "handoff: ok" check b.md
want="status${tab}raised/R1/fields${tab}app${tab}APP-6${tab}53${tab}APP-6: type Bug; state New; iteration none; owner none; links none"
if out=$(cd "$tmp" && sh "$hs" claims b.md 2>&1); then st=0; else st=$?; fi
[ "$st" = 0 ] || fail "claims links none on a raised ticket: exit $st"
[ "$(printf '%s\n' "$out" | tail -n 1)" = "$want" ] ||
	fail "claims links none on a raised ticket: last line '$(printf '%s\n' "$out" | tail -n 1)'"

# ---------------------------------------------------------------------------
# Broken copies of the valid file.
del_line "$v" "$tmp/b.md" 18
broken "missing key" "handoff b.md:14: missing key 'owner'"

ins_after "$v" "$tmp/b.md" 19 "- extra: x"
broken "unknown key" "handoff b.md:20: unknown key 'extra'"

ins_after "$v" "$tmp/b.md" 16 "- state: Active"
broken "duplicate key" "handoff b.md:17: duplicate key 'state'"

set_line "$v" "$tmp/b1.md" 16 "- iteration: none"
set_line "$tmp/b1.md" "$tmp/b.md" 17 "- state: Active"
broken "keys out of order" "handoff b.md:17: key 'state' is out of order"

set_line "$v" "$tmp/b.md" 18 "- owner:"
broken "empty value" "handoff b.md:18: key 'owner' has an empty value"

set_line "$v" "$tmp/b.md" 62 "- in_bundle_confidence: maybe"
broken "bad confidence" "handoff b.md:62: invalid in_bundle_confidence 'maybe'"

set_line "$v" "$tmp/b.md" 40 "- status: later"
broken "bad status" "handoff b.md:40: invalid status 'later'"

set_line "$v" "$tmp/b.md" 61 "- rank: first"
broken "bad rank" "handoff b.md:61: rank must be a whole number from 1"

set_line "$v" "$tmp/b.md" 38 "- decided_by: the planner"
broken "bad decided_by" "handoff b.md:38: invalid decided_by 'the planner'"

set_line "$v" "$tmp/b.md" 39 "- recorded_at: somewhere"
broken "bad recorded_at" "handoff b.md:39: invalid recorded_at 'somewhere'"

set_line "$v" "$tmp/b.md" 19 "- bundles: app, web"
broken "unknown bundle in bundles" "handoff b.md:19: unknown bundle 'web'"

set_line "$v" "$tmp/b.md" 23 "  - web 9c5f77c: add the status column migration so every row has a status."
broken "commit with an unknown bundle" "handoff b.md:23: unknown bundle 'web'"

ins_after "$v" "$tmp/b1.md" 10 "- web: repo ./web; pr none; branch feature; base main"
set_line "$tmp/b1.md" "$tmp/b.md" 24 "  - web 9c5f77c: add the status column migration so every row has a status."
broken "commit bundle outside the ticket bundles" "handoff b.md:24: commit bundle 'web' is not one of the ticket bundles"

ins_after "$v" "$tmp/b.md" 10 "- app: repo ./other; pr none; branch x; base main"
broken "duplicate bundle name" "handoff b.md:11: duplicate bundle name 'app'"

set_line "$v" "$tmp/b.md" 10 "- app: repo ./app; pr none; branch ; base main"
broken "empty branch" "handoff b.md:10: bundle line has an empty branch"

set_line "$v" "$tmp/b.md" 42 "### D1"
broken "duplicate id" "handoff b.md:42: duplicate decision id 'D1'"

set_line "$v" "$tmp/b.md" 43 "- ticket: APP-9"
broken "decision with an unknown ticket" "handoff b.md:43: ticket 'APP-9' is not in Tickets or Raised tickets"

set_line "$v" "$tmp/b.md" 23 "  - app 9c5f7: add the status column migration so every row has a status."
broken "short sha" "handoff b.md:23: commit sha '9c5f7' must be 7 to 40 lowercase hex digits"

set_line "$v" "$tmp/b.md" 23 "  - app 9C5F77C: add the status column migration so every row has a status."
broken "uppercase sha" "handoff b.md:23: commit sha '9C5F77C' must be 7 to 40 lowercase hex digits"

set_line "$v" "$tmp/b.md" 20 "- problem: Removing a user${tab}deletes the record."
broken "tab in a value" "handoff b.md:20: tab in line"

set_line "$v" "$tmp/b.md" 37 "  - chosen: keep the row and set a status"
broken "two chosen entries" "handoff b.md:37: more than one chosen option"

set_line "$v" "$tmp/b.md" 36 "  - rejected: remove the row; why: it cannot be undone"
broken "taken with no chosen entry" "handoff b.md:35: status 'default taken' with options needs exactly one chosen entry"

ins_after "$v" "$tmp/b.md" 27 "stray text"
broken "stray line" "handoff b.md:28: unrecognized line"

set_line "$v" "$tmp/b.md" 27 "  - The test suite runs with one test skipped"
broken "verified entry without a check" "handoff b.md:27: verified entry must be '<statement>; check: <check>'"

set_line "$v" "$tmp/b.md" 27 "  - The smoke test passes; check: env: ; sh smoke.sh"
broken "env tag with an empty name" "handoff b.md:27: env tag has an empty name"

set_line "$v" "$tmp/b.md" 27 "  - The smoke test passes; check: env: staging;"
broken "env tag with an empty check" "handoff b.md:27: env tag has an empty check"

set_line "$v" "$tmp/b.md" 27 "  - The smoke test passes; check: env: staging"
broken "env tag without a separator" "handoff b.md:27: env tag must be 'env: <name>; <check>'"

set_line "$v" "$tmp/b.md" 27 "  - The smoke test passes; check: env:staging; sh smoke.sh"
broken "env tag without a space after the colon" "handoff b.md:27: env tag must be 'env: <name>; <check>'"

set_line "$v" "$tmp/b.md" 2 "cca-handoff: 2"
broken "version 2" "handoff b.md:2: unsupported handoff version"

sed '51,$d' "$v" > "$tmp/b.md"
broken "missing section" "handoff b.md:50: missing section '## Raised tickets'"

set_line "$v" "$tmp/b.md" 54 "- ticket: APP-1"
broken "raised ticket equal to a ticket id" "handoff b.md:54: raised ticket 'APP-1' is already a ticket id in Tickets"

ins_after "$v" "$tmp/b.md" 9 "none"
broken "none before a bundle" "handoff b.md:10: section '## Bundles' never holds none"

set_line "$v" "$tmp/b.md" 10 "none"
broken "none and no bundle" "handoff b.md:8: section '## Bundles' needs at least one bundle${nl}handoff b.md:10: section '## Bundles' never holds none${nl}handoff b.md:19: unknown bundle 'app'${nl}handoff b.md:23: unknown bundle 'app'${nl}handoff b.md:24: unknown bundle 'app'${nl}handoff b.md:59: unknown bundle 'app'"

set_line "$v" "$tmp/b.md" 24 "  - app 9c5f77c1: add the deactivate command, which keeps the row and sets its status to inactive."
broken "same commit at two sha lengths" "handoff b.md:24: duplicate commit entry 'app 9c5f77c1' (same commit as 'app 9c5f77c')"

set_line "$v" "$tmp/b.md" 19 "- bundles: app, app"
broken "bundle named twice" "handoff b.md:19: duplicate bundle 'app' in bundles"

{ head -n 29 "$v"; tail -n +51 "$v"; } > "$tmp/b.md"
broken "empty decisions" "handoff b.md:29: section '## Decisions' is empty; write none"

sed '52,$d' "$v" > "$tmp/b.md"
broken "file ends after raised tickets" "handoff b.md:51: section '## Raised tickets' is empty; write none"

ins_after "$v" "$tmp/b.md" 19 "- parent: FEAT-1"
broken "parent after bundles" "handoff b.md:20: key 'parent' is out of order"

ins_after "$v" "$tmp/b1.md" 18 "- parent: FEAT-1"
ins_after "$tmp/b1.md" "$tmp/b.md" 19 "- parent: FEAT-2"
broken "parent twice" "handoff b.md:20: duplicate key 'parent'"

ins_after "$v" "$tmp/b1.md" 18 "- links:"
ins_after "$tmp/b1.md" "$tmp/b.md" 19 "  - closed by github:owner/app#12"
broken "links entry without a separator" "handoff b.md:20: links entry must be '<type>: <target>'"

ins_after "$tmp/b1.md" "$tmp/b.md" 19 "  - : github:owner/app#12"
broken "links entry with an empty type" "handoff b.md:20: links entry has an empty type"

ins_after "$tmp/b1.md" "$tmp/b.md" 19 "  - closed by:"
broken "links entry with an empty target" "handoff b.md:20: links entry has an empty target"

ins_after "$tmp/b1.md" "$tmp/b2.md" 19 "  - closed by: github:owner/app#12"
ins_after "$tmp/b2.md" "$tmp/b.md" 20 "  - closed by: github:owner/app#12"
broken "duplicate links entry" "handoff b.md:21: duplicate links entry 'closed by: github:owner/app#12'"

cp "$tmp/b1.md" "$tmp/b.md"
broken "links with no entries" "handoff b.md:19: key 'links' has no entries"

ins_after "$v" "$tmp/b.md" 18 "- parent: APP-1"
broken "parent equal to the ticket id" "handoff b.md:19: ticket 'APP-1' is its own parent"

ins_after "$v" "$tmp/b.md" 58 "- parent: APP-6"
broken "raised ticket parent equal to its ticket" "handoff b.md:59: ticket 'APP-6' is its own parent"

# A claim is read as one line, so the whole claim line, all six fields joined by tabs, is
# capped at 8000 bytes: an error, never a truncation. The long values are fixed-length
# runs; the byte counts below are literals, each worked out from the field widths.
pad() { head -c "$1" /dev/zero | tr '\000' a; }

# D1's claim: kind 'decision' 8, ref 'decisions/D1' 12, bundle 'app' 3, ticket 'APP-1' 5,
# line '31' 2, text 8309 (346 for the fixture plus the 8000-byte reason replacing a
# 37-byte one), 5 tabs: 8 + 12 + 3 + 5 + 2 + 8309 + 5 = 8344.
set_line "$v" "$tmp/b.md" 37 "  - rejected: keep the row and set a status; why: $(pad 8000)"
cap_d1="handoff b.md:31: claim is 8344 bytes, over the 8000-byte cap"
broken "decision claim over the cap" "$cap_d1"
run "claims decision claim over the cap" 1 "$cap_d1" claims b.md
run "commits decision claim over the cap" 1 "$cap_d1" commits b.md

# The problem claim: kind 'code' 4, ref 'tickets/APP-1/problem' 21, bundle 3, ticket 5,
# line '14' 2, 5 tabs: 40 bytes besides the text. A text of 7961 makes 8001.
set_line "$v" "$tmp/b.md" 20 "- problem: $(pad 7961)"
cap_p="handoff b.md:14: claim is 8001 bytes, over the 8000-byte cap"
broken "problem over the cap" "$cap_p"
run "claims problem over the cap" 1 "$cap_p" claims b.md
run "commits problem over the cap" 1 "$cap_p" commits b.md

# A text of 7960 makes the line exactly 8000.
set_line "$v" "$tmp/b.md" 20 "- problem: $(pad 7960)"
run "check problem at the cap" 0 "handoff: ok" check b.md
run "commits problem at the cap" 0 "$commits_exp" commits b.md
if out=$(cd "$tmp" && sh "$hs" claims b.md 2>&1); then st=0; else st=$?; fi
[ "$st" = 0 ] || fail "claims problem at the cap: exit $st"
[ "$(printf '%s\n' "$out" | awk 'NR == 2 { print length($0) }')" = 8000 ] ||
	fail "claims problem at the cap: the claim line is not 8000 bytes"

# A long id reaches the ref field. D followed by 7700 ones is an id of 7701 bytes, so the
# ref 'decisions/<id>' is 10 + 7701 = 7711; the line is 8 + 7711 + 3 + 5 + 2 + 346 + 5 =
# 8080, with the fixture's own 346-byte text.
set_line "$v" "$tmp/b.md" 31 "### D$(pad 7700 | tr a 1)"
cap_id="handoff b.md:31: claim is 8080 bytes, over the 8000-byte cap"
broken "decision id over the cap" "$cap_id"
run "claims decision id over the cap" 1 "$cap_id" claims b.md
run "commits decision id over the cap" 1 "$cap_id" commits b.md

# Two errors in one file, reported in line order.
set_line "$v" "$tmp/b1.md" 23 "  - app 9c5f7: add the status column migration so every row has a status."
del_line "$tmp/b1.md" "$tmp/b.md" 18
broken "two errors" "handoff b.md:14: missing key 'owner'${nl}handoff b.md:22: commit sha '9c5f7' must be 7 to 40 lowercase hex digits"

# claims and commits print the same errors and no claims.
set_line "$v" "$tmp/b.md" 2 "cca-handoff: 2"
run "claims on a broken file" 1 "handoff b.md:2: unsupported handoff version" claims b.md
run "commits on a broken file" 1 "handoff b.md:2: unsupported handoff version" commits b.md

# An empty file.
: > "$tmp/e.md"
want="handoff e.md:1: missing frontmatter: the first line must be ---${nl}handoff e.md:1: missing section '## Bundles'${nl}handoff e.md:1: missing section '## Tickets'${nl}handoff e.md:1: missing section '## Decisions'${nl}handoff e.md:1: missing section '## Raised tickets'"
run "empty file" 1 "$want" check e.md

if [ "$fails" -gt 0 ]; then
	exit 1
fi
echo "handoff test: ok"
