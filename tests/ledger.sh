#!/bin/sh
# ledger.sh: tests for skills/cca/scripts/ledger.sh.
#
# Usage: sh tests/ledger.sh
#
# Builds an inline run directory in a temp dir (three pass-one scopes, a failed pass-one
# file, a failed and a not-run pass two, a top-up, a second opinion, a late adversary, and
# a converged.md), runs each op on it and on one-change copies of it, and compares stdout
# and exit codes with literal expected values.
#
# Prints one line per mismatch and `ledger test: ok` on success; exits 1 on any mismatch.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
ls=$root/skills/cca/scripts/ledger.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

nl='
'

fails=0
fail() {
	echo "ledger test: $*"
	fails=$((fails + 1))
}

# run <label> <expected exit> <expected stdout> <ledger.sh args...>: stdout is compared
# after command substitution, so trailing newlines are not significant.
run() {
	label=$1
	want_st=$2
	want_out=$3
	shift 3
	if out=$(sh "$ls" "$@" 2> "$tmp/err"); then st=0; else st=$?; fi
	[ "$st" = "$want_st" ] || fail "$label: expected exit $want_st, got $st"
	[ "$out" = "$want_out" ] || fail "$label: expected output '$want_out', got '$out'"
}

# runf <label> <expected exit> <expected stdout file> <args...>: stdout is compared byte
# for byte with the file.
runf() {
	label=$1
	want_st=$2
	want_file=$3
	shift 3
	if sh "$ls" "$@" > "$tmp/outf" 2> "$tmp/err"; then st=0; else st=$?; fi
	[ "$st" = "$want_st" ] || fail "$label: expected exit $want_st, got $st"
	if ! cmp -s "$want_file" "$tmp/outf"; then
		fail "$label: stdout differs from the expected file; first differences:"
		diff "$want_file" "$tmp/outf" | head -n 8
	fi
}

# errmsg <label> <expected stderr>: the stderr of the last run.
errmsg() {
	got=$(cat "$tmp/err")
	[ "$got" = "$2" ] || fail "$1: expected stderr '$2', got '$got'"
}

# crlf <file>: rewrite a file with CRLF line ends.
crlf() {
	awk 'BEGIN { ORS = "\r\n" } { print }' "$1" > "$1.crlf" && mv "$1.crlf" "$1"
}

# mk6 <dir> <positioned ids> <seen ids> <X ids>: ledger/6.md with a three-line position
# section for each positioned id. The header takes lines 1 to 6 and each section five
# lines, so the section k (from 0) starts at line 7 + 5k.
mk6() {
	{
		printf '## Role\ncodex m-x, thread t1\n\n## Acknowledgments\n- inputs: acknowledged\n\n'
		for id in $2; do
			printf '## %s\n- position: agrees\n- evidence: %s@abc:f.js:1\n- answer location: codex/response.md, %s\n\n' "$id" "$id" "$id"
		done
		for id in $4; do
			printf '### %s: Extra issue\n- severity: low\n- question: Q1\n- label: convention\n- origin: codex\n- evidence: x\n\n' "$id"
		done
		printf '## Merge verdict (non-binding)\nmerge with care\n\n## Seen, no position\n'
		for id in $3; do
			printf -- '- %s\n' "$id"
		done
	} > "$1/ledger/6.md"
}

# mk7 <dir> <verdict ids> <L ids>: ledger/7.md and the matching late/adversary.md.
mk7() {
	{
		for id in $2; do
			printf '## %s\n- verdict: survives by cca:adversary (late, model m-c)\n- reason: stands\n- evidence: e\n\n' "$id"
		done
		for id in $3; do
			printf '### %s: New late finding\n- severity: low\n- question: Q1\n- label: convention\n- origin: late\n- evidence: x\n\n' "$id"
		done
	} > "$1/ledger/7.md"
	{
		printf '# Late adversary\n\n'
		for id in $2; do
			printf '### verdict on %s: survives\n- severity: unchanged\n- label: unchanged\n- evidence: e\n- reason: stands\n\n' "$id"
		done
		for id in $3; do
			printf '### %s: New late finding\n- severity: low\n- question: Q1\n- label: convention\n- origin: late\n- evidence: x\n\n' "$id"
		done
		printf 'runs: none\nstatus: complete\n'
	} > "$1/late/adversary.md"
}

# mkruns <dir>: the pass-one, pass-two, and top-up files and the inventory.
mkruns() {
	d=$1
	mkdir -p "$d/pass1" "$d/pass2" "$d/ledger" "$d/codex" "$d/late"
	cat > "$d/ledger/inventory.txt" <<'EOF'
pass1 app pass1/app.md m-a complete
pass1 web pass1/web.md m-a complete

pass1 cfg pass1/cfg.md m-a complete
pass1 bad pass1/bad.md m-a failed
pass2 app pass2/app.md m-b complete
pass2 web pass2/web.md m-b failed
pass2 cfg - - not-run
topup app pass2/app-topup.md m-a complete
EOF
	cat > "$d/pass1/app.md" <<'EOF'
# Pass one: app

### app-F1: Limit is off by one
- severity: high
- question: Q1
- label: verified fact
- evidence: app@abc:src/a.js:10 `if (n > limit)`
- demonstrated: the guard uses a greater-than
- recommended change: app src/a.js use >=

### app-F2: Unused flag
- severity: low
- question: Q2
- label: convention
- evidence: search git grep flag, result:
```text
### app-F9: not a finding
## Not a heading
```
- demonstrated: the flag has no reader

### app-F4: Retry text wrong
- severity: medium
- question: Q1
- label: verified fact
- evidence: app@abc:src/r.js:3 "retry twice"
- demonstrated: the text says twice

## Top-up
### app-F3: Missing null check
- severity: medium
- question: Q1
- label: unverified assumption
- evidence: app@abc:src/n.js:5
- demonstrated: none
- inferred: it may crash

## Verified OK
- app-OK1: guard checked

## Claims
- claim 1: true

## Decisions
none
runs: none
consumed: none
status: complete
EOF
	# A pre-top-up copy that repeats a finding id: it must be ignored.
	cat > "$d/pass1/app.pre-topup.md" <<'EOF'
### app-F1: Limit is off by one
- severity: high
- label: verified fact
status: complete
EOF
	cat > "$d/pass1/web.md" <<'EOF'
### web-F1: Missing auth check
- severity: blocker
- question: Q3
- label: verified fact
- evidence: web@abc:s.js:1 "no check"
- demonstrated: no check runs
runs: none
consumed: none
status: complete
EOF
	cat > "$d/pass1/cfg.md" <<'EOF'
# Pass one: cfg

### cfg-F1: Stale comment
- severity: note
- question: Q2
- label: convention
- evidence: cfg@abc:c.yml:4

## Verified OK
none
runs: none
consumed: none
status: complete
EOF
	printf 'partial output\n' > "$d/pass1/bad.md"
	cat > "$d/pass2/app.md" <<'EOF'
# Pass two: app

### verdict on app-F1: downgraded
- severity: high -> medium
- label: unchanged
- evidence: app@abc:src/a.js:10 shows the guard
- reason: a guard exists

### verdict on app-F2: survives
- severity: unchanged
- label: unchanged
- evidence: git grep flag finds no reader
- reason: stands

### verdict on app-F4: reworded
- severity: unchanged
- label: unchanged
- evidence: app@abc:src/r.js:3 says twice or thrice
- reason: the text says twice or thrice

### verdict on app-F3: dropped
- severity: medium -> low
- label: unverified assumption -> convention
- evidence: app@abc:src/n.js:5 has the check
- reason: not a defect

## Verified OK challenged
- app-OK1: held

## Coverage gaps
- none

### app-P1: Added by the adversary
- severity: medium
- question: Q1
- label: verified fact
- origin: pass2
- evidence: app@abc:src/p.js:2
- demonstrated: yes

## Map corrections
none
runs: none
consumed: none
status: complete
EOF
	printf 'partial output\n' > "$d/pass2/web.md"
	cat > "$d/pass2/app-topup.md" <<'EOF'
### app-T1: Found after a map fix
- severity: low
- question: Q1
- label: convention
- origin: topup
- evidence: app@abc:src/m.js:8
runs: none
consumed: none
status: complete
EOF
}

# want5 <file>: the expected build5 output for mkruns.
want5() {
	cat > "$1" <<'EOF'
## app-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/app.md
### Original
### app-F1: Limit is off by one
- severity: high
- question: Q1
- label: verified fact
- evidence: app@abc:src/a.js:10 `if (n > limit)`
- demonstrated: the guard uses a greater-than
- recommended change: app src/a.js use >=
### Pass-two verdicts
- downgraded by cca:adversary (model m-b) in pass2/app.md: a guard exists; evidence: app@abc:src/a.js:10 shows the guard
### State after pass two
medium, verified fact, downgraded

## app-F2
- origin: pass1
- author: cca:auditor, model m-a, file pass1/app.md
### Original
### app-F2: Unused flag
- severity: low
- question: Q2
- label: convention
- evidence: search git grep flag, result:
```text
### app-F9: not a finding
## Not a heading
```
- demonstrated: the flag has no reader
### Pass-two verdicts
- survives by cca:adversary (model m-b) in pass2/app.md: stands; evidence: git grep flag finds no reader
### State after pass two
low, convention, survives

## app-F4
- origin: pass1
- author: cca:auditor, model m-a, file pass1/app.md
### Original
### app-F4: Retry text wrong
- severity: medium
- question: Q1
- label: verified fact
- evidence: app@abc:src/r.js:3 "retry twice"
- demonstrated: the text says twice
### Pass-two verdicts
- reworded by cca:adversary (model m-b) in pass2/app.md: the text says twice or thrice; evidence: app@abc:src/r.js:3 says twice or thrice
### State after pass two
medium, verified fact, reworded

## app-F3
- origin: pass1
- author: cca:auditor, model m-a, file pass1/app.md
### Original
### app-F3: Missing null check
- severity: medium
- question: Q1
- label: unverified assumption
- evidence: app@abc:src/n.js:5
- demonstrated: none
- inferred: it may crash
### Pass-two verdicts
- dropped by cca:adversary (model m-b) in pass2/app.md: not a defect; evidence: app@abc:src/n.js:5 has the check
### State after pass two
low, convention, dropped

## app-P1
- origin: pass2
- author: cca:adversary, model m-b, file pass2/app.md
### Original
### app-P1: Added by the adversary
- severity: medium
- question: Q1
- label: verified fact
- origin: pass2
- evidence: app@abc:src/p.js:2
- demonstrated: yes
### Pass-two verdicts
- none
### State after pass two
medium, verified fact, no verdict: late addition

## app-T1
- origin: topup
- author: cca:auditor, model m-a, file pass2/app-topup.md
### Original
### app-T1: Found after a map fix
- severity: low
- question: Q1
- label: convention
- origin: topup
- evidence: app@abc:src/m.js:8
### Pass-two verdicts
- none
### State after pass two
low, convention, no verdict: late addition

## web-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/web.md
### Original
### web-F1: Missing auth check
- severity: blocker
- question: Q3
- label: verified fact
- evidence: web@abc:s.js:1 "no check"
- demonstrated: no check runs
### Pass-two verdicts
- none
### State after pass two
blocker, verified fact, no verdict: scope failed

## cfg-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/cfg.md
### Original
### cfg-F1: Stale comment
- severity: note
- question: Q2
- label: convention
- evidence: cfg@abc:c.yml:4
### Pass-two verdicts
- none
### State after pass two
note, convention, no verdict: not run, budget expired

## Verified OK challenged: app
- app-OK1: held

## Coverage gaps: app
- none

## Failed outputs
- pass1/bad.md
- pass2/web.md

EOF
}

