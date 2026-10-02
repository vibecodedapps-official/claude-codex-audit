#!/bin/sh
# live.sh: tests for skills/cca/scripts/live.sh.
#
# Usage: sh tests/live.sh
#
# Part 1 writes a report whose first line is the SHA-256 of its body (the hex is a
# literal, computed once from the body below), a valid live file, and broken copies of
# it, and compares the output and exit status of `check` with literals. The literal line
# numbers are the line numbers of the valid file written below.
#
# Part 2 tests the bookkeeping modes (import, active, carry, assemble, retire), each in
# a fresh run directory, comparing stdout, stderr, the exit status, and the files that
# result with literals: replay, rebuild, numeric order of <k>, a malformed record,
# operational failures, and recovery after a partial retire or assemble.
#
# The script under test runs under `sh`, or under $LIVE_SH when set. Prints one line per
# mismatch and `live test: ok` on success; exits 1 on any mismatch. When jq is missing it
# prints a note and exits 0, since `active` needs it.
set -u

if ! command -v jq >/dev/null 2>&1; then
	echo "live test: note: jq not found, nothing was tested"
	exit 0
fi

root=$(cd "$(dirname "$0")/.." && pwd)
lv=$root/skills/cca/scripts/live.sh
LS=${LIVE_SH:-sh}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
w=$tmp/w
mkdir "$w"

tab=$(printf '\t')
nl='
'

fails=0
fail() {
	echo "live test: $*"
	fails=$((fails + 1))
}

# run <label> <expected exit> <expected stdout> <expected stderr> <live.sh args...>: run
# the script in the work directory, so file names in messages are relative.
run() {
	label=$1
	want_st=$2
	want_out=$3
	want_err=$4
	shift 4
	if out=$(cd "$w" && $LS "$lv" "$@" 2> "$tmp/err"); then st=0; else st=$?; fi
	err=$(cat "$tmp/err")
	[ "$st" = "$want_st" ] || fail "$label: expected exit $want_st, got $st"
	[ "$out" = "$want_out" ] || fail "$label: expected output '$want_out', got '$out'"
	[ "$err" = "$want_err" ] || fail "$label: expected stderr '$want_err', got '$err'"
}

sha() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum < "$1" | cut -d ' ' -f 1
	else
		shasum -a 256 < "$1" | cut -d ' ' -f 1
	fi
}

# same <label> <file> <expected text>: the file holds exactly the text (a literal).
same() {
	if [ ! -f "$2" ]; then
		fail "$1: $2 is missing"
		return
	fi
	got=$(cat "$2"; echo x)
	[ "$got" = "$3${nl}x" ] || fail "$1: expected '$3', got '${got%x}'"
}

absent() { # <label> <path>
	[ ! -e "$2" ] || fail "$1: $2 exists"
}

# snap <dir>: the names and checksums of everything under <dir>.
snap() {
	(cd "$w" && find "$1" | sort && find "$1" -type f -exec cksum {} + | sort)
}

long() { # a 9000-byte line, built by concatenation
	awk 'BEGIN { s = ""; for (i = 0; i < 900; i++) s = s "0123456789"; print s }'
}

H=45419c3e70cbb08c5dd8b359f58d0d11e41b755a63dc40212161a724656d737f
Z=0000000000000000000000000000000000000000000000000000000000000000

# ---------------------------------------------------------------------------
# Part 1: check.

cat > "$w/body.md" <<'EOF'
# cca audit report: 2026-10-01-1000-demo

### 9. Live checks

#### live g1-F2
- item: C1
- query: select count(*) from users where status is null
- where: production read replica
- results: a count above 0 shows the defect (high); 0 drops it
- status: not run: not approved

#### live g1+g2-F3
- item: C2
- query: select id from orders where total < 0
- where: production read replica
- results: any row shows the defect (medium); none drops it
- status: not run: not approved

#### live X1
- item: C3
- query: curl -s https://staging.example.test/health
- where: staging
- results: a 500 shows the defect (high); a 200 drops it
- status: not run: not approved

#### live claim 3
- item: claim 3
- query: sh run-tests.sh
- env: staging
- status: not run: not approved

### 10. Claims
EOF
{ printf 'revision: sha256:%s\n' "$H"; cat "$w/body.md"; } > "$w/report.md"

cat > "$w/valid.md" <<EOF
---
cca-live: 1
run: 2026-10-01-1000-demo
report: sha256:$H
---

## g1-F2
- query: select count(*) from users where status is null
- where: production read replica
- result: 12 rows
- approved_by: Ana Ruiz
- approved_at: 2026-10-01T09:30:00Z

## g1+g2-F3
- query: select id from orders where total < 0
- where: production read replica
- result: no rows
- approved_by: Ana Ruiz
- approved_at: 2026-10-01T09:31:00Z

## X1
- query: curl -s https://staging.example.test/health
- where: staging
- result: HTTP 200
- approved_by: Ana Ruiz
- approved_at: 2026-10-01T09:32:00Z

## claim 3
- query: sh run-tests.sh
- env: staging
- where: the staging box
- result: all tests pass
- approved_by: Ana Ruiz
- approved_at: 2026-10-01
EOF
v=$w/valid.md

set_line() { # <in> <out> <n> <text>
	{ head -n $(($3 - 1)) "$1"; printf '%s\n' "$4"; tail -n +$(($3 + 1)) "$1"; } > "$2"
}
ins_after() { # <in> <out> <n> <text>
	{ head -n "$3" "$1"; printf '%s\n' "$4"; tail -n +$(($3 + 1)) "$1"; } > "$2"
}
del_line() { # <in> <out> <n>
	{ head -n $(($3 - 1)) "$1"; tail -n +$(($3 + 1)) "$1"; } > "$2"
}

usage_msg="usage: live.sh check <file> <report.md> | import <file> <report.md> <run dir> | active <run dir> | carry <run dir> <id> | assemble <run dir> <entries dir> | retire <run dir> <dest dir> <reason>"

run "check valid" 0 "live: ok" "" check valid.md report.md

# broken <label> <message>: run check on b.md.
broken() {
	run "$1" 1 "$2" "" check b.md report.md
}

set_line "$v" "$w/b.md" 2 "cca-live: 2"
broken "version 2" "live b.md:2: unsupported live version"
set_line "$v" "$w/b.md" 3 "run: other-run"
broken "wrong run" "live b.md:3: run 'other-run' is not the report's run '2026-10-01-1000-demo'"
set_line "$v" "$w/b.md" 4 "report: sha256:$Z"
broken "wrong revision" "live b.md:4: report 'sha256:$Z' is not the report's revision 'sha256:$H'"

