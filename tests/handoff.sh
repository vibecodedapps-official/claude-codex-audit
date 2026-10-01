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