# mkbase <dir>: mkruns plus ledger/5.md (the expected build5 output and the two map
# sections), a complete ledger/6.md with its answer, and ledger/7.md with the late file.
mkbase() {
	mkruns "$1"
	want5 "$1/ledger/5.md"
	printf '## Map corrections applied\n- none\n\n## Map corrections not applied\n- none\n' >> "$1/ledger/5.md"
	mk6 "$1" "app-F1 app-F3 app-F4 app-P1 web-F1" "app-F2 app-T1 cfg-F1" "X1"
	cat > "$1/codex/response.md" <<'EOF'
# Second opinion

- app-F1: agree with the downgrade
* `app-F3`: the drop stands
**app-F4**: reword accepted
  # app-P1: stands at medium
web-F1: confirmed blocker
cfg-F1 is fine, no comment

### X1: Extra issue
It is a low issue.
EOF
	mk7 "$1" "app-P1 app-T1 X1" "L1"
	cat > "$1/gate.md" <<'GEOF'
app-F1: counts; stage 5 verdict, stage 6 position
app-F2: counts; stage 5 verdict, stage 6 acknowledged (low or note)
app-F4: counts; stage 5 verdict, stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: counts; late verdict, stage 6 position
app-T1: counts; late verdict, stage 6 acknowledged (low or note)
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: counts; late verdict
L1: provisional; late finding
GEOF
	cat > "$1/converged.md" <<'CEOF'
# Converged

## C1: Limit guard
- absorbs: app-F1, app-F3
- sources: app-F1 pass1
- gate: counts
- disposition: agreed

## C2: Flag and retry text
- absorbs: app-F2, app-F4
- gate: counts

## C3: Late additions
- absorbs: app-P1, app-T1
- gate: counts

## C4: Unreviewed
- absorbs: web-F1, cfg-F1
- gate: provisional

## C5: Extra
- absorbs: X1
- gate: counts

## C6: Late finding
- absorbs: L1
- gate: provisional

runs: none
status: complete
CEOF
}

want5 "$tmp/want5.txt"
B=$tmp/base
mkbase "$B"
mkdir -p "$tmp/empty"

# ---------------------------------------------------------------------------
# build5 on the base run.
runf "build5" 0 "$tmp/want5.txt" build5 "$B"

# CRLF input gives the same output.
cp -R "$B" "$tmp/crlf"
for f in ledger/inventory.txt pass1/app.md pass1/web.md pass1/cfg.md pass2/app.md pass2/app-topup.md; do
	crlf "$tmp/crlf/$f"
done
runf "build5, CRLF input" 0 "$tmp/want5.txt" build5 "$tmp/crlf"

# ---------------------------------------------------------------------------
# build5 errors: stderr lines, exit 1, no stdout.
cp -R "$B" "$tmp/e1"
printf '### app-F1: Again\n- severity: low\n- label: convention
status: complete
' >> "$tmp/e1/pass1/app.md"
run "duplicate id" 1 "" build5 "$tmp/e1"
errmsg "duplicate id" "ledger: pass1/app.md:49: duplicate finding id app-F1"

cp -R "$B" "$tmp/e2"
printf '### verdict on app-F7: survives\n- severity: unchanged\n- label: unchanged\n- evidence: e
status: complete
' >> "$tmp/e2/pass2/app.md"
run "verdict for unknown id" 1 "" build5 "$tmp/e2"
errmsg "verdict for unknown id" "ledger: pass2/app.md:46: verdict on app-F7 has no finding"

cp -R "$B" "$tmp/e3"
sed 's/^- severity: high$/- severity: urgent/' "$B/pass1/app.md" > "$tmp/e3/pass1/app.md"
run "malformed severity" 1 "" build5 "$tmp/e3"
errmsg "malformed severity" "ledger: pass1/app.md:3: app-F1: severity 'urgent' is not blocker, high, medium, low, or note"

cp -R "$B" "$tmp/e4"
printf '### extra-F1: Not inventoried\n- severity: low\n- label: convention\n' > "$tmp/e4/pass1/extra.md"
run "un-inventoried pass1 file" 1 "" build5 "$tmp/e4"
errmsg "un-inventoried pass1 file" "ledger: pass1/extra.md is not in ledger/inventory.txt"

cp -R "$B" "$tmp/e5"
rm "$tmp/e5/pass1/cfg.md"
run "inventory names a missing file" 1 "" build5 "$tmp/e5"
errmsg "inventory names a missing file" "ledger: ledger/inventory.txt:4: pass1/cfg.md does not exist"

cp -R "$B" "$tmp/e6"
sed '/^### verdict on app-F4/,/^- reason: the text says twice or thrice/d' "$B/pass2/app.md" > "$tmp/e6/pass2/app.md"
run "finding without a verdict in a complete pass two" 1 "" build5 "$tmp/e6"
errmsg "finding without a verdict" "ledger: pass2/app.md: no verdict for app-F4"

cp -R "$B" "$tmp/e7"
printf '### verdict on app-F2: survives\n- severity: unchanged\n- label: unchanged\n- evidence: again
status: complete
' >> "$tmp/e7/pass2/app.md"
run "duplicate verdict" 1 "" build5 "$tmp/e7"
errmsg "duplicate verdict" "ledger: pass2/app.md:46: duplicate verdict for app-F2"

cp -R "$B" "$tmp/e8"
sed 's/^- evidence: git grep flag finds no reader$/- evidence:/' "$B/pass2/app.md" > "$tmp/e8/pass2/app.md"
run "verdict without evidence" 1 "" build5 "$tmp/e8"
errmsg "verdict without evidence" "ledger: pass2/app.md:9: verdict on app-F2: needs exactly one nonempty - evidence: line"

cp -R "$B" "$tmp/e9"
printf '\n```\nunclosed\n' >> "$tmp/e9/pass1/cfg.md"
run "unclosed fence" 1 "" build5 "$tmp/e9"
errmsg "unclosed fence" "ledger: pass1/cfg.md: the file ends inside a code fence
ledger: pass1/cfg.md: the inventory says complete, but the file does not end with status: complete"

# ---------------------------------------------------------------------------
# mandatory: blocker, high, medium after pass two, downgraded or dropped, and live ids.
run "mandatory" 0 "app-F1${nl}app-F3${nl}app-F4${nl}app-P1${nl}web-F1" mandatory "$B"

cp -R "$B" "$tmp/m1"
mkdir -p "$tmp/m1/live/carried"
printf -- '---\ncca-live: 1\n---\n\n## app-F2\n- query: q\n\n## X7\n- query: q\n' > "$tmp/m1/live/findings.md"
printf '### X7: Carried\n' > "$tmp/m1/live/carried/X7.md"
run "mandatory with live ids" 0 "X7${nl}app-F1${nl}app-F2${nl}app-F3${nl}app-F4${nl}app-P1${nl}web-F1" mandatory "$tmp/m1"

# seen excludes the mandatory ids and the ids with a position section.
run "seen, none positioned" 0 "- app-F2${nl}- app-T1${nl}- cfg-F1" seen "$B"
cp -R "$B" "$tmp/s1"
mk6 "$tmp/s1" "app-F1 app-F2 web-F1" "app-T1 cfg-F1" ""
run "seen, app-F2 positioned" 0 "- app-T1${nl}- cfg-F1" seen "$tmp/s1"
run "seen, live id app-F2 is mandatory" 0 "- app-T1${nl}- cfg-F1" seen "$tmp/m1"

# ---------------------------------------------------------------------------
# check --through 5.
run "check 5, base" 0 "" check "$B" --through 5

cp -R "$B" "$tmp/c1"
sed 's/^- survives by cca:adversary (model m-b) in pass2\/app.md: stands; evidence: git grep flag finds no reader$/- survives by cca:adversary (model m-b) in pass2\/app.md: stands; evidence: invented/' "$B/ledger/5.md" > "$tmp/c1/ledger/5.md"
run "check 5, altered verdict line" 1 "ledger: ledger/5.md differs from the build5 output at line 32" check "$tmp/c1" --through 5

cp -R "$B" "$tmp/c2"
sed '/^## app-F4$/,/^medium, verified fact, reworded$/d' "$B/ledger/5.md" > "$tmp/c2/ledger/5.md"
run "check 5, omitted finding" 1 "ledger: ledger/5.md: no section for app-F4${nl}ledger: ledger/5.md differs from the build5 output at line 36" check "$tmp/c2" --through 5