# An edited report body under its old revision line.
{ printf 'revision: sha256:%s\n' "$H"; sed 's/^- where: staging$/- where: elsewhere/' "$w/body.md"; } > "$w/report-edited.md"
run "edited report body" 1 "live report-edited.md:1: the revision line does not match the SHA-256 of the report body" "" check valid.md report-edited.md

set_line "$v" "$w/b.md" 7 "## g9-F9"
broken "unknown id" "live b.md:7: 'g9-F9' is not a live check of the report"
set_line "$v" "$w/b.md" 14 "## g1-F2"
broken "duplicate id" "live b.md:14: duplicate id 'g1-F2'${nl}live b.md:15: query does not match the report's query for 'g1-F2'"
set_line "$v" "$w/b.md" 8 "- query: select 1"
broken "query differs" "live b.md:8: query does not match the report's query for 'g1-F2'"
set_line "$v" "$w/b.md" 8 "- query: select count(*) from users where status is null  "
run "query with trailing spaces" 0 "live: ok" "" check b.md report.md
set_line "$v" "$w/b.md" 30 "- env: staging-copy"
broken "claim env differs" "live b.md:30: env 'staging-copy' does not match the report's env 'staging'"
del_line "$v" "$w/b.md" 30
broken "claim without env" "live b.md:28: missing key 'env'"
ins_after "$v" "$w/b.md" 8 "- env: staging"
broken "finding with env" "live b.md:9: key 'env' is not allowed on a finding entry"
del_line "$v" "$w/b.md" 9
broken "missing key" "live b.md:7: missing key 'where'"
set_line "$v" "$w/b.md" 9 "- result: 12 rows"
set_line "$w/b.md" "$w/c.md" 10 "- where: production read replica"
run "key out of order" 1 "live c.md:10: key 'where' is out of order" "" check c.md report.md
ins_after "$v" "$w/b.md" 10 "- note: x"
broken "unknown key" "live b.md:11: unknown key 'note'"
ins_after "$v" "$w/b.md" 10 "- result: again"
broken "repeated key" "live b.md:11: duplicate key 'result'"
set_line "$v" "$w/b.md" 10 "- result:"
broken "empty value" "live b.md:10: key 'result' has an empty value"
set_line "$v" "$w/b.md" 10 "- result:   "
broken "blank value" "live b.md:10: key 'result' has an empty value"
set_line "$v" "$w/b.md" 12 "- approved_at: yesterday"
broken "bad approved_at" "live b.md:12: approved_at must start with YYYY-MM-DD"
set_line "$v" "$w/b.md" 10 "- result: a${tab}b"
broken "tab" "live b.md:10: tab in line"
ins_after "$v" "$w/b.md" 10 "stray"
broken "stray line" "live b.md:11: unrecognized line"
head -n 5 "$v" > "$w/b.md"
broken "no entries" "live b.md:5: no entries"
del_line "$v" "$w/b.md" 5
broken "frontmatter not closed" "live b.md:6: frontmatter is not closed"
del_line "$v" "$w/b.md" 4
broken "missing frontmatter key" "live b.md:4: missing frontmatter key 'report'"
: > "$w/empty.md"
run "empty file" 1 "live empty.md:1: missing frontmatter: the first line must be ---" "" check empty.md report.md
# Two errors: the missing key is found when the entry ends, and is listed first.
del_line "$v" "$w/c.md" 9
set_line "$w/c.md" "$w/b.md" 11 "- approved_at: yesterday"
broken "errors in line order" "live b.md:7: missing key 'where'${nl}live b.md:11: approved_at must start with YYYY-MM-DD"

awk 'BEGIN { ORS = "\r\n" } { print }' "$v" > "$w/crlf.md"
run "check crlf" 0 "live: ok" "" check crlf.md report.md
printf '\357\273\277' > "$w/bom.md"
cat "$v" >> "$w/bom.md"
run "check utf-8 bom" 0 "live: ok" "" check bom.md report.md
{ head -n 9 "$v"; printf -- '- result: '; long; tail -n +11 "$v"; } > "$w/longres.md"
run "check long result" 0 "live: ok" "" check longres.md report.md

# result_file: an entry gives a file in place of a one-line result. The files hold a CR,
# an empty line, and a `## ` line, which a one-line result cannot.
printf 'id,status\r\n\r\n## 1,null\n2,null\n' > "$w/rows.txt"
printf 'PASS 41 tests\nFAIL 0\n' > "$w/tests.txt"
set_line "$v" "$w/c.md" 10 "- result_file: rows.txt"
set_line "$w/c.md" "$w/rf.md" 32 "- result_file: tests.txt"
run "check result_file" 0 "live: ok" "" check rf.md report.md
mkdir -p "$w/sub dir"
cp "$w/rows.txt" "$w/sub dir/my rows.txt"
set_line "$v" "$w/sub dir/rf.md" 10 "- result_file: my rows.txt"
run "check result_file beside the live file, with spaces" 0 "live: ok" "" check "sub dir/rf.md" report.md
mkdir -p "$w/data"
cp "$w/rows.txt" "$w/data/rows.txt"
set_line "$v" "$w/b.md" 10 "- result_file:   data/rows.txt"
run "check result_file in a subdirectory, leading spaces" 0 "live: ok" "" check b.md report.md
# Only a path under the live file's directory: never absolute, never through `..`.
under="is not a relative path under the live file's directory"
set_line "$v" "$w/b.md" 10 "- result_file: $w/rows.txt"
broken "result_file absolute" "live b.md:10: result_file '$w/rows.txt' $under"
set_line "$v" "$w/b.md" 10 '- result_file: C:/x/rows.txt'
broken "result_file X:/" "live b.md:10: result_file 'C:/x/rows.txt' $under"
set_line "$v" "$w/b.md" 10 '- result_file: c:rows.txt'
broken "result_file X:" "live b.md:10: result_file 'c:rows.txt' $under"
set_line "$v" "$w/b.md" 10 '- result_file: \x\rows.txt'
broken "result_file \\" "live b.md:10: result_file '\x\rows.txt' $under"
set_line "$v" "$w/b.md" 10 "- result_file: data/../../rows.txt"
broken "result_file .." "live b.md:10: result_file 'data/../../rows.txt' $under"
set_line "$v" "$w/b.md" 10 '- result_file: data\..\rows.txt'
broken "result_file ..\\" "live b.md:10: result_file 'data\..\rows.txt' $under"
# A backslash in a path is printed as is, under dash too.
set_line "$v" "$w/b.md" 10 '- result_file: out\new\table.txt'
broken "result_file backslashes" "live b.md:10: result_file 'out\\new\\table.txt' is not a readable file"
del_line "$v" "$w/b.md" 10
broken "neither result key" "live b.md:7: missing key 'result' or 'result_file'"
ins_after "$v" "$w/b.md" 10 "- result_file: rows.txt"
broken "both result keys" "live b.md:11: keys 'result' and 'result_file' are both given"
set_line "$v" "$w/b.md" 10 "- result_file:"
broken "empty result_file" "live b.md:10: key 'result_file' has an empty value"
set_line "$v" "$w/b.md" 10 "- result_file: nope.txt"
broken "missing result_file" "live b.md:10: result_file 'nope.txt' is not a readable file"
set_line "$v" "$w/b.md" 10 "- result_file: sub dir"
broken "result_file a directory" "live b.md:10: result_file 'sub dir' is not a readable file"
: > "$w/none.txt"
set_line "$w/rf.md" "$w/b.md" 32 "- result_file: none.txt"
broken "empty result file" "live b.md:32: result_file 'none.txt' is empty"
# A format error hides the file errors, so the lines stay in line order.
set_line "$v" "$w/c.md" 10 "- result_file: nope.txt"
set_line "$w/c.md" "$w/b.md" 2 "cca-live: 2"
broken "format error first" "live b.md:2: unsupported live version"