cp -R "$B" "$tmp/c3"
sed 's/^## app-F4$/## app-F8/' "$B/ledger/5.md" > "$tmp/c3/ledger/5.md"
run "check 5, unknown id" 1 "ledger: ledger/5.md: no section for app-F4${nl}ledger: ledger/5.md: section for app-F8, which no inventoried file holds${nl}ledger: ledger/5.md differs from the build5 output at line 36" check "$tmp/c3" --through 5

# The map-correction sections after the generated part are free text.
cp -R "$B" "$tmp/c4"
printf '## Map corrections applied\n- domain/app-map.r2.md, lines 3 to 4\n\n## Map corrections not applied\n- one round\n' > "$tmp/c4/tail.txt"
sed '/^## Map corrections applied$/,$d' "$B/ledger/5.md" > "$tmp/c4/ledger/5.md"
cat "$tmp/c4/tail.txt" >> "$tmp/c4/ledger/5.md"
run "check 5, other map sections" 0 "" check "$tmp/c4" --through 5

# The inventory must name every file (the pre-top-up copy is exempt) and the build errors show.
run "check 5, un-inventoried file" 1 "ledger: pass1/extra.md is not in ledger/inventory.txt" check "$tmp/e4" --through 5

# ---------------------------------------------------------------------------
# check --through 6.
run "check 6, base" 0 "" check "$B" --through 6 --stage6 complete

cp -R "$B" "$tmp/d1"
mk6 "$tmp/d1" "app-F1 app-F2 app-F3 app-F4 app-P1 web-F1" "app-T1 cfg-F1" "X1"
run "check 6, invented position" 1 "ledger: ledger/6.md:12: no line starting 'app-F2:' in the codex response files" check "$tmp/d1" --through 6 --stage6 complete

cp -R "$B" "$tmp/d2"
mk6 "$tmp/d2" "app-F1 app-F4 app-P1 web-F1" "app-F2 app-T1 cfg-F1" "X1"
run "check 6, missing mandatory position" 1 "ledger: ledger/6.md: mandatory id app-F3 has no position" check "$tmp/d2" --through 6 --stage6 complete

cp -R "$B" "$tmp/d3"
mk6 "$tmp/d3" "app-F1 app-F3 app-F4 app-P1 web-F1" "app-F1 app-F2 app-T1 cfg-F1" "X1"
run "check 6, mandatory and seen overlap" 1 "ledger: ledger/6.md: '## Seen, no position' lists mandatory id app-F1" check "$tmp/d3" --through 6 --stage6 complete

cp -R "$B" "$tmp/d4"
mk6 "$tmp/d4" "app-F1 app-F3 app-F4 app-P1 web-F1" "app-T1 cfg-F1" "X1"
run "check 6, seen list misses an id" 1 "ledger: ledger/6.md: '## Seen, no position' does not list app-F2" check "$tmp/d4" --through 6 --stage6 complete

cp -R "$B" "$tmp/d5"
printf '### X2: Another one\nIt is also low.\n' >> "$tmp/d5/codex/response.md"
run "check 6, omitted X addition" 1 "ledger: ledger/6.md: no addition X2, which the codex response files raise" check "$tmp/d5" --through 6 --stage6 complete

cp -R "$B" "$tmp/d6"
mkdir -p "$tmp/d6/live/carried"
printf -- '---\ncca-live: 1\n---\n\n## X1\n- query: q\n' > "$tmp/d6/live/findings.md"
printf '### X1: Carried\n' > "$tmp/d6/live/carried/X1.md"
mk6 "$tmp/d6" "X1 app-F1 app-F3 app-F4 app-P1 web-F1" "app-F2 app-T1 cfg-F1" "X1"
run "check 6, X collides with a carried id" 1 "ledger: ledger/6.md: addition X1 reuses a carried id" check "$tmp/d6" --through 6 --stage6 complete

cp -R "$B" "$tmp/d7"
mk6 "$tmp/d7" "app-F1 app-F1 app-F3 app-F4 app-P1 web-F1" "app-F2 app-T1 cfg-F1" "X1"
run "check 6, two position sections" 1 "ledger: ledger/6.md:12: duplicate position section for app-F1" check "$tmp/d7" --through 6 --stage6 complete

cp -R "$B" "$tmp/d8"
mk6 "$tmp/d8" "app-F1 app-F3 app-F4 app-P1 web-F1 app-F9" "app-F2 app-T1 cfg-F1" "X1"
printf 'app-F9: made up\n' >> "$tmp/d8/codex/response.md"
run "check 6, position for an unknown id" 1 "ledger: ledger/6.md:32: position for unknown id app-F9" check "$tmp/d8" --through 6 --stage6 complete

cp -R "$B" "$tmp/d9"
sed 's/^- evidence: app-F1@abc:f.js:1$/- evidence:/' "$B/ledger/6.md" > "$tmp/d9/ledger/6.md"
run "check 6, position without evidence" 1 "ledger: ledger/6.md:7: app-F1 has no nonempty - evidence: line" check "$tmp/d9" --through 6 --stage6 complete

# With stage 6 failed, the mandatory and seen rules do not apply.
cp -R "$B" "$tmp/d10"
mk6 "$tmp/d10" "app-F1" "" "X1"
run "check 6, stage 6 failed" 0 "" check "$tmp/d10" --through 6 --stage6 failed

# ---------------------------------------------------------------------------
# gate. Arguments: --tier, --stage6, --late.
gate_base="app-F1: counts; stage 5 verdict, stage 6 position
app-F2: counts; stage 5 verdict, stage 6 acknowledged (low or note)
app-F4: counts; stage 5 verdict, stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: counts; late verdict, stage 6 position
app-T1: counts; late verdict, stage 6 acknowledged (low or note)
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: counts; late verdict
L1: provisional; late finding"
run "gate, medium, complete, complete" 0 "$gate_base" gate "$B" --tier medium --stage6 complete --late complete
run "gate, high, same as medium" 0 "$gate_base" gate "$B" --tier high --stage6 complete --late complete

want="app-F1: provisional; stage 6 failed
app-F2: provisional; stage 6 failed
app-F4: provisional; stage 6 failed
app-F3: provisional; stage 6 failed
app-P1: provisional; stage 6 failed
app-T1: provisional; stage 6 failed
web-F1: provisional; stage 6 failed
cfg-F1: provisional; stage 6 failed
X1: counts; late verdict
L1: provisional; late finding"
run "gate, stage 6 failed" 0 "$want" gate "$B" --tier medium --stage6 failed --late complete

want="app-F1: counts; stage 5 verdict, stage 6 position
app-F2: counts; stage 5 verdict, stage 6 acknowledged (low or note)
app-F4: counts; stage 5 verdict, stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: provisional; late addition at low tier
app-T1: provisional; late addition at low tier
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: provisional; late addition at low tier
L1: provisional; late finding"
run "gate, low tier: P, T, X do not count" 0 "$want" gate "$B" --tier low --stage6 complete --late complete

want="app-F1: counts; stage 5 verdict, stage 6 position
app-F2: counts; stage 5 verdict, stage 6 acknowledged (low or note)
app-F4: counts; stage 5 verdict, stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: provisional; no late verdict
app-T1: provisional; no late verdict
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: provisional; no late verdict
L1: provisional; late finding"
run "gate, late failed" 0 "$want" gate "$B" --tier medium --stage6 complete --late failed
run "gate, late not run" 0 "$want" gate "$B" --tier medium --stage6 complete --late not-run

cp -R "$B" "$tmp/g1"
mk6 "$tmp/g1" "app-F1 app-F3 web-F1" "app-F2 app-T1 cfg-F1" "X1"
want="app-F1: counts; stage 5 verdict, stage 6 position
app-F2: counts; stage 5 verdict, stage 6 acknowledged (low or note)
app-F4: provisional; medium or above without a stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: provisional; medium or above without a stage 6 position
app-T1: counts; late verdict, stage 6 acknowledged (low or note)
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: counts; late verdict
L1: provisional; late finding"
run "gate, medium findings without a position" 0 "$want" gate "$tmp/g1" --tier medium --stage6 complete --late complete

# Live-listed ids: app-F2 (pass one) and L7 (carried L), no live review yet.
cp -R "$B" "$tmp/g2"
mkdir -p "$tmp/g2/live/carried"
printf -- '---\ncca-live: 1\n---\n\n## app-F2\n- query: q\n\n## L7\n- query: q\n' > "$tmp/g2/live/findings.md"
printf '### L7: Carried late finding\n' > "$tmp/g2/live/carried/L7.md"
printf '### L8: Not listed in live findings\n' > "$tmp/g2/live/carried/L8.md"
want="app-F1: counts; stage 5 verdict, stage 6 position
app-F2: provisional; live result not yet reviewed
app-F4: counts; stage 5 verdict, stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: counts; late verdict, stage 6 position
app-T1: counts; late verdict, stage 6 acknowledged (low or note)
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: counts; late verdict
L1: provisional; late finding
L7: provisional; live result not yet reviewed"
run "gate, live ids not yet reviewed" 0 "$want" gate "$tmp/g2" --tier medium --stage6 complete --late complete

# The live review completes: positions and late verdicts for app-F2 and L7.
cp -R "$tmp/g2" "$tmp/g3"
mk6 "$tmp/g3" "app-F1 app-F2 app-F3 app-F4 app-P1 web-F1 L7" "app-T1 cfg-F1" "X1"
mk7 "$tmp/g3" "app-P1 app-T1 X1 app-F2 L7" "L1"
want="app-F1: counts; stage 5 verdict, stage 6 position
app-F2: counts; live review completed
app-F4: counts; stage 5 verdict, stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: counts; late verdict, stage 6 position
app-T1: counts; late verdict, stage 6 acknowledged (low or note)
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: counts; late verdict
L1: provisional; late finding
L7: counts; live review completed"
run "gate, live ids reviewed, carried L counts" 0 "$want" gate "$tmp/g3" --tier medium --stage6 complete --late complete

# The live rule is additive: with stage 6 failed the reviewed live ids stay provisional.
want="app-F1: provisional; stage 6 failed
app-F2: provisional; live result not yet reviewed
app-F4: provisional; stage 6 failed
app-F3: provisional; stage 6 failed
app-P1: provisional; stage 6 failed
app-T1: provisional; stage 6 failed
web-F1: provisional; stage 6 failed
cfg-F1: provisional; stage 6 failed
X1: counts; late verdict
L1: provisional; late finding
L7: provisional; live result not yet reviewed"
run "gate, live ids with stage 6 failed" 0 "$want" gate "$tmp/g3" --tier medium --stage6 failed --late complete

# A reviewed live P counts at low tier; an unlisted carried file is not in the universe.
cp -R "$B" "$tmp/g4"
mkdir -p "$tmp/g4/live/carried"
printf -- '---\ncca-live: 1\n---\n\n## app-P1\n- query: q\n' > "$tmp/g4/live/findings.md"
printf '### L8: Not listed\n' > "$tmp/g4/live/carried/L8.md"
want="app-F1: counts; stage 5 verdict, stage 6 position
app-F2: counts; stage 5 verdict, stage 6 acknowledged (low or note)
app-F4: counts; stage 5 verdict, stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: counts; live review completed
app-T1: provisional; late addition at low tier
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: provisional; late addition at low tier
L1: provisional; late finding"
run "gate, live P at low tier" 0 "$want" gate "$tmp/g4" --tier low --stage6 complete --late complete

# A pass-one id whose pass two failed gets no stage 5 credit even with a stage 6 position.
cp -R "$B" "$tmp/g5"
mk6 "$tmp/g5" "app-F1 app-F3 app-F4 app-P1 web-F1 cfg-F1" "app-F2 app-T1" "X1"
run "gate, position without stage 5 verdict" 0 "$gate_base" gate "$tmp/g5" --tier medium --stage6 complete --late complete

# Duplicate ledger/5.md sections are an error for the gate too.
cp -R "$B" "$tmp/g6"
printf '## app-F1\n- origin: pass1\n' >> "$tmp/g6/ledger/5.md"
run "gate, duplicate ledger/5.md section" 1 "" gate "$tmp/g6" --tier medium --stage6 complete --late complete
errmsg "gate, duplicate ledger/5.md section" "ledger: ledger/5.md:142: duplicate section for app-F1"
run "gate, missing inventory" 2 "" gate "$tmp/empty" --tier medium --stage6 failed --late failed
errmsg "gate, missing inventory" "ledger: cannot read $tmp/empty/ledger/inventory.txt"

# ---------------------------------------------------------------------------
# check --through 7.
run "check 7, base" 0 "" check "$B" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/h1"
mk7 "$tmp/h1" "app-P1 app-T1 X1" ""
cp "$B/late/adversary.md" "$tmp/h1/late/adversary.md"
want="ledger: ledger/7.md: no addition L1, which late/adversary.md raises
ledger: gate.md:10: line for unknown id L1
ledger: converged.md:25: C6 absorbs unknown id L1"
run "check 7, omitted L" 1 "$want" check "$tmp/h1" --through 7 --tier medium --stage6 complete --late complete

mkdir -p "$tmp/h2x/ledger" "$tmp/h2x/late"
cp -R "$B" "$tmp/h2"
mk7 "$tmp/h2x" "app-P1 app-T1" "L1"
cp "$tmp/h2x/late/adversary.md" "$tmp/h2/late/adversary.md"
run "check 7, verdict missing from the adversary file" 1 "ledger: ledger/7.md:11: verdict of X1 has no verdict block in late/adversary.md" check "$tmp/h2" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/h3"
cp "$tmp/h2x/ledger/7.md" "$tmp/h3/ledger/7.md"
want="ledger: ledger/7.md: no verdict section for X1, which late/adversary.md gives
ledger: ledger/7.md: no late verdict for X1, which late-ids lists
ledger: gate.md:9: 'X1: counts; late verdict', expected 'X1: provisional; no late verdict'
ledger: converged.md:21: C5 gate is counts, but no absorbed id counts"
run "check 7, verdict missing from ledger/7.md" 1 "$want" check "$tmp/h3" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/h4"
sed 's/^app-P1: counts; late verdict, stage 6 position$/app-P1: provisional; no late verdict/' "$B/gate.md" > "$tmp/h4/gate.md"
run "check 7, gate.md mismatch" 1 "ledger: gate.md:5: 'app-P1: provisional; no late verdict', expected 'app-P1: counts; late verdict, stage 6 position'" check "$tmp/h4" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/h5"
sed '/^app-T1:/d' "$B/gate.md" > "$tmp/h5/gate.md"
run "check 7, gate.md omits an id" 1 "ledger: gate.md: no line for app-T1" check "$tmp/h5" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/h6"
run "check 7, wrong tier makes gate.md stale" 1 "ledger: gate.md:5: 'app-P1: counts; late verdict, stage 6 position', expected 'app-P1: provisional; late addition at low tier'${nl}ledger: gate.md:6: 'app-T1: counts; late verdict, stage 6 acknowledged (low or note)', expected 'app-T1: provisional; late addition at low tier'${nl}ledger: gate.md:9: 'X1: counts; late verdict', expected 'X1: provisional; late addition at low tier'${nl}ledger: converged.md:13: C3 gate is counts, but no absorbed id counts${nl}ledger: converged.md:21: C5 gate is counts, but no absorbed id counts" check "$tmp/h6" --through 7 --tier low --stage6 complete --late complete

# converged.md: an id absorbed twice, an id never absorbed, a wrong gate, an unknown id.
cp -R "$B" "$tmp/k1"
sed 's/^- absorbs: app-P1, app-T1$/- absorbs: app-P1, app-T1, app-F4/' "$B/converged.md" > "$tmp/k1/converged.md"
run "check 7, id absorbed twice" 1 "ledger: converged.md: app-F4 is absorbed 2 times (C2, C3)" check "$tmp/k1" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/k2"
sed 's/^- absorbs: L1$/- absorbs:/' "$B/converged.md" > "$tmp/k2/converged.md"
run "check 7, id never absorbed" 1 "ledger: converged.md: L1 is in no - absorbs: list" check "$tmp/k2" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/k3"
sed 's/^- gate: provisional$/- gate: counts/' "$B/converged.md" > "$tmp/k3/converged.md"
want="ledger: converged.md:17: C4 gate is counts, but no absorbed id counts
ledger: converged.md:25: C6 gate is counts, but no absorbed id counts"
run "check 7, wrong converged gate" 1 "$want" check "$tmp/k3" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/k4"
awk '!d && $0 == "- gate: counts" { print "- gate: provisional"; d = 1; next } { print }' "$B/converged.md" > "$tmp/k4/converged.md"
run "check 7, counted item marked provisional" 1 "ledger: converged.md:3: C1 gate is provisional, but an absorbed id counts" check "$tmp/k4" --through 7 --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/k5"
sed 's/^- absorbs: X1$/- absorbs: X1, X9/' "$B/converged.md" > "$tmp/k5/converged.md"
run "check 7, unknown absorbed id" 1 "ledger: converged.md:21: C5 absorbs unknown id X9" check "$tmp/k5" --through 7 --tier medium --stage6 complete --late complete

# converged.md is required at stage 7.
cp -R "$B" "$tmp/k6"
rm "$tmp/k6/converged.md"
run "check 7, no converged.md" 2 "" check "$tmp/k6" --through 7 --tier medium --stage6 complete --late complete
errmsg "check 7, no converged.md" "ledger: cannot read $tmp/k6/converged.md"

# With the late adversary failed, its file is not read; gate.md follows the gate rules.
cp -R "$B" "$tmp/k7"
rm "$tmp/k7/late/adversary.md"
sed 's/^app-P1: .*$/app-P1: provisional; no late verdict/; s/^app-T1: .*$/app-T1: provisional; no late verdict/; s/^X1: .*$/X1: provisional; no late verdict/' "$B/gate.md" > "$tmp/k7/gate.md"
want="ledger: converged.md:13: C3 gate is counts, but no absorbed id counts
ledger: converged.md:21: C5 gate is counts, but no absorbed id counts"
run "check 7, late adversary failed" 1 "$want" check "$tmp/k7" --through 7 --tier medium --stage6 complete --late failed


# A failed record with no file is listed by kind and scope.
cp -R "$B" "$tmp/n1"
printf 'pass1 gone - m-a failed\n' >> "$tmp/n1/ledger/inventory.txt"
awk '{ a[NR] = $0 } END { for (i = 1; i < NR; i++) print a[i]; print "- pass1 gone: no file"; print a[NR] }' "$tmp/want5.txt" > "$tmp/want5n.txt"
runf "build5, failed record without a file" 0 "$tmp/want5n.txt" build5 "$tmp/n1"

cp -R "$B" "$tmp/n2"
printf 'pass2 ghost pass2/ghost.md m-b complete\npass1 odd pass1/odd.md\n' >> "$tmp/n2/ledger/inventory.txt"
run "inventory: unknown scope and a short record" 1 "" build5 "$tmp/n2"
errmsg "inventory: unknown scope and a short record" "ledger: ledger/inventory.txt:11: expected 5 fields, got 3
ledger: ledger/inventory.txt:10: pass2 record for scope ghost has no pass1 record
ledger: ledger/inventory.txt:10: pass2/ghost.md does not exist"

# CRLF in every file the check reads.
cp -R "$B" "$tmp/n3"
for f in ledger/5.md ledger/6.md ledger/7.md ledger/inventory.txt gate.md converged.md codex/response.md late/adversary.md pass1/app.md pass2/app.md; do
	crlf "$tmp/n3/$f"
done
run "check 7, CRLF input" 0 "" check "$tmp/n3" --through 7 --tier medium --stage6 complete --late complete
run "gate, CRLF input" 0 "$gate_base" gate "$tmp/n3" --tier medium --stage6 complete --late complete