run "no arguments" 2 "" "$usage_msg"
run "unknown mode" 2 "" "$usage_msg" parse valid.md report.md
run "check one argument" 2 "" "$usage_msg" check valid.md
run "check unreadable file" 2 "" "live: cannot read nope.md" check nope.md report.md
run "check unreadable report" 2 "" "live: cannot read nope-report.md" check valid.md nope-report.md
tail -n +2 "$w/report.md" > "$w/norev.md"
run "report without revision" 2 "" "live: norev.md has no 'revision: sha256:<hex>' first line" check valid.md norev.md
{ printf 'revision: sha256:%s\n' "$H"; sed 's/^# cca audit report: .*$/# something else/' "$w/body.md"; } > "$w/nohead.md"
run "report without heading" 2 "" "live: nohead.md has no '# cca audit report: <run-id>' heading" check valid.md nohead.md

# ---------------------------------------------------------------------------
# Part 2: the bookkeeping modes.

# res_file <out> <at> <id>...: a results file, one entry per id, the heading of the
# first at line 7 and each next 7 lines on.
res_file() {
	rf_out=$1
	rf_at=$2
	shift 2
	printf -- '---\ncca-live: 1\nrun: demo\nreport: sha256:x\n---\n' > "$rf_out"
	for rf_id in "$@"; do
		printf -- '\n## %s\n- query: q\n- where: w\n- result: r\n- approved_by: Ana Ruiz\n- approved_at: %s\n' "$rf_id" "$rf_at" >> "$rf_out"
	done
}

# mk_state <dir> <with carried 0|1>: a run directory under $w with imports 1 (g1-F2, X1,
# claim 3), 2 (g1-F2), and 3 (L1, retired), stages.json recording one approval, and the
# derived files that the first import's winners make.
mk_state() {
	d=$w/$1
	rm -rf "$d"
	mkdir -p "$d/live"
	res_file "$d/live/results-1.md" 2026-10-01T09:00:00Z g1-F2 X1 'claim 3'
	res_file "$d/live/results-2.md" 2026-10-01T09:30:00Z g1-F2
	res_file "$d/live/results-3.md" 2026-10-01T09:45:00Z L1
	printf '3 retired 2026-10-01T10:00:00Z: stage 4 rerun\n' > "$d/live/retired.md"
	cat > "$d/stages.json" <<'EOF'
{"plugin_version":"0.3.0","approvals":[{"kind":"fetch","target":"app:origin","decision":"approved","time":"2026-10-01T08:00:00Z","source":"live/results-2.md:7"},{"kind":"live","target":"g1-F2","decision":"approved","time":"2026-10-01T09:00:00Z","by":"Ana Ruiz","source":"live/results-1.md:7"}]}
EOF
	printf '## g1-F2\n- source: live/results-1.md:7\n- earlier: none\n- result 12 rows; derived: verified fact\n' > "$d/live/findings.md"
	printf '## claim 3\n- source: live/results-1.md:21\n- earlier: none\n- claim 3: true, reproduced\n' > "$d/live/claims.md"
	if [ "$2" = 1 ]; then
		mkdir "$d/live/carried"
		printf '### X1: Missing index on orders\n- finding text\n' > "$d/live/carried/X1.md"
	fi
}

# The ledger files the carry cases cut.
mk_ledgers() { # <dir>
	mkdir -p "$w/$1/ledger"
	cat > "$w/$1/ledger/6.md" <<'EOF'
## Role
Second opinion.

## X-section note
Not a finding.

### X1: Missing index on orders
- severity: high
- label: unverified assumption

### Evidence
- orders.sql:12

### X2: Unused flag
- severity: low

## Merge verdict (non-binding)
Done.
EOF
	cat > "$w/$1/ledger/7.md" <<'EOF'
## Late adversary failed
The run failed twice.

### L1: Retry loop never ends
- severity: medium
- label: verified fact

### Evidence
- worker.sh:9

## Claims challenged
- claim 3: upheld
EOF
}

# --- import ----------------------------------------------------------------

rm -rf "$w/i1" && mkdir "$w/i1"
run "import, no live" 0 "live: imported live/results-1.md" "" import valid.md report.md i1
[ "$(sha "$w/i1/live/results-1.md")" = f651dc2f65c68c959027d31e78911b056b34a305b5e5c788b2e9657bad5941b0 ] || fail "import, no live: the kept file is not the source"
absent "import, no live" "$w/i1/live/results-1.md.pending"

rm -rf "$w/i2" && mkdir -p "$w/i2/live"
cp "$v" "$w/i2/live/results-1.md"
printf 'stale\n' > "$w/i2/live/results-7.md.pending"
printf 'notes\n' > "$w/i2/live/notes.md"
run "import, next number" 0 "live: imported live/results-2.md" "" import valid.md report.md i2
absent "import, next number" "$w/i2/live/results-7.md.pending"
absent "import, next number" "$w/i2/live/results-8.md"
[ "$(sha "$w/i2/live/results-2.md")" = f651dc2f65c68c959027d31e78911b056b34a305b5e5c788b2e9657bad5941b0 ] || fail "import, next number: the kept file is not the source"
same "import, next number" "$w/i2/live/notes.md" notes