# ---------------------------------------------------------------------------
# Review round 2.
cp -R "$B" "$tmp/r1"
sed 's/^- demonstrated: the guard uses a greater-than$/- demonstrated: altered/' "$B/ledger/5.md" > "$tmp/r1/ledger/5.md"
run "check 5, altered Original line" 1 "ledger: ledger/5.md differs from the build5 output at line 10" check "$tmp/r1" --through 5

cp -R "$B" "$tmp/r2"
sed 's/^medium, verified fact, downgraded$/high, verified fact, downgraded/' "$B/ledger/5.md" > "$tmp/r2/ledger/5.md"
run "check 5, altered State line" 1 "ledger: ledger/5.md differs from the build5 output at line 15" check "$tmp/r2" --through 5

cp -R "$B" "$tmp/r3"
printf 'pass1 zz pass1/app.pre-topup.md m-a complete\n' >> "$tmp/r3/ledger/inventory.txt"
run "inventory names a pre-top-up file" 1 "" build5 "$tmp/r3"
errmsg "inventory names a pre-top-up file" "ledger: ledger/inventory.txt:10: pass1/app.pre-topup.md is a pre-top-up copy and has no record"

cp -R "$B" "$tmp/r4"
sed 's/^- verdict: survives by cca:adversary (late, model m-c)$/- verdict: dropped by cca:adversary (late, model m-c)/' "$B/ledger/7.md" > "$tmp/r4/ledger/7.md"

cp -R "$B" "$tmp/r5"
sed 's/^medium, verified fact, downgraded$/medium verified fact downgraded/' "$B/ledger/5.md" > "$tmp/r5/ledger/5.md"
run "mandatory with a malformed state line" 1 "" mandatory "$tmp/r5"
errmsg "mandatory with a malformed state line" "ledger: ledger/5.md:15: malformed state line for app-F1"
run "seen with a malformed state line" 1 "" seen "$tmp/r5"
run "gate with a malformed state line" 1 "" gate "$tmp/r5" --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/r6"
awk '$0 == "### State after pass two" && !d { d = 1; getline; next } { print }' "$B/ledger/5.md" > "$tmp/r6/ledger/5.md"
run "mandatory with a section that has no state" 1 "" mandatory "$tmp/r6"
errmsg "mandatory with no state" "ledger: ledger/5.md: section for app-F1 has no '### State after pass two' line"

# live/findings.md: no fence handling, trailing blanks trimmed, "## id: title" rejected.
cp -R "$B" "$tmp/r7"
mkdir -p "$tmp/r7/live"
printf '## app-F2  \n```\nquery\n\n## X7 \t\n' > "$tmp/r7/live/findings.md"
run "mandatory, unbalanced fence in live findings" 0 "X7${nl}app-F1${nl}app-F2${nl}app-F3${nl}app-F4${nl}app-P1${nl}web-F1" mandatory "$tmp/r7"
printf '## app-F2: title\n' > "$tmp/r7/live/findings.md"
run "mandatory, live heading with a title" 1 "" mandatory "$tmp/r7"
errmsg "mandatory, live heading with a title" "ledger: live/findings.md:1: heading 'app-F2: title' must be '## <id>' alone"

cp -R "$B" "$tmp/r8"
sed 's/^- answer location: codex\/response.md, app-F1$/- answer location:/' "$B/ledger/6.md" > "$tmp/r8/ledger/6.md"
run "check 6, empty answer location" 1 "ledger: ledger/6.md:7: app-F1 has no nonempty - answer location: line" check "$tmp/r8" --through 6 --stage6 complete

cp -R "$B" "$tmp/r9"
sed 's/^## app-F1$/## app-F1  /' "$B/ledger/6.md" > "$tmp/r9/ledger/6.md"
run "check 6, trailing blanks on a heading" 0 "" check "$tmp/r9" --through 6 --stage6 complete

# A scope with dots and underscores.
D=$tmp/ds
mkdir -p "$D/pass1" "$D/pass2" "$D/ledger"
printf 'pass1 my_app.v2 pass1/my_app.v2.md m-a complete\npass2 my_app.v2 pass2/my_app.v2.md m-b complete\n' > "$D/ledger/inventory.txt"
printf '### my_app.v2-F1: Odd scope\n- severity: low\n- label: convention\n- evidence: e\nruns: none\nstatus: complete\n' > "$D/pass1/my_app.v2.md"
printf '### verdict on my_app.v2-F1: survives\n- severity: unchanged\n- label: unchanged\n- evidence: e2\n- reason: r\n\n## Verified OK challenged\nnone\n\n## Coverage gaps\nnone\nstatus: complete\n' > "$D/pass2/my_app.v2.md"
cat > "$tmp/wantds.txt" <<'EOF'
## my_app.v2-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/my_app.v2.md
### Original
### my_app.v2-F1: Odd scope
- severity: low
- label: convention
- evidence: e
### Pass-two verdicts
- survives by cca:adversary (model m-b) in pass2/my_app.v2.md: r; evidence: e2
### State after pass two
low, convention, survives

## Verified OK challenged: my_app.v2
none

## Coverage gaps: my_app.v2
none

EOF
runf "build5, scope with dots and underscores" 0 "$tmp/wantds.txt" build5 "$D"

# A medium P that is live-listed needs a position and a late verdict.
cp -R "$B" "$tmp/r10"
mkdir -p "$tmp/r10/live"
printf '## app-P1\n' > "$tmp/r10/live/findings.md"
mk6 "$tmp/r10" "app-F1 app-F3 app-F4 web-F1" "app-F2 app-T1 cfg-F1" "X1"
want="app-F1: counts; stage 5 verdict, stage 6 position
app-F2: counts; stage 5 verdict, stage 6 acknowledged (low or note)
app-F4: counts; stage 5 verdict, stage 6 position
app-F3: counts; stage 5 verdict, stage 6 position
app-P1: provisional; live result not yet reviewed
app-T1: counts; late verdict, stage 6 acknowledged (low or note)
web-F1: provisional; no stage 5 verdict
cfg-F1: provisional; no stage 5 verdict
X1: counts; late verdict
L1: provisional; late finding"
run "gate, live medium P without a position" 0 "$want" gate "$tmp/r10" --tier medium --stage6 complete --late complete
printf '## app-P1\n' > "$tmp/r10/live/findings.md"
mk6 "$tmp/r10" "app-F1 app-F3 app-F4 app-P1 web-F1" "app-F2 app-T1 cfg-F1" "X1"
run "gate, live medium P reviewed" 0 "$(printf '%s' "$gate_base" | sed 's/^app-P1: .*/app-P1: counts; live review completed/')" gate "$tmp/r10" --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/r11"
sed 's/^## Coverage gaps$/## Gaps/' "$B/pass2/app.md" > "$tmp/r11/pass2/app.md"
run "complete pass two without Coverage gaps" 1 "" build5 "$tmp/r11"
errmsg "complete pass two without Coverage gaps" "ledger: pass2/app.md: no '## Coverage gaps' section"

cp -R "$B" "$tmp/r12"
sed 's/^### cfg-F1: /### zzz-F1: /' "$B/pass1/cfg.md" > "$tmp/r12/pass1/cfg.md"
run "finding id outside its scope" 1 "" build5 "$tmp/r12"
errmsg "finding id outside its scope" "ledger: pass1/cfg.md:3: zzz-F1 does not start with its scope 'cfg-'"

cp -R "$B" "$tmp/r13"
rm "$tmp/r13/ledger/6.md"
run "check 6, stage 6 failed, no ledger/6.md" 0 "" check "$tmp/r13" --through 6 --stage6 failed

# Headings that look like findings or verdicts but are not exact are errors.
cp -R "$B" "$tmp/q1"
printf '### app-P2:Missing space\n- severity: low\n- label: convention
status: complete
' >> "$tmp/q1/pass2/app.md"
run "pass-two addition with no space after the colon" 1 "" build5 "$tmp/q1"
errmsg "no space after the colon" "ledger: pass2/app.md:46: malformed finding heading"

cp -R "$B" "$tmp/q2"
printf '### app-F5:\n- severity: low\n- label: convention
status: complete
' >> "$tmp/q2/pass1/app.md"
run "finding heading with an empty title" 1 "" build5 "$tmp/q2"
errmsg "empty title" "ledger: pass1/app.md:49: malformed finding heading"

cp -R "$B" "$tmp/q3"
printf '### verdict on app-F2:survives\n- severity: unchanged\n- label: unchanged\n- evidence: e
status: complete
' >> "$tmp/q3/pass2/app.md"
run "verdict heading with no space after the colon" 1 "" build5 "$tmp/q3"
errmsg "verdict heading with no space" "ledger: pass2/app.md:46: malformed verdict heading"

# Round 4: malformed input an op reads fails that op closed.
cp -R "$B" "$tmp/u1"
sed 's/^- verdict: survives by cca:adversary (late, model m-c)$/- verdict: pending by cca:adversary (late, model m-c)/' "$B/ledger/7.md" > "$tmp/u1/ledger/7.md"
run "gate, invalid late verdict word" 1 "" gate "$tmp/u1" --tier medium --stage6 complete --late complete
errmsg "gate, invalid late verdict word" "ledger: ledger/7.md:2: verdict of app-P1 must start with survives, downgraded, reworded, or dropped
ledger: ledger/7.md:7: verdict of app-T1 must start with survives, downgraded, reworded, or dropped
ledger: ledger/7.md:12: verdict of X1 must start with survives, downgraded, reworded, or dropped"

cp -R "$B" "$tmp/u2"
mk6 "$tmp/u2" "app-F1 app-F1 app-F3 app-F4 app-P1 web-F1" "app-F2 app-T1 cfg-F1" "X1"
run "seen, duplicate position section" 1 "" seen "$tmp/u2"
errmsg "seen, duplicate position section" "ledger: ledger/6.md:12: duplicate position section for app-F1"
run "gate, duplicate position section" 1 "" gate "$tmp/u2" --tier medium --stage6 complete --late complete