set_line "$v" "$w/b.md" 2 "cca-live: 2"
rm -rf "$w/i3" && mkdir "$w/i3"
run "import, invalid file" 1 "live b.md:2: unsupported live version" "" import b.md report.md i3
[ -z "$(ls -A "$w/i3/live")" ] || fail "import, invalid file: live/ is not empty"
rm -rf "$w/i4" && mkdir -p "$w/i4/live"
cp "$v" "$w/i4/live/results-1.md"
run "import, invalid file after one" 1 "live b.md:2: unsupported live version" "" import b.md report.md i4
[ "$(ls -A "$w/i4/live")" = results-1.md ] || fail "import, invalid file after one: live/ changed"
run "import, edited report" 1 "live report-edited.md:1: the revision line does not match the SHA-256 of the report body" "" import valid.md report-edited.md i4
[ "$(ls -A "$w/i4/live")" = results-1.md ] || fail "import, edited report: live/ changed"
run "import, no run directory" 2 "" "live: cannot read run directory nope" import valid.md report.md nope
run "import, unreadable file" 2 "" "live: cannot read nope.md" import nope.md report.md i4
rm -rf "$w/i5" && mkdir "$w/i5"
run "import, long result" 0 "live: imported live/results-1.md" "" import longres.md report.md i5
[ "$(sha "$w/i5/live/results-1.md")" = 53e82444536d4c2c202e313227e7d14d35646831e9cd9a4ae512c37cd57c6e7c ] || fail "import, long result: the kept file differs"

# Without jq, import exits 2 before it writes anything, since the reconcile after it runs
# `active`, which needs jq. Runs only where PATH without jq's directories still has the
# shell and the tools the script uses (jq installed apart from them); else prints a skip.
nojq=$(printf '%s\n' "$PATH" | tr ':' '\n' | while IFS= read -r pd; do
	[ -x "$pd/jq" ] || [ -x "$pd/jq.exe" ] || printf '%s\n' "$pd"
done | paste -s -d : -)
if PATH=$nojq sh -c '! command -v jq && command -v "$1" && command -v awk && command -v cp &&
	command -v tail && { command -v sha256sum || command -v shasum; }' sh "$LS" > /dev/null 2>&1; then
	rm -rf "$w/i6" && mkdir "$w/i6"
	if out=$(cd "$w" && PATH=$nojq $LS "$lv" import valid.md report.md i6 2> "$tmp/err"); then st=0; else st=$?; fi
	[ "$st" = 2 ] || fail "import, no jq: expected exit 2, got $st"
	[ -z "$out" ] || fail "import, no jq: expected no output, got '$out'"
	[ "$(cat "$tmp/err")" = "live: jq not found" ] || fail "import, no jq: expected stderr 'live: jq not found', got '$(cat "$tmp/err")'"
	absent "import, no jq" "$w/i6/live"
else
	echo "live test: skipped import, no jq: jq shares a PATH directory with the tools"
fi

# --- result_file -------------------------------------------------------------

# An import copies each result_file to results-<k>/<heading line>.txt and hashes the
# copies in SHA256SUMS; the kept .md is the source byte for byte.
SR=0cdfed83356cc4c62dc9b84dbd6bf8dd4a859e67a5e72b360c57b3c4d7a6aee7
ST=40b0d5efd5ab8f61cba15cbd5471e30fe4f42e26de480b6bc0c861e199ad4d74
rm -rf "$w/f1" && mkdir "$w/f1"
run "import result_file" 0 "live: imported live/results-1.md" "" import rf.md report.md f1
cmp -s "$w/rf.md" "$w/f1/live/results-1.md" || fail "import result_file: the kept file is not the source"
cmp -s "$w/rows.txt" "$w/f1/live/results-1/7.txt" || fail "import result_file: 7.txt is not rows.txt"
cmp -s "$w/tests.txt" "$w/f1/live/results-1/28.txt" || fail "import result_file: 28.txt is not tests.txt"
same "import result_file" "$w/f1/live/results-1/SHA256SUMS" "$SR  7.txt
$ST  28.txt"
[ "$(cd "$w/f1/live" && ls -A)" = "results-1${nl}results-1.md" ] || fail "import result_file: live/ holds more"
want="approve${tab}live/results-1.md:7${tab}g1-F2${tab}Ana Ruiz${tab}2026-10-01T09:30:00Z
approve${tab}live/results-1.md:14${tab}g1+g2-F3${tab}Ana Ruiz${tab}2026-10-01T09:31:00Z
approve${tab}live/results-1.md:21${tab}X1${tab}Ana Ruiz${tab}2026-10-01T09:32:00Z
approve${tab}live/results-1.md:28${tab}claim 3${tab}Ana Ruiz${tab}2026-10-01
carry${tab}X1${tab}ledger/6.md
winner${tab}g1-F2${tab}live/results-1.md:7${tab}none${tab}new
winner${tab}g1+g2-F3${tab}live/results-1.md:14${tab}none${tab}new
winner${tab}X1${tab}live/results-1.md:21${tab}none${tab}new
winner${tab}claim 3${tab}live/results-1.md:28${tab}none${tab}new"
run "active, result_file" 0 "$want" "" active f1

# A missing result file writes nothing.
rm -rf "$w/f2" && mkdir "$w/f2"
set_line "$v" "$w/b.md" 10 "- result_file: nope.txt"
run "import result_file, missing file" 1 "live b.md:10: result_file 'nope.txt' is not a readable file" "" import b.md report.md f2
[ -z "$(ls -A "$w/f2/live")" ] || fail "import result_file, missing file: live/ is not empty"

# Recovery: a stale results-<k>.pending/ and an orphan results-<k>/ (no .md, an import
# stopped between its two renames) are removed; a committed results-<k>/ stays.
rm -rf "$w/f3" && mkdir -p "$w/f3/live/results-1" "$w/f3/live/results-2" "$w/f3/live/results-4.pending" "$w/f3/live/results-x"
cp "$w/f1/live/results-1.md" "$w/f3/live/results-1.md"
cp "$w/f1/live/results-1/"* "$w/f3/live/results-1/"
printf 'orphan\n' > "$w/f3/live/results-2/7.txt"
printf 'stale\n' > "$w/f3/live/results-4.pending/7.txt"
run "import result_file, recovery" 0 "live: imported live/results-2.md" "" import rf.md report.md f3
[ "$(cd "$w/f3/live" && ls -A)" = "results-1${nl}results-1.md${nl}results-2${nl}results-2.md${nl}results-x" ] || fail "import result_file, recovery: live/ holds $(cd "$w/f3/live" && ls -A)"
cmp -s "$w/rows.txt" "$w/f3/live/results-2/7.txt" || fail "import result_file, recovery: 7.txt is not rows.txt"
mkdir "$w/f3/live/results-9"
run "retire, orphan result directory" 0 "live: retired 1${nl}live: retired 2" "" retire f3 f3/superseded/1/live "stage 4 rerun"
absent "retire, orphan result directory" "$w/f3/live/results-9"
[ -d "$w/f3/live/results-2" ] || fail "retire, orphan result directory: removed live/results-2"