cp -R "$B" "$tmp/u3"
printf '```\nopen\n' >> "$tmp/u3/ledger/5.md"
run "mandatory, ledger/5.md ends inside a fence" 1 "" mandatory "$tmp/u3"
errmsg "mandatory, fence in ledger/5.md" "ledger: ledger/5.md: the file ends inside a code fence"

cp -R "$B" "$tmp/u4"
printf '```\nopen\n' >> "$tmp/u4/ledger/7.md"
run "gate, ledger/7.md ends inside a fence" 1 "" gate "$tmp/u4" --tier medium --stage6 complete --late complete
errmsg "gate, fence in ledger/7.md" "ledger: ledger/7.md: the file ends inside a code fence"

cp -R "$B" "$tmp/u5"
mk6 "$tmp/u5" "app-F1 app-F3 app-F4 app-P1 web-F1" "app-F2 app-T1 cfg-F1" "X1 X1"
run "gate, duplicate X addition" 1 "" gate "$tmp/u5" --tier medium --stage6 complete --late complete
errmsg "gate, duplicate X addition" "ledger: ledger/6.md:39: duplicate addition X1"

# Round 5: fenced lines in the codex response files never count.
cp -R "$B" "$tmp/v1"
printf '```\n### X99: Quoted example\n```\n' >> "$tmp/v1/codex/response.md"
run "check 6, fenced X heading is not required" 0 "" check "$tmp/v1" --through 6 --stage6 complete

cp -R "$B" "$tmp/v2"
mk6 "$tmp/v2" "app-F1 app-F2 app-F3 app-F4 app-P1 web-F1" "app-T1 cfg-F1" "X1"
printf '```\napp-F2: agree\n```\n' >> "$tmp/v2/codex/response.md"
run "check 6, fenced position line gives no provenance" 1 "ledger: ledger/6.md:12: no line starting 'app-F2:' in the codex response files" check "$tmp/v2" --through 6 --stage6 complete

cp -R "$B" "$tmp/v3"
mk6 "$tmp/v3" "app-F1 app-F2 app-F3 app-F4 app-P1 web-F1" "app-T1 cfg-F1" "X1"
printf '```\nunclosed\napp-F2: agree\n' >> "$tmp/v3/codex/response.md"
run "check 6, response ends inside a fence" 1 "ledger: ledger/6.md:12: no line starting 'app-F2:' in the codex response files" check "$tmp/v3" --through 6 --stage6 complete

# Round 6: findings in failed outputs are kept, malformed blocks there are counted.
FD=$tmp/fd
mkdir -p "$FD/pass1" "$FD/pass2" "$FD/ledger"
printf 'pass1 s pass1/s.md m-a complete\npass1 t pass1/t.md m-a failed\npass2 s pass2/s.md m-b failed\n' > "$FD/ledger/inventory.txt"
printf '### s-F1: One\n- severity: high\n- label: verified fact\n- evidence: e\nruns: none\nstatus: complete\n' > "$FD/pass1/s.md"
printf '### t-F1: Two\n- severity: low\n- label: convention\n- evidence: e\n\n### t-F2: Bad\n- label: convention\n- evidence: e\n' > "$FD/pass1/t.md"
printf '### verdict on s-F1: survives\n- severity: unchanged\n- label: unchanged\n- evidence: e\n- reason: r\n\n### s-P1: Added\n- severity: medium\n- label: verified fact\n- evidence: e\n\n### s-P2:Bad\n- severity: low\n- label: convention\n' > "$FD/pass2/s.md"
cat > "$tmp/wantfd.txt" <<'EOF'
## s-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/s.md
### Original
### s-F1: One
- severity: high
- label: verified fact
- evidence: e
### Pass-two verdicts
- none
### State after pass two
high, verified fact, no verdict: scope failed

## s-P1
- origin: pass2
- author: cca:adversary, model m-b, file pass2/s.md
### Original
### s-P1: Added
- severity: medium
- label: verified fact
- evidence: e
### Pass-two verdicts
- none
### State after pass two
medium, verified fact, no verdict: output failed

## t-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/t.md
### Original
### t-F1: Two
- severity: low
- label: convention
- evidence: e
### Pass-two verdicts
- none
### State after pass two
low, convention, no verdict: output failed

## Failed outputs
- pass1/t.md (1 blocks not parsed)
- pass2/s.md (1 blocks not parsed)

EOF
runf "build5, findings from failed files" 0 "$tmp/wantfd.txt" build5 "$FD"
cp "$tmp/wantfd.txt" "$FD/ledger/5.md"
printf '## Map corrections applied\n- none\n\n## Map corrections not applied\n- none\n' >> "$FD/ledger/5.md"
run "check 5, findings from failed files" 0 "" check "$FD" --through 5
run "mandatory, findings from failed files" 0 "s-F1${nl}s-P1" mandatory "$FD"
run "gate, finding from a failed file" 0 "s-F1: provisional; stage 6 failed
s-P1: provisional; stage 6 failed
t-F1: provisional; stage 6 failed" gate "$FD" --tier medium --stage6 failed --late failed

# The base run with its pass-two app file marked failed.
cp -R "$B" "$tmp/w1"
sed 's/^pass2 app pass2\/app.md m-b complete$/pass2 app pass2\/app.md m-b failed/' "$B/ledger/inventory.txt" > "$tmp/w1/ledger/inventory.txt"
sh "$ls" build5 "$tmp/w1" > "$tmp/w1.out" 2> "$tmp/err"
st=$?
[ "$st" = 0 ] || fail "build5, pass two failed: expected exit 0, got $st"
[ "$(grep -c 'no verdict: scope failed$' "$tmp/w1.out")" = 5 ] || fail "build5, pass two failed: expected 5 scope failed states"
[ "$(grep -c 'no verdict: output failed$' "$tmp/w1.out")" = 1 ] || fail "build5, pass two failed: expected 1 output failed state"
[ "$(grep -n '^medium, verified fact, no verdict: output failed$' "$tmp/w1.out" | cut -d: -f2-)" = "medium, verified fact, no verdict: output failed" ] || fail "build5, pass two failed: app-P1 state"
[ "$(grep -c '^## Verified OK challenged' "$tmp/w1.out")" = 0 ] || fail "build5, pass two failed: no challenged section expected"

# A duplicate merged item id.
cp -R "$B" "$tmp/w2"
sed 's/^## C2: Flag and retry text$/## C1: Flag and retry text/' "$B/converged.md" > "$tmp/w2/converged.md"
run "check 7, duplicate item id" 1 "ledger: converged.md:9: duplicate item id C1" check "$tmp/w2" --through 7 --tier medium --stage6 complete --late complete

# A failed file that ends inside a fence: the block that holds it is skipped and counted.
FE=$tmp/fe
mkdir -p "$FE/pass1" "$FE/pass2" "$FE/ledger"
printf 'pass1 s pass1/s.md m-a complete\npass2 s pass2/s.md m-b failed\n' > "$FE/ledger/inventory.txt"
printf '### s-F1: One\n- severity: high\n- label: verified fact\n- evidence: e\nruns: none\nstatus: complete\n' > "$FE/pass1/s.md"
printf '### s-P1: Good\n- severity: low\n- label: convention\n- evidence: e\n\n### s-P2: Open\n- severity: low\n- label: convention\n- evidence: see\n```\nnever closed\n' > "$FE/pass2/s.md"
cat > "$tmp/wantfe.txt" <<'EOF'
## s-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/s.md
### Original
### s-F1: One
- severity: high
- label: verified fact
- evidence: e
### Pass-two verdicts
- none
### State after pass two
high, verified fact, no verdict: scope failed

## s-P1
- origin: pass2
- author: cca:adversary, model m-b, file pass2/s.md
### Original
### s-P1: Good
- severity: low
- label: convention
- evidence: e
### Pass-two verdicts
- none
### State after pass two
low, convention, no verdict: output failed

## Failed outputs
- pass2/s.md (1 blocks not parsed)

EOF
runf "build5, failed file ends inside a fence" 0 "$tmp/wantfe.txt" build5 "$FE"
cp "$tmp/wantfe.txt" "$FE/ledger/5.md"
printf '## Map corrections applied\n- none\n\n## Map corrections not applied\n- none\n' >> "$FE/ledger/5.md"
run "check 5, failed file ends inside a fence" 0 "" check "$FE" --through 5

# missing: mandatory ids with no provenance line in the response files.
run "missing, base" 0 "" missing "$B"
cp -R "$B" "$tmp/x1"
grep -v '^web-F1: confirmed blocker$' "$B/codex/response.md" > "$tmp/x1/codex/response.md"
run "missing, one answer removed" 0 "web-F1" missing "$tmp/x1"
cp -R "$B" "$tmp/x2"
grep -v '^web-F1: confirmed blocker$' "$B/codex/response.md" > "$tmp/x2/codex/response.md"
printf '```\nweb-F1: quoted\n```\n' >> "$tmp/x2/codex/response.md"
run "missing, position only inside a fence" 0 "web-F1" missing "$tmp/x2"
cp -R "$B" "$tmp/x3"
rm "$tmp/x3/codex/response.md"
run "missing, no response file" 0 "app-F1${nl}app-F3${nl}app-F4${nl}app-P1${nl}web-F1" missing "$tmp/x3"
run "missing, malformed ledger/5.md" 1 "" missing "$tmp/r5"

# Segment boundaries in a response file reset the fence state.
cp -R "$B" "$tmp/y1"
{ grep -v '^web-F1: confirmed blocker$' "$B/codex/response.md"; printf '```\nopen\n--- follow-up, thread t9 ---\nweb-F1: confirmed blocker\n'; } > "$tmp/y1/codex/response.md"
run "missing, follow-up after an open fence" 0 "" missing "$tmp/y1"
run "check 6, follow-up after an open fence" 0 "" check "$tmp/y1" --through 6 --stage6 complete

cp -R "$B" "$tmp/y2"
{ grep -v '^web-F1: confirmed blocker$' "$B/codex/response.md"; printf -- '--- follow-up, thread t9 ---\n```\nopen\nweb-F1: confirmed blocker\n'; } > "$tmp/y2/codex/response.md"
run "missing, open fence inside the follow-up" 0 "web-F1" missing "$tmp/y2"