# active and assemble check the copies of every active import.
copies() { # <dir>: a run directory with the result_file import and no derived files
	rm -rf "$w/$1" && mkdir -p "$w/$1/live"
	cp "$w/f1/live/results-1.md" "$w/$1/live/"
	cp -R "$w/f1/live/results-1" "$w/$1/live/"
}
copies f4
printf 'more\n' >> "$w/f4/live/results-1/7.txt"
run "active, edited copy" 1 "live: live/results-1/7.txt does not match live/results-1/SHA256SUMS" "" active f4
copies f4
rm "$w/f4/live/results-1/28.txt"
run "active, missing copy" 1 "live: live/results-1/28.txt is missing" "" active f4
copies f4
rm -r "$w/f4/live/results-1"
run "active, missing result directory" 1 "live: live/results-1/SHA256SUMS is missing" "" active f4
run "assemble, missing result directory" 1 "live: live/results-1/SHA256SUMS is missing" "" assemble f4 f4/entries
copies f4
head -n 1 "$w/f4/live/results-1/SHA256SUMS" > "$w/f4/sums" && cp "$w/f4/sums" "$w/f4/live/results-1/SHA256SUMS"
run "active, short SHA256SUMS" 1 "live: live/results-1/SHA256SUMS does not list the result files of live/results-1.md" "" active f4
# A SHA256SUMS without its final newline: its last line is still checked.
copies f4
printf '%s  7.txt\n%s  28.txt' "$SR" "$ST" > "$w/f4/live/results-1/SHA256SUMS"
printf 'more\n' >> "$w/f4/live/results-1/28.txt"
run "active, unterminated SHA256SUMS" 1 "live: live/results-1/28.txt does not match live/results-1/SHA256SUMS" "" active f4
# import checks the copies first, so a retry does not commit another import.
run "import, broken copy of an earlier import" 1 "live: live/results-1/28.txt does not match live/results-1/SHA256SUMS" "" import valid.md report.md f4
[ "$(cd "$w/f4/live" && ls -A)" = "results-1${nl}results-1.md" ] || fail "import, broken copy of an earlier import: live/ changed"
copies f4
printf 'junk\n' > "$w/f4/live/findings.md"
run "import, malformed derived file" 1 "live: live/findings.md:1: line before the first section; delete the file to rebuild it" "" import valid.md report.md f4
[ "$(cd "$w/f4/live" && ls -A)" = "findings.md${nl}results-1${nl}results-1.md" ] || fail "import, malformed derived file: live/ changed"
copies f4
head -n 1 "$w/f4/live/results-1/SHA256SUMS" > "$w/f4/sums" && cp "$w/f4/sums" "$w/f4/live/results-1/SHA256SUMS"
# A retired import is not checked.
printf '1 retired 2026-10-01T10:00:00Z: stage 4 rerun\n' > "$w/f4/live/retired.md"
run "active, retired import with a short SHA256SUMS" 0 "" "" active f4

# --- active ----------------------------------------------------------------

rm -rf "$w/a0" && mkdir "$w/a0"
run "active, no live" 0 "" "" active a0

mk_state a1 0
want="approve${tab}live/results-1.md:14${tab}X1${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-1.md:21${tab}claim 3${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-2.md:7${tab}g1-F2${tab}Ana Ruiz${tab}2026-10-01T09:30:00Z
carry${tab}X1${tab}ledger/6.md
winner${tab}g1-F2${tab}live/results-2.md:7${tab}live/results-1.md:7${tab}changed
winner${tab}X1${tab}live/results-1.md:14${tab}none${tab}new
winner${tab}claim 3${tab}live/results-1.md:21${tab}none${tab}kept"
before=$(snap a1)
run "active" 0 "$want" "" active a1
[ "$(snap a1)" = "$before" ] || fail "active: changed the run directory"

rm "$w/a1/stages.json"
want="approve${tab}live/results-1.md:7${tab}g1-F2${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-1.md:14${tab}X1${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-1.md:21${tab}claim 3${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-2.md:7${tab}g1-F2${tab}Ana Ruiz${tab}2026-10-01T09:30:00Z
carry${tab}X1${tab}ledger/6.md
winner${tab}g1-F2${tab}live/results-2.md:7${tab}live/results-1.md:7${tab}changed
winner${tab}X1${tab}live/results-1.md:14${tab}none${tab}new
winner${tab}claim 3${tab}live/results-1.md:21${tab}none${tab}kept"
run "active, no stages.json" 0 "$want" "" active a1

# An L<n> winner is carried from ledger/7.md.
rm -rf "$w/a2" && mkdir -p "$w/a2/live"
res_file "$w/a2/live/results-1.md" 2026-10-01T09:00:00Z L1
printf '{"approvals":[]}\n' > "$w/a2/stages.json"
want="approve${tab}live/results-1.md:7${tab}L1${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
carry${tab}L1${tab}ledger/7.md
winner${tab}L1${tab}live/results-1.md:7${tab}none${tab}new"
run "active, L1" 0 "$want" "" active a2

# Numbers: <k> is compared as a number.
rm -rf "$w/n1" && mkdir -p "$w/n1/live"
res_file "$w/n1/live/results-9.md" 2026-10-01T09:00:00Z g1-F2
res_file "$w/n1/live/results-10.md" 2026-10-01T09:30:00Z g1-F2
want="approve${tab}live/results-9.md:7${tab}g1-F2${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-10.md:7${tab}g1-F2${tab}Ana Ruiz${tab}2026-10-01T09:30:00Z
winner${tab}g1-F2${tab}live/results-10.md:7${tab}live/results-9.md:7${tab}new"
run "numbers, active" 0 "$want" "" active n1
run "numbers, import" 0 "live: imported live/results-11.md" "" import valid.md report.md n1

# --- carry -----------------------------------------------------------------

rm -rf "$w/c1" && mk_ledgers c1
run "carry X1" 0 "" "" carry c1 X1
same "carry X1" "$w/c1/live/carried/X1.md" "### X1: Missing index on orders
- severity: high
- label: unverified assumption