cp -R "$B" "$tmp/y3"
{ grep -v '^web-F1: confirmed blocker$' "$B/codex/response.md"; printf '```\nopen\n--- batch 2 ---\nweb-F1: confirmed blocker\n'; } > "$tmp/y3/codex/response.md"
run "missing, batch boundary after an open fence" 0 "" missing "$tmp/y3"

# ---------------------------------------------------------------------------
# 0.5.1: completion from the file, mis-cased ids, block ends, list numbers, map
# headings, late-ids.
cp -R "$B" "$tmp/z1"
grep -v '^status: complete$' "$B/pass1/web.md" > "$tmp/z1/pass1/web.md"
run "build5, complete record whose file lacks status: complete" 1 "" build5 "$tmp/z1"
errmsg "complete record without status" "ledger: pass1/web.md: the inventory says complete, but the file does not end with status: complete"
run "check 5, complete record whose file lacks status: complete" 1 "ledger: pass1/web.md: the inventory says complete, but the file does not end with status: complete" check "$tmp/z1" --through 5
cp -R "$B" "$tmp/z2"
printf '\n\n' >> "$tmp/z2/pass1/web.md"
runf "build5, trailing blank lines after status: complete" 0 "$tmp/want5.txt" build5 "$tmp/z2"

cp -R "$B" "$tmp/z3"
printf '### app-f9: Lower case id\n- severity: low\n- label: convention\nstatus: complete\n' >> "$tmp/z3/pass1/app.md"
run "mis-cased finding id in a pass file" 1 "" build5 "$tmp/z3"
errmsg "mis-cased finding id" "ledger: pass1/app.md:49: malformed finding heading"
cp -R "$B" "$tmp/z4"
mk6 "$tmp/z4" "app-F1 app-F3 app-F4 app-P1 web-F1" "app-F2 app-T1 cfg-F1" "x1"
run "gate, lower case X addition in ledger/6.md" 1 "" gate "$tmp/z4" --tier medium --stage6 complete --late complete
errmsg "lower case X addition" "ledger: ledger/6.md:32: malformed addition heading"
cp -R "$B" "$tmp/z5"
mk7 "$tmp/z5" "app-P1 app-T1 X1" "l1"
run "gate, lower case L addition in ledger/7.md" 1 "" gate "$tmp/z5" --tier medium --stage6 complete --late complete
errmsg "lower case L addition" "ledger: ledger/7.md:16: malformed addition heading"
cp -R "$B" "$tmp/z6"
printf '### x2: Another\nlow.\n' >> "$tmp/z6/codex/response.md"
run "check 6, lower case X heading in the response" 1 "ledger: codex/response.md:12: heading names an X addition but does not read #+ X<n>:" check "$tmp/z6" --through 6 --stage6 complete
cp -R "$B" "$tmp/z7"
printf '### l2: Another late\n- severity: low\n' >> "$tmp/z7/late/adversary.md"
run "check 7, lower case L heading in the late file" 1 "ledger: late/adversary.md:30: malformed finding heading" check "$tmp/z7" --through 7 --tier medium --stage6 complete --late complete

# Only the exact lines end a block; "status: ..." and "runs: ..." inside a block are text.
BE=$tmp/be
mkdir -p "$BE/pass1" "$BE/ledger"
printf 'pass1 s pass1/s.md m-a complete\npass2 s - - not-run\n' > "$BE/ledger/inventory.txt"
printf '### s-F1: One\n- severity: high\n- label: verified fact\n- evidence: e\nstatus: pending review of the claim\nruns: 3 commands logged\n- demonstrated: more\nrequired status: ok\nconsumed: none\nstatus: complete\n' > "$BE/pass1/s.md"
cat > "$tmp/wantbe.txt" <<'EOF'
## s-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/s.md
### Original
### s-F1: One
- severity: high
- label: verified fact
- evidence: e
status: pending review of the claim
runs: 3 commands logged
- demonstrated: more
required status: ok
### Pass-two verdicts
- none
### State after pass two
high, verified fact, no verdict: not run, budget expired

EOF
runf "build5, block text that starts like an end line" 0 "$tmp/wantbe.txt" build5 "$BE"

# A leading list number does not hide a position.
cp -R "$B" "$tmp/z8"
sed 's/^web-F1: confirmed blocker$/1. web-F1: confirmed blocker/; s/^\*\*app-F4\*\*: reword accepted$/2) **app-F4**: reword accepted/' "$B/codex/response.md" > "$tmp/z8/codex/response.md"
run "missing, numbered answers" 0 "" missing "$tmp/z8"
run "check 6, numbered answers" 0 "" check "$tmp/z8" --through 6 --stage6 complete

# check 5 needs both map headings, once each, in order.
cp -R "$B" "$tmp/z9"
cp "$tmp/want5.txt" "$tmp/z9/ledger/5.md"
want="ledger: ledger/5.md: no '## Map corrections applied' heading
ledger: ledger/5.md: no '## Map corrections not applied' heading"
run "check 5, no map headings" 1 "$want" check "$tmp/z9" --through 5
cp "$tmp/want5.txt" "$tmp/z9/ledger/5.md"
printf '## Map corrections applied\n- none\n' >> "$tmp/z9/ledger/5.md"
run "check 5, no not-applied heading" 1 "ledger: ledger/5.md: no '## Map corrections not applied' heading" check "$tmp/z9" --through 5
cp "$tmp/want5.txt" "$tmp/z9/ledger/5.md"
printf '## Map corrections applied\n- none\n\n## Map corrections applied\n- none\n\n## Map corrections not applied\n- none\n' >> "$tmp/z9/ledger/5.md"
run "check 5, heading twice" 1 "ledger: ledger/5.md: '## Map corrections applied' appears 2 times" check "$tmp/z9" --through 5
cp "$tmp/want5.txt" "$tmp/z9/ledger/5.md"
printf '## Map corrections not applied\n- none\n\n## Map corrections applied\n- none\n' >> "$tmp/z9/ledger/5.md"
run "check 5, headings out of order" 1 "ledger: ledger/5.md: '## Map corrections not applied' comes before '## Map corrections applied'${nl}ledger: ledger/5.md differs from the build5 output at line 136" check "$tmp/z9" --through 5

# late-ids.
run "late-ids, medium" 0 "X1${nl}app-P1${nl}app-T1" late-ids "$B" --tier medium --stage6 complete
run "late-ids, high" 0 "X1${nl}app-P1${nl}app-T1" late-ids "$B" --tier high --stage6 complete
run "late-ids, low" 0 "" late-ids "$B" --tier low --stage6 complete
cp -R "$B" "$tmp/z10"
sed '13s/.*/- position: restore requested for app-F3/' "$B/ledger/6.md" > "$tmp/z10/ledger/6.md"
run "late-ids, restore requested" 0 "X1${nl}app-F3${nl}app-P1${nl}app-T1" late-ids "$tmp/z10" --tier medium --stage6 complete
run "late-ids, restore requested at low" 0 "" late-ids "$tmp/z10" --tier low --stage6 complete
mkdir -p "$tmp/z10/live"
printf '## app-F2\n' > "$tmp/z10/live/findings.md"
run "late-ids, live id at low" 0 "app-F2" late-ids "$tmp/z10" --tier low --stage6 complete
run "late-ids, live id at medium" 0 "X1${nl}app-F2${nl}app-F3${nl}app-P1${nl}app-T1" late-ids "$tmp/z10" --tier medium --stage6 complete
run "late-ids without --tier" 2 "" late-ids "$B"
run "late-ids without --stage6" 2 "" late-ids "$B" --tier low
run "late-ids with --late" 2 "" late-ids "$B" --tier low --stage6 complete --late complete

cp -R "$B" "$tmp/z11"
mk7 "$tmp/z11" "app-P1 X1" "L1"
want="ledger: ledger/7.md: no late verdict for app-T1, which late-ids lists
ledger: gate.md:6: 'app-T1: counts; late verdict, stage 6 acknowledged (low or note)', expected 'app-T1: provisional; no late verdict'"
run "check 7, late-ids id without a late verdict" 1 "$want" check "$tmp/z11" --through 7 --tier medium --stage6 complete --late complete

# Review round 1 of 0.5.1.
cp -R "$B" "$tmp/aa1"
rm "$tmp/aa1/ledger/6.md"
run "late-ids, stage 6 complete, no ledger/6.md" 2 "" late-ids "$tmp/aa1" --tier medium --stage6 complete
errmsg "late-ids, no ledger/6.md" "ledger: cannot read $tmp/aa1/ledger/6.md"
run "late-ids, stage 6 failed, no ledger/6.md" 0 "app-P1${nl}app-T1" late-ids "$tmp/aa1" --tier medium --stage6 failed
run "late-ids, no ledger/5.md" 2 "" late-ids "$tmp/empty" --tier low --stage6 failed
errmsg "late-ids, no ledger/5.md (failed)" "ledger: cannot read $tmp/empty/ledger/5.md"
run "late-ids, stage 6 failed ignores restore requests" 0 "X1${nl}app-F2${nl}app-P1${nl}app-T1" late-ids "$tmp/z10" --tier medium --stage6 failed

cp -R "$B" "$tmp/aa2"
{ grep -v '^status: complete$' "$B/pass1/web.md"; printf 'status: complete \t\n'; } > "$tmp/aa2/pass1/web.md"
runf "build5, trailing blanks on the final status line" 0 "$tmp/want5.txt" build5 "$tmp/aa2"

# A heading that only resembles an id is not an error.
cp -R "$B" "$tmp/aa3"
printf '### api-v2: notes\nfree text\nstatus: complete\n' >> "$tmp/aa3/pass1/cfg.md"
runf "build5, heading that resembles an id" 0 "$tmp/want5.txt" build5 "$tmp/aa3"

# ---------------------------------------------------------------------------
# Outward trace sections (#17): a pass-one `## Outward trace` and a pass-two
# `## Outward trace challenged` are read by no op. The files below carry them, with a
# fence that holds finding and section headings, and the ops give what they would give
# without the sections.
OT=$tmp/ot
mkdir -p "$OT/pass1" "$OT/pass2" "$OT/ledger"
printf 'pass1 app pass1/app.md m-a complete\npass2 app pass2/app.md m-b complete\n' > "$OT/ledger/inventory.txt"
cat > "$OT/pass1/app.md" <<'EOF'
# Pass one: app

### app-F1: Run drops the failure branch
- severity: high
- question: Q1
- label: verified fact
- evidence: app@abc:src/a.sh:4 `run || true`
- demonstrated: the failure status is discarded

### app-F2: Helper has no caller
- severity: low
- question: Q2
- label: convention
- evidence: search git grep helper, no result
- demonstrated: nothing reads it

## Verified OK
- app-OK1: guard checked

## Outward trace
- app-OT1: app:src/a.sh:run (app@abc:src/a.sh:4); siblings: app:src/b.sh:helper (app@abc:src/b.sh:12); callees: none; consumers: web:src/w.sh:call (web@abc:src/w.sh:7); result: finding app-F1
- app-OT2: app:src/a.sh:parse (app@abc:src/a.sh:20); siblings: none; callees: app:src/a.sh:trim (app@abc:src/a.sh:30) fails closed;
  consumers: none; result: sound, evidence: app@abc:src/a.sh:21 returns on an empty input
- app-OT3: app:src/c.sh:late (app@abc:src/c.sh:30); siblings: none; callees: none; consumers: none; result: incomplete: the caller lives in a repo the brief does not map
- not traced: app:src/d.sh:extra (src/d.sh:3), app:src/e.sh:more (src/e.sh:9) (cap reached)

Entry shape, as written in the brief:
```text
### app-F9: example
- severity: high
## Coverage gaps
- outward trace: app:src/x.sh:y not traced
```

## Claims
- claim 1: true

## Decisions
none
runs: none
consumed: none
status: complete
EOF
cat > "$OT/pass2/app.md" <<'EOF'
# Pass two: app

### verdict on app-F1: downgraded
- severity: high -> medium
- label: unchanged
- evidence: app@abc:src/a.sh:6 tests the status
- reason: a later line checks the status

### verdict on app-F2: survives
- severity: unchanged
- label: unchanged
- evidence: git grep helper finds no caller
- reason: stands

## Verified OK challenged
- app-OK1: held

## Outward trace challenged
- app-OT1: upheld; evidence: app@abc:src/a.sh:4 discards the status
- app-OT2: broken, finding app-P1; evidence: app@abc:src/b.sh:9 lacks the check
Example of a gap line:
```text
### app-P9: example
## Coverage gaps
- outward trace: app:src/x.sh:y not traced
```

### app-P1: Sibling lacks the check
- severity: medium
- question: Q1
- label: verified fact
- origin: pass2
- evidence: app@abc:src/b.sh:9
- demonstrated: the same input reaches it

## Coverage gaps
- outward trace: app:src/b.sh:helper not traced
- outward trace: app:src/d.sh:extra (src/d.sh:3) not traced
runs: none
consumed: none
status: complete
EOF
cat > "$tmp/wantot.txt" <<'EOF'
## app-F1
- origin: pass1
- author: cca:auditor, model m-a, file pass1/app.md
### Original
### app-F1: Run drops the failure branch
- severity: high
- question: Q1
- label: verified fact
- evidence: app@abc:src/a.sh:4 `run || true`
- demonstrated: the failure status is discarded
### Pass-two verdicts
- downgraded by cca:adversary (model m-b) in pass2/app.md: a later line checks the status; evidence: app@abc:src/a.sh:6 tests the status
### State after pass two
medium, verified fact, downgraded

## app-F2
- origin: pass1
- author: cca:auditor, model m-a, file pass1/app.md
### Original
### app-F2: Helper has no caller
- severity: low
- question: Q2
- label: convention
- evidence: search git grep helper, no result
- demonstrated: nothing reads it
### Pass-two verdicts
- survives by cca:adversary (model m-b) in pass2/app.md: stands; evidence: git grep helper finds no caller
### State after pass two
low, convention, survives

## app-P1
- origin: pass2
- author: cca:adversary, model m-b, file pass2/app.md
### Original
### app-P1: Sibling lacks the check
- severity: medium
- question: Q1
- label: verified fact
- origin: pass2
- evidence: app@abc:src/b.sh:9
- demonstrated: the same input reaches it
### Pass-two verdicts
- none
### State after pass two
medium, verified fact, no verdict: late addition

## Verified OK challenged: app
- app-OK1: held

## Coverage gaps: app
- outward trace: app:src/b.sh:helper not traced
- outward trace: app:src/d.sh:extra (src/d.sh:3) not traced

EOF
runf "build5, outward trace sections" 0 "$tmp/wantot.txt" build5 "$OT"
cp "$tmp/wantot.txt" "$OT/ledger/5.md"
printf '## Map corrections applied\n- none\n\n## Map corrections not applied\n- none\n' >> "$OT/ledger/5.md"
run "check 5, outward trace sections" 0 "" check "$OT" --through 5
run "mandatory, outward trace sections" 0 "app-F1${nl}app-P1" mandatory "$OT"
want="app-F1: provisional; stage 6 failed
app-F2: provisional; stage 6 failed
app-P1: provisional; stage 6 failed"
run "gate, outward trace sections" 0 "$want" gate "$OT" --tier medium --stage6 failed --late not-run

# CRLF input gives the same output.
cp -R "$OT" "$tmp/ot-crlf"
for f in ledger/inventory.txt ledger/5.md pass1/app.md pass2/app.md; do
	crlf "$tmp/ot-crlf/$f"
done
runf "build5, outward trace sections, CRLF input" 0 "$tmp/wantot.txt" build5 "$tmp/ot-crlf"
run "check 5, outward trace sections, CRLF input" 0 "" check "$tmp/ot-crlf" --through 5

# The section right after a finding block (no Verified OK between them) reads the same.
cp -R "$OT" "$tmp/ot-adj"
awk '$0 == "## Verified OK" { skip = 1 } $0 == "## Outward trace" { skip = 0 } !skip { print }' "$OT/pass1/app.md" > "$tmp/ot-adj/pass1/app.md"
[ "$(grep -c '^## Verified OK$' "$tmp/ot-adj/pass1/app.md")" = 0 ] || fail "outward trace test setup: Verified OK was not removed"
runf "build5, outward trace right after a finding block" 0 "$tmp/wantot.txt" build5 "$tmp/ot-adj"

# A fence in either section that is never closed is the usual fence error.
cp -R "$OT" "$tmp/ot-u1"
awk '$0 == "```" && !d { d = 1; next } { print }' "$OT/pass1/app.md" > "$tmp/ot-u1/pass1/app.md"
run "unclosed fence in the outward trace section" 1 "" build5 "$tmp/ot-u1"
errmsg "unclosed fence in the outward trace section" "ledger: pass1/app.md: the file ends inside a code fence"
run "check 5, unclosed fence in the outward trace section" 1 "ledger: pass1/app.md: the file ends inside a code fence" check "$tmp/ot-u1" --through 5

cp -R "$OT" "$tmp/ot-u2"
awk '$0 == "```" && !d { d = 1; next } { print }' "$OT/pass2/app.md" > "$tmp/ot-u2/pass2/app.md"
run "unclosed fence in the outward trace challenged section" 1 "" build5 "$tmp/ot-u2"
errmsg "unclosed fence in the outward trace challenged section" "ledger: pass2/app.md: the file ends inside a code fence
ledger: pass2/app.md: no '## Coverage gaps' section"

# ---------------------------------------------------------------------------
# Usage errors and unreadable input: exit 2, nothing on stdout.
usage_msg="usage: ledger.sh build5|mandatory|seen|missing <run dir>
       ledger.sh late-ids <run dir> --tier low|medium|high --stage6 complete|failed
       ledger.sh gate <run dir> --tier low|medium|high --stage6 complete|failed --late complete|failed|not-run
       ledger.sh check <run dir> --through 5|6|7 [--tier ..] [--stage6 ..] [--late ..]"
run "no arguments" 2 ""
errmsg "no arguments" "$usage_msg"
run "unknown op" 2 "" frobnicate "$B"
errmsg "unknown op" "$usage_msg"
run "build5 with a flag" 2 "" build5 "$B" --tier low
errmsg "build5 with a flag" "$usage_msg"
run "check without --through" 2 "" check "$B"
errmsg "check without --through" "$usage_msg"
run "check 6 without --stage6" 2 "" check "$B" --through 6
errmsg "check 6 without --stage6" "$usage_msg"
run "check 7 without --late" 2 "" check "$B" --through 7 --stage6 complete --tier low
errmsg "check 7 without --late" "$usage_msg"
run "bad flag value" 2 "" check "$B" --through 9
errmsg "bad flag value" "$usage_msg"
run "gate without flags" 2 "" gate "$B"
errmsg "gate without flags" "$usage_msg"
run "missing run dir" 2 "" build5 "$tmp/nodir"
errmsg "missing run dir" "ledger: cannot read directory $tmp/nodir"
run "missing inventory" 2 "" build5 "$tmp/empty"
errmsg "missing inventory" "ledger: cannot read $tmp/empty/ledger/inventory.txt"
run "mandatory without ledger/5.md" 2 "" mandatory "$tmp/empty"
errmsg "mandatory without ledger/5.md" "ledger: cannot read $tmp/empty/ledger/5.md"

# The ops never change a run directory.
before=$(cd "$B" && find . -type f | sort | xargs cat | cksum)
sh "$ls" build5 "$B" > /dev/null
sh "$ls" check "$B" --through 6 --stage6 complete > /dev/null
after=$(cd "$B" && find . -type f | sort | xargs cat | cksum)
[ "$before" = "$after" ] || fail "run directory files changed"

if [ "$fails" -gt 0 ]; then
	exit 1
fi
echo "ledger test: ok"