### Evidence
- orders.sql:12
"
before=$(snap c1)
run "carry X1 again" 1 "live: live/carried/X1.md exists" "" carry c1 X1
[ "$(snap c1)" = "$before" ] || fail "carry X1 again: changed the run directory"
run "carry X9" 1 "live: no block for X9 in ledger/6.md" "" carry c1 X9
absent "carry X9" "$w/c1/live/carried/X9.md"
rm -rf "$w/c2" && mkdir "$w/c2"
run "carry L1, no ledger" 1 "live: no block for L1 in ledger/7.md" "" carry c2 L1
absent "carry L1, no ledger" "$w/c2/live"
run "carry g1-F2" 2 "" "$usage_msg" carry c1 g1-F2
run "carry X" 2 "" "$usage_msg" carry c1 X
run "carry, no run directory" 2 "" "live: cannot read run directory nope" carry nope X1
run "carry L1" 0 "" "" carry c1 L1
same "carry L1" "$w/c1/live/carried/L1.md" "### L1: Retry loop never ends
- severity: medium
- label: verified fact

### Evidence
- worker.sh:9
"

# --- assemble --------------------------------------------------------------

# mk_entries <dir>: a.md for g1-F2 and b.md for X1.
mk_entries() {
	mkdir -p "$1"
	printf '## g1-F2\n- derived: dropped\n' > "$1/a.md"
	printf '## X1\n- derived: verified fact, high\n- note: second line\n' > "$1/b.md"
}

findings_want="## g1-F2
- source: live/results-2.md:7
- earlier: live/results-1.md:7
- derived: dropped
## X1
- source: live/results-1.md:14
- earlier: none
- derived: verified fact, high
- note: second line"

mk_state s1 0
mk_ledgers s1
run "assemble prepares: carry X1" 0 "" "" carry s1 X1
mk_entries "$w/s1/tmp/live-entries"
cp "$w/s1/live/claims.md" "$w/claims.before"
run "assemble" 0 "live: wrote live/findings.md${nl}live: kept live/claims.md" "" assemble s1 s1/tmp/live-entries
same "assemble" "$w/s1/live/findings.md" "$findings_want"
cmp -s "$w/claims.before" "$w/s1/live/claims.md" || fail "assemble: live/claims.md changed"
absent "assemble" "$w/s1/tmp/live-entries"

# Replay: record the approvals, then nothing is left to do.
cat > "$w/s1/stages.json" <<'EOF'
{"approvals":[{"kind":"live","source":"live/results-1.md:7"},{"kind":"live","source":"live/results-1.md:14"},{"kind":"live","source":"live/results-1.md:21"},{"kind":"live","source":"live/results-2.md:7"}]}
EOF
want="winner${tab}g1-F2${tab}live/results-2.md:7${tab}live/results-1.md:7${tab}kept
winner${tab}X1${tab}live/results-1.md:14${tab}none${tab}kept
winner${tab}claim 3${tab}live/results-1.md:21${tab}none${tab}kept"
run "replay, active" 0 "$want" "" active s1
cp "$w/s1/live/findings.md" "$w/findings.before"
run "replay, assemble" 0 "live: kept live/findings.md${nl}live: kept live/claims.md" "" assemble s1 s1/tmp/live-entries
cmp -s "$w/findings.before" "$w/s1/live/findings.md" || fail "replay: live/findings.md changed"
cmp -s "$w/claims.before" "$w/s1/live/claims.md" || fail "replay: live/claims.md changed"

# Rebuild: a deleted derived file is a new winner.
rm "$w/s1/live/findings.md"
want="winner${tab}g1-F2${tab}live/results-2.md:7${tab}live/results-1.md:7${tab}new
winner${tab}X1${tab}live/results-1.md:14${tab}none${tab}new
winner${tab}claim 3${tab}live/results-1.md:21${tab}none${tab}kept"
run "rebuild findings, active" 0 "$want" "" active s1
rm "$w/s1/live/claims.md"
want="winner${tab}g1-F2${tab}live/results-2.md:7${tab}live/results-1.md:7${tab}new
winner${tab}X1${tab}live/results-1.md:14${tab}none${tab}new
winner${tab}claim 3${tab}live/results-1.md:21${tab}none${tab}new"
run "rebuild both, active" 0 "$want" "" active s1
mk_entries "$w/s1/tmp/live-entries"
printf '## claim 3\n- derived: true, reproduced\n' > "$w/s1/tmp/live-entries/c.md"
run "rebuild, assemble" 0 "live: wrote live/findings.md${nl}live: wrote live/claims.md" "" assemble s1 s1/tmp/live-entries
same "rebuild, findings" "$w/s1/live/findings.md" "$findings_want"
same "rebuild, claims" "$w/s1/live/claims.md" "## claim 3
- source: live/results-1.md:21
- earlier: none
- derived: true, reproduced"

# A rejected assemble writes nothing and keeps the entries.
# fail_asm <label> <dir> <expected output>
fail_asm() {
	before=$(snap "$2")
	run "$1" 1 "$3" "" assemble "$2" "$2/tmp/live-entries"
	[ "$(snap "$2")" = "$before" ] || fail "$1: changed the run directory"
}

mk_state s2 1
mk_entries "$w/s2/tmp/live-entries"
rm "$w/s2/tmp/live-entries/b.md"
fail_asm "assemble, missing entry" s2 "live: no entry for 'X1'"

mk_state s3 1
mk_entries "$w/s3/tmp/live-entries"
printf '## claim 3\n- derived: true, reproduced\n' > "$w/s3/tmp/live-entries/c.md"
fail_asm "assemble, entry for a kept winner" s3 "live: c.md: 'claim 3' is not a new or changed winner"

mk_state s4 1
mk_entries "$w/s4/tmp/live-entries"
printf '## g1-F2\n- derived: again\n' > "$w/s4/tmp/live-entries/c.md"
fail_asm "assemble, id in two entries" s4 "live: c.md: 'g1-F2' is also in a.md"

mk_state s5 1
mk_entries "$w/s5/tmp/live-entries"
printf '## g1-F2\n- source: live/results-9.md:1\n- derived: dropped\n' > "$w/s5/tmp/live-entries/a.md"
fail_asm "assemble, entry with a source line" s5 "live: a.md:2: line starts with '- source:'"

mk_state s6 0
mk_entries "$w/s6/tmp/live-entries"
fail_asm "assemble, carried file missing" s6 "live: live/carried/X1.md is missing"

mk_state s7 1
mk_entries "$w/s7/tmp/live-entries"
printf '## g1-F2\n\n- derived: dropped\n- earlier: x\n## x\nd\r\n' > "$w/s7/tmp/live-entries/a.md"
printf 'X1\n' > "$w/s7/tmp/live-entries/b.md"
printf '## unknown\n' > "$w/s7/tmp/live-entries/c.md"
want="live: a.md:2: empty line
live: a.md:4: line starts with '- earlier:'
live: a.md:5: line starts with '## '
live: a.md:6: carriage return
live: b.md:1: first line must be '## <id>'
live: b.md: no derivation lines
live: c.md: no derivation lines
live: c.md: 'unknown' is not a new or changed winner
live: no entry for 'X1'"
fail_asm "assemble, entry errors in order" s7 "$want"

# Every import retired: both files are removed, nothing is left empty.
mk_state s8 1
printf '1 retired 2026-10-01T10:00:00Z: a\n2 retired 2026-10-01T10:00:00Z: a\n3 retired 2026-10-01T10:00:00Z: a\n' > "$w/s8/live/retired.md"
run "assemble, no winners" 0 "live: removed live/findings.md${nl}live: removed live/claims.md" "" assemble s8 s8/tmp/live-entries
absent "assemble, no winners" "$w/s8/live/findings.md"
absent "assemble, no winners" "$w/s8/live/claims.md"
run "assemble, no winners again" 0 "live: absent live/findings.md${nl}live: absent live/claims.md" "" assemble s8 s8/tmp/live-entries

# An entry line over 8,192 bytes is kept whole.
mk_state s9 1
mk_entries "$w/s9/tmp/live-entries"
{ printf '## g1-F2\n- derived: '; long; } > "$w/s9/tmp/live-entries/a.md"
run "assemble, long line" 0 "live: wrote live/findings.md${nl}live: kept live/claims.md" "" assemble s9 s9/tmp/live-entries
[ "$(sha "$w/s9/live/findings.md")" = 617475361f432f39b0e5e5a898153d35a9b607efd14861b39f5464689118cd3e ] || fail "assemble, long line: live/findings.md differs"
# A long line in a kept section passes through whole too.
run "assemble, long line kept" 0 "live: kept live/findings.md${nl}live: kept live/claims.md" "" assemble s9 s9/tmp/live-entries
[ "$(sha "$w/s9/live/findings.md")" = 617475361f432f39b0e5e5a898153d35a9b607efd14861b39f5464689118cd3e ] || fail "assemble, long line kept: live/findings.md differs"
# An entry file without its final newline gets one.
mk_state s10 1
mkdir "$w/s10/e"
printf '## g1-F2\n- derived: dropped' > "$w/s10/e/a.md"
printf '## X1\n- derived: x\n' > "$w/s10/e/b.md"
run "assemble, no final newline" 0 "live: wrote live/findings.md${nl}live: kept live/claims.md" "" assemble s10 s10/e
same "assemble, no final newline" "$w/s10/live/findings.md" "## g1-F2
- source: live/results-2.md:7
- earlier: live/results-1.md:7
- derived: dropped
## X1
- source: live/results-1.md:14
- earlier: none
- derived: x"

# --- retire ----------------------------------------------------------------

mk_state t1 1
printf 'stale\n' > "$w/t1/live/results-7.md.pending"
run "retire" 0 "live: retired 1
live: retired 2
live: moved live/findings.md
live: moved live/claims.md
live: moved live/carried" "" retire t1 t1/superseded/1/live "stage 4 rerun"
lines=$(wc -l < "$w/t1/live/retired.md")
[ "$lines" -eq 3 ] || fail "retire: live/retired.md has $lines lines"
[ "$(sed -n 1p "$w/t1/live/retired.md")" = "3 retired 2026-10-01T10:00:00Z: stage 4 rerun" ] || fail "retire: the first line changed"
for n in 1 2; do
	line=$(sed -n "$((n + 1))p" "$w/t1/live/retired.md")
	[ "${line#"$n retired "}" != "$line" ] || fail "retire: line $((n + 1)) does not start with '$n retired '"
	case $line in
	*": stage 4 rerun") ;;
	*) fail "retire: line $((n + 1)) does not end with ': stage 4 rerun'" ;;
	esac
	t=${line#"$n retired "}
	t=${t%": stage 4 rerun"}
	if ! printf '%s\n' "$t" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
		fail "retire: line $((n + 1)) time '$t' is not a UTC time"
	fi
done
absent "retire" "$w/t1/live/findings.md"
absent "retire" "$w/t1/live/claims.md"
absent "retire" "$w/t1/live/carried"
absent "retire" "$w/t1/live/results-7.md.pending"
for n in 1 2 3; do
	[ -f "$w/t1/live/results-$n.md" ] || fail "retire: live/results-$n.md is gone"
done
same "retire, moved findings" "$w/t1/superseded/1/live/findings.md" "## g1-F2
- source: live/results-1.md:7
- earlier: none
- result 12 rows; derived: verified fact"
same "retire, moved carried" "$w/t1/superseded/1/live/carried/X1.md" "### X1: Missing index on orders
- finding text"
[ -f "$w/t1/superseded/1/live/claims.md" ] || fail "retire: claims.md was not moved"
before=$(snap t1)
run "retire again" 0 "" "" retire t1 t1/superseded/2/live "stage 4 rerun"
[ "$(snap t1)" = "$before" ] || fail "retire again: changed the run directory"
run "import after retire" 0 "live: imported live/results-4.md" "" import valid.md report.md t1
run "retire, no live" 0 "" "" retire a0 a0/superseded/1/live "r"
run "retire, empty reason" 2 "" "live: the reason is empty or has a newline" retire t1 t1/superseded/3/live ""
run "retire, no run directory" 2 "" "live: cannot read run directory nope" retire nope nope/x r

# Nothing to move: the destination is not created.
rm -rf "$w/t4" && mkdir -p "$w/t4/live"
res_file "$w/t4/live/results-1.md" 2026-10-01T09:00:00Z g1-F2
run "retire, nothing to move" 0 "live: retired 1" "" retire t4 t4/superseded/1/live "stage 4 rerun"
absent "retire, nothing to move" "$w/t4/superseded"
[ "$(wc -l < "$w/t4/live/retired.md")" -eq 1 ] || fail "retire, nothing to move: live/retired.md is not one line"

# Recovery: the retirement lines were appended but the derived files were not moved.
mk_state t2 1
printf '1 retired 2026-10-01T10:00:00Z: stage 4 rerun\n2 retired 2026-10-01T10:00:00Z: stage 4 rerun\n3 retired 2026-10-01T10:00:00Z: stage 4 rerun\n' > "$w/t2/live/retired.md"
cp "$w/t2/live/retired.md" "$w/retired.before"
run "recovery, retire" 0 "live: moved live/findings.md
live: moved live/claims.md
live: moved live/carried" "" retire t2 t2/superseded/2/live "stage 4 rerun"
cmp -s "$w/retired.before" "$w/t2/live/retired.md" || fail "recovery, retire: live/retired.md changed"
[ -f "$w/t2/superseded/2/live/findings.md" ] || fail "recovery, retire: findings.md was not moved"

# Recovery: live/findings.md was written, live/claims.md was not.
mk_state t3 1
printf '%s\n' "$findings_want" > "$w/t3/live/findings.md"
rm "$w/t3/live/claims.md"
printf '{"approvals":[]}\n' > "$w/t3/stages.json"
want="approve${tab}live/results-1.md:7${tab}g1-F2${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-1.md:14${tab}X1${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-1.md:21${tab}claim 3${tab}Ana Ruiz${tab}2026-10-01T09:00:00Z
approve${tab}live/results-2.md:7${tab}g1-F2${tab}Ana Ruiz${tab}2026-10-01T09:30:00Z
winner${tab}g1-F2${tab}live/results-2.md:7${tab}live/results-1.md:7${tab}kept
winner${tab}X1${tab}live/results-1.md:14${tab}none${tab}kept
winner${tab}claim 3${tab}live/results-1.md:21${tab}none${tab}new"
run "recovery, active" 0 "$want" "" active t3
mkdir -p "$w/t3/e"
printf '## claim 3\n- derived: true, reproduced\n' > "$w/t3/e/a.md"
cp "$w/t3/live/findings.md" "$w/findings.before"
run "recovery, assemble" 0 "live: kept live/findings.md${nl}live: wrote live/claims.md" "" assemble t3 t3/e
cmp -s "$w/findings.before" "$w/t3/live/findings.md" || fail "recovery, assemble: live/findings.md changed"
same "recovery, claims" "$w/t3/live/claims.md" "## claim 3
- source: live/results-1.md:21
- earlier: none
- derived: true, reproduced"

# --- malformed state -------------------------------------------------------

# bad_derived <label> <name> <content>: a derived file that active and assemble reject.
# $4 is the expected output.
bad_derived() {
	mk_state m1 1
	printf '%s' "$3" > "$w/m1/live/$2"
	before=$(snap m1)
	run "$1, active" 1 "$4" "" active m1
	run "$1, assemble" 1 "$4" "" assemble m1 m1/e
	[ "$(snap m1)" = "$before" ] || fail "$1: changed the run directory"
}

sfx="; delete the file to rebuild it"
bad_derived "line before the first section" findings.md "stray
## g1-F2
- source: live/results-1.md:7
- earlier: none
- d
" "live: live/findings.md:1: line before the first section$sfx"
bad_derived "section twice" findings.md "## g1-F2
- source: live/results-1.md:7
- earlier: none
- d
## g1-F2
- source: live/results-1.md:7
- earlier: none
- d
" "live: live/findings.md:5: section 'g1-F2' twice$sfx"
bad_derived "no source line" findings.md "## g1-F2
- earlier: none
- earlier: none
- d
" "live: live/findings.md:2: line 2 of a section must be '- source: <source>'$sfx"
bad_derived "no earlier line" claims.md "## claim 3
- source: live/results-1.md:21
- d
- d
" "live: live/claims.md:3: line 3 of a section must be '- earlier: <sources>'$sfx"
bad_derived "no derivation lines" findings.md "## g1-F2
- source: live/results-1.md:7
- earlier: none
## X1
- source: live/results-1.md:14
- earlier: none
- d
" "live: live/findings.md:1: no derivation lines$sfx"
bad_derived "empty line" findings.md "## g1-F2
- source: live/results-1.md:7
- earlier: none

- d
" "live: live/findings.md:4: empty line$sfx"
bad_derived "carriage return" findings.md "## g1-F2
- source: live/results-1.md:7
- earlier: none
- d$(printf '\r')
" "live: live/findings.md:4: carriage return$sfx"
bad_derived "no final newline" claims.md "## claim 3
- source: live/results-1.md:21
- earlier: none
- d" "live: live/claims.md:4: no final newline$sfx"
bad_derived "claims, line before the first section" claims.md "- d
" "live: live/claims.md:1: line before the first section$sfx"
mk_state m2 1
printf 'stray\n' > "$w/m2/live/findings.md"
printf 'stray\n' > "$w/m2/live/claims.md"
run "findings checked before claims" 1 "live: live/findings.md:1: line before the first section$sfx
live: live/claims.md:1: line before the first section$sfx" "" active m2

# A stray line in live/retired.md.
mk_state m3 1
printf '3 retired 2026-10-01T10:00:00Z: stage 4 rerun\ngarbage\n01 retired 2026-10-01T10:00:00Z: x\n' > "$w/m3/live/retired.md"
want="live: live/retired.md:2: not a retirement record
live: live/retired.md:3: not a retirement record"
printf 'stale\n' > "$w/m3/live/results-7.md.pending"
before=$(snap m3)
run "retired.md stray, active" 1 "$want" "" active m3
run "retired.md stray, assemble" 1 "$want" "" assemble m3 m3/e
run "retired.md stray, retire" 1 "$want" "" retire m3 m3/superseded/1/live "stage 4 rerun"
[ "$(snap m3)" = "$before" ] || fail "retired.md stray: changed the run directory"
absent "retired.md stray" "$w/m3/superseded"

# --- operational failures --------------------------------------------------

rm -rf "$w/o1" && mkdir "$w/o1"
printf 'not a directory\n' > "$w/o1/live"
before=$(snap o1)
run "import, live is a file" 2 "" "live: cannot create o1/live" import valid.md report.md o1
[ "$(snap o1)" = "$before" ] || fail "import, live is a file: changed the run directory"

mk_state o2 1
printf 'not json\n' > "$w/o2/stages.json"
before=$(snap o2)
run "active, stages.json is not JSON" 2 "" "live: cannot read the approvals in o2/stages.json" active o2
[ "$(snap o2)" = "$before" ] || fail "active, bad stages.json: changed the run directory"

mk_state o3 1
printf 'a file\n' > "$w/o3/blocker"
before=$(snap o3)
run "retire, destination under a file" 2 "" "live: cannot create o3/blocker/superseded/1/live" retire o3 o3/blocker/superseded/1/live "stage 4 rerun"
[ "$(snap o3)" = "$before" ] || fail "retire, destination under a file: changed the run directory"

if [ "$fails" -eq 0 ]; then
	echo "live test: ok"
	exit 0
fi
exit 1
