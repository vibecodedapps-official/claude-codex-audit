#!/bin/sh
# ledger.sh: build and check the mechanical parts of the stage 5 to 7 ledger.
#
# Usage:
#   sh ledger.sh build5    <run dir>
#   sh ledger.sh mandatory <run dir>
#   sh ledger.sh seen      <run dir>
#   sh ledger.sh missing   <run dir>
#   sh ledger.sh late-ids  <run dir> --tier low|medium|high --stage6 complete|failed
#   sh ledger.sh late-check <run dir> --tier low|medium|high --stage6 complete|failed
#   sh ledger.sh gate      <run dir> --tier low|medium|high --stage6 complete|failed
#                                    --late complete|failed|not-run
#   sh ledger.sh check     <run dir> --through 5|6|7 [--tier ..] [--stage6 ..] [--late ..]
#
# All paths are relative to <run dir>. `check --through 6` needs --stage6; `--through 7`
# needs all three flags; `late-ids` and `late-check` need --tier and --stage6. No other
# op takes a flag.
#
# Ops (the stage prompts redirect stdout to the file they write):
#   build5     the finding sections of ledger/5.md, in the shape of stages/5-pass-two.md,
#              step 6: per scope in inventory order, the pass-one findings (barrier
#              top-up findings included, in file order), then the pass-two additions,
#              then the top-up findings. `### Original` is the source block, CR
#              stripped, trailing blank lines removed. The verdict line and the state
#              come from the scope's complete pass-two file; a finding with no verdict
#              gets `no verdict: late addition` (P, T), `no verdict: scope failed`,
#              `no verdict: not run, budget expired`, or, for a finding read from a
#              failed file, `no verdict: output failed`. Then, per scope with a complete
#              pass two, `## Verified OK challenged: <scope>` and
#              `## Coverage gaps: <scope>`, cut from the pass-two file, and, when a
#              record is failed, `## Failed outputs` with one line per failed file:
#              `- <path>`, `- <path> (<n> blocks not parsed)` when n > 0 blocks of the
#              file were skipped, or `- <kind> <scope>: no file` when the record has no
#              path. A failed file that exists still gives every well-formed finding
#              block (a verdict block in it is never credited); a malformed block in it
#              (or one that holds a fence the file never closes) is skipped and
#              counted, not an error.
#              Every section ends with a blank line. The orchestrator appends the two
#              map-correction sections itself.
#   mandatory  one id per line, sorted, unique: every ledger/5.md id whose state
#              severity is blocker, high, or medium; every id whose state is downgraded
#              or dropped; every id that live/findings.md lists as a `## <id>` heading.
#   seen       `- <id>` per ledger/5.md id that is not mandatory and has no `## <id>`
#              section in ledger/6.md, in ledger/5.md order.
#   gate       the lines of gate.md, one per id of the universe: the ledger/5.md ids in
#              ledger order, the `### X<n>:` ids of ledger/6.md, the `### L<n>:` ids of
#              ledger/7.md, then the carried ids. A carried id is a file
#              live/carried/<id>.md whose id live/findings.md lists; any other file is
#              not in the universe. Each line is `<id>: <reason>`, with a reason below.
#   missing    the mandatory ids (as `mandatory`) that have no provenance line in
#              codex/response.md or a codex/response-<k>.md, one per line, sorted. The
#              provenance and fence rules are those of `check --through 6`. It reads no
#              ledger/6.md. No response file at all makes every mandatory id missing.
#              In a response file, a line that is exactly `--- follow-up, thread <id> ---`
#              or `--- batch <k> ---` closes any open fence and is never a position, so
#              an answer that ends inside a fence does not hide the segment after it.
#   late-ids   one id per line, sorted, unique: the ids the late adversary must challenge.
#              At medium and high: every ledger/5.md id with origin pass2 or topup, every
#              `### X<n>:` addition of ledger/6.md, and, with --stage6 complete, every
#              ledger/6.md position section whose `- position:` starts with `restore
#              requested` in any letter case. At every tier: every `## <id>` of
#              live/findings.md. ledger/6.md is read as `gate` reads it: required with
#              --stage6 complete, optional with failed (an absent file adds nothing).
#              With failed, ledger/6.md may be partial: a file that ends inside a fence, a
#              malformed addition heading, and the `### X<n>:` block that holds the open
#              fence are left out without an error, in late-ids and gate, and `check`
#              still reports them. With complete they are errors of every op that reads it.
#   late-check print one `ledger: <problem>` line per problem in late/adversary.md,
#              nothing when none, as `check` does. It reads the file as `check --through 7
#              --late complete` does (the rules of Parsing below; a last nonblank line
#              other than `status: complete`; an end inside a fence; an `L<n>` addition
#              that reuses a carried id) and also requires a `### verdict on <id>:` block
#              for every id `late-ids` lists and none for an id it does not list. A
#              missing file is a problem, not a usage error.
#   check      print one `ledger: <problem>` line per problem, nothing when none:
#              --through 5   reconcile the inventory with the files, then require the
#                            part of ledger/5.md before its first `## Map corrections
#                            applied` line (trailing blank lines ignored) to equal the
#                            build5 output, and name each missing or unknown id. The
#                            file must also hold `## Map corrections applied` and then
#                            `## Map corrections not applied`, each once.
#              --through 6   also, for ledger/6.md: every `## <id>` position holds a
#                            nonempty `- position:`, `- evidence:`, and `- answer
#                            location:`, appears once, names a known id, and has a line
#                            starting `<id>:` in codex/response.md or a
#                            codex/response-<k>.md (leading spaces, then one list number
#                            `<digits>.` or `<digits>)`, then `-`, `*`, `#`, and
#                            backticks stripped, then optional `*` or backticks before
#                            the colon; lines inside ``` fences never count, and a response
#                            file that ends inside a fence is not an error, since the
#                            answer is not ours to reject: its later lines just give no
#                            provenance; a heading `#+ x<n>:` that is not `#+ X<n>:` is a
#                            problem); the `### X<n>:` additions equal the `#+ X<n>:`
#                            headings of those files and never reuse a carried id; and,
#                            when --stage6 is complete, every mandatory id has a
#                            position and `## Seen, no position` lists exactly the
#                            ledger/5.md ids that are neither mandatory nor positioned;
#                            a position whose first word is `restore` (any letter case)
#                            but which does not start with `restore requested` is a
#                            problem, since only that phrase asks for a late verdict.
#              --through 7   also: when --late is complete, late/adversary.md ends, at
#                            its last nonblank line, with `status: complete`, the
#                            `### L<n>:` additions and the verdicts of ledger/7.md equal
#                            those of late/adversary.md and no L reuses a carried id;
#                            gate.md has one line per universe id and equals the gate
#                            output; the verdict words agree; and in converged.md (required)
#                            every universe id sits in exactly one `- absorbs:` list and
#                            each item's `- gate:` is `counts` exactly when an absorbed
#                            id counts; a `## C<n>:` item id used twice is a problem; and,
#                            when --late is complete, every id `late-ids` lists has a
#                            `## <id>` section with a `- verdict:` in ledger/7.md.
#
# Gate reasons. A line is `<id>: counts; <reason>` or `<id>: provisional; <reason>`:
#   counts; stage 5 verdict, stage 6 position
#   counts; stage 5 verdict, stage 6 acknowledged (low or note)
#   counts; late verdict, stage 6 position
#   counts; late verdict, stage 6 acknowledged (low or note)
#   counts; late verdict                              (X)
#   counts; live review completed                     (a live-listed id, and a carried L)
#   provisional; live result not yet reviewed
#   provisional; stage 6 failed
#   provisional; no stage 5 verdict
#   provisional; medium or above without a stage 6 position
#   provisional; late addition at low tier
#   provisional; no late verdict
#   provisional; late finding                         (a new L)
# A pass-one id counts with a stage 5 verdict from a complete pass-two file, stage 6
# complete, and a stage 6 position when its state severity is medium or above. A P or T
# counts with stage 6 complete, a late verdict (only with --late complete), and the same
# position rule; at low tier a P, T, or X counts only through the live rule. An X counts
# with a late verdict. A new L never counts. A live-listed id also needs stage 6
# complete with a position and a late verdict ("live review completed"), added to its
# own row. The reason says "position" when a position exists, else "acknowledged". When
# several reasons apply, the first of: live, stage 6 failed, low tier, no stage 5 or
# late verdict, medium without position.
#
# Inventory, ledger/inventory.txt, one record per line, five fields separated by blanks,
# blank lines ignored, paths relative to the run directory without blanks:
#   pass1 <scope> <path> <requested model> complete|failed
#   pass2 <scope> <path or -> <requested model or -> complete|failed|not-run
#   topup <scope> <path> <requested model> complete|failed
# Every .md file under pass1/ and pass2/ except *.pre-topup.md has exactly one record,
# every record's file exists, each scope has one pass1 record, at most one pass2 and one
# topup record, and every complete pass1 scope has a pass2 record. Verdicts come only
# from complete pass-two files; findings come from complete files (malformed blocks are
# errors) and from failed files (malformed blocks are skipped and counted).
# A complete record's file must also end, at its last nonblank line, with exactly
# `status: complete`; the inventory alone does not make a file complete.
#
# Parsing (skills/cca/common.md, output contract). A finding block starts at
# `### <id>: <title>`, a verdict block at `### verdict on <id>: <verdict>`. A block ends
# at the next line starting `## ` or `### `, or at a line that is exactly `runs:`,
# `runs: none`, `consumed:`, `consumed: none`, `opened:`, `opened: none`, or `status:
# complete` (trailing blanks ignored). Any other line that starts with those words is
# body text. Lines between ``` lines never start or end a block, and a file that
# ends inside a fence is an error. A `### ` line whose first token (cut at a colon) looks
# like an id in any letter case but is not exactly `### <id>: <title>` with a title is a
# malformed heading, never skipped; in a pass file only the `<scope>-F|P|T<n>` shape
# counts in any letter case, since X and L ids never belong there, so `### x86: notes`
# is text. Ids are `<scope>-F|P|T<n>`, `X<n>`, `L<n>`. A finding
# block needs exactly one `- severity:` and one `- label:` line with an allowed value; a
# verdict block needs a verdict word, one `- severity:` (`<old> -> <new>` or
# `unchanged`), one `- label:`, and a nonempty `- evidence:`. A duplicate id, a second
# verdict for one id, a verdict for an id that is not a pass-one finding of its scope, a
# pass-one finding without a verdict in a complete pass-two file, and a malformed block
# are errors in every op.
#
# Exit codes: 0 ok. 1 problems: check and late-check print one `ledger: <problem>` line
# each on stdout; the other ops print them on stderr and nothing on stdout. 2 on a usage
# error or an unreadable required file, one line starting `ledger: ` on stderr (the
# inventory; ledger/5.md; ledger/6.md when stage 6 is complete; ledger/7.md and
# late/adversary.md when --late is complete; codex/response.md and gate.md for check at
# the stage that reads them). late-check reads late/adversary.md without needing it.
#
# Still model-judged: whether evidence supports a finding, whether a map correction is
# right, the content of every position and verdict, severity and contested calls in the
# merge, and the report prose. This script checks that the files are complete,
# consistent with each other, and shaped as the stage files say.
#
# LF or CRLF input. Sorting is in the C locale.
# POSIX sh plus awk; the awk program uses only features that mawk, gawk, and BSD awk all
# accept: no gensub, no arrays of arrays, no length of an array, no \< or \>.
set -u

LC_ALL=C
export LC_ALL

usage() {
	echo "usage: ledger.sh build5|mandatory|seen|missing <run dir>" >&2
	echo "       ledger.sh late-ids <run dir> --tier low|medium|high --stage6 complete|failed" >&2
	echo "       ledger.sh late-check <run dir> --tier low|medium|high --stage6 complete|failed" >&2
	echo "       ledger.sh gate <run dir> --tier low|medium|high --stage6 complete|failed --late complete|failed|not-run" >&2
	echo "       ledger.sh check <run dir> --through 5|6|7 [--tier ..] [--stage6 ..] [--late ..]" >&2
	exit 2
}

fatal() {
	echo "ledger: $*" >&2
	exit 2
}

[ $# -ge 2 ] || usage
op=$1
run=$2
shift 2
case $op in
build5 | mandatory | seen | missing | late-ids | late-check | gate | check) ;;
*) usage ;;
esac

tier=
stage6=
late=
through=
while [ $# -gt 0 ]; do
	[ $# -ge 2 ] || usage
	flag=$1
	val=$2
	shift 2
	case $flag in
	--tier)
		case $val in low | medium | high) tier=$val ;; *) usage ;; esac
		;;
	--stage6)
		case $val in complete | failed) stage6=$val ;; *) usage ;; esac
		;;
	--late)
		case $val in complete | failed | not-run) late=$val ;; *) usage ;; esac
		;;
	--through)
		case $val in 5 | 6 | 7) through=$val ;; *) usage ;; esac
		;;
	*) usage ;;
	esac
done

case $op in
build5 | mandatory | seen | missing)
	[ -z "$tier$stage6$late$through" ] || usage
	;;
late-ids | late-check)
	[ -n "$tier" ] && [ -n "$stage6" ] && [ -z "$late$through" ] || usage
	;;
gate)
	[ -n "$tier" ] && [ -n "$stage6" ] && [ -n "$late" ] && [ -z "$through" ] || usage
	;;
check)
	[ -n "$through" ] || usage
	if [ "$through" -ge 6 ] && [ -z "$stage6" ]; then usage; fi
	if [ "$through" -ge 7 ] && { [ -z "$tier" ] || [ -z "$late" ]; }; then usage; fi
	;;
esac

[ -d "$run" ] || fatal "cannot read directory $run"

need() {
	if [ ! -f "$run/$1" ] || [ ! -r "$run/$1" ]; then
		fatal "cannot read $run/$1"
	fi
}

case $op in
build5) need ledger/inventory.txt ;;
mandatory | missing) need ledger/5.md ;;
seen)
	need ledger/5.md
	need ledger/6.md
	;;
late-ids | late-check)
	need ledger/5.md
	[ "$stage6" = complete ] && need ledger/6.md
	;;
gate)
	need ledger/inventory.txt
	need ledger/5.md
	[ "$stage6" = complete ] && need ledger/6.md
	[ "$late" = complete ] && need ledger/7.md
	;;
check)
	need ledger/inventory.txt
	need ledger/5.md
	if [ "$through" -ge 6 ] && [ "$stage6" = complete ]; then
		need ledger/6.md
		need codex/response.md
	fi
	if [ "$through" -ge 7 ]; then
		need gate.md
		need converged.md
		[ "$late" = complete ] && need ledger/7.md
		[ "$late" = complete ] && need late/adversary.md
	fi
	;;
esac

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# The files the awk program classifies by path: pass-one and pass-two reports, carried
# live findings, and the second-opinion answers.
(
	cd "$run" || exit 1
	for d in pass1 pass2 live/carried codex; do
		if [ -d "$d" ]; then find "$d" -type f -name '*.md' ! -name '*.pre-topup.md'; fi
	done
) | sort > "$tmp/files.txt"

cat > "$tmp/ledger.awk" <<'EOF'
# ledger.awk: the whole of ledger.sh. Variables: op, through, tier, stage6, late. The
# run directory, the file list, and the problem file come from the environment, not from
# -v, which would process backslash escapes.

function trim(s) {
	sub(/^[ \t]+/, "", s)
	sub(/[ \t]+$/, "", s)
	return s
}

function chomp(s,   n) {
	n = length(s)
	if (n > 0 && substr(s, n, 1) == "\r") s = substr(s, 1, n - 1)
	return s
}

# readfile: lines of a file, CR stripped, into a; returns the count, -1 when unreadable.
function readfile(path, a,   n, line, rc) {
	delete a
	n = 0
	while ((rc = (getline line < path)) > 0) {
		n++
		a[n] = chomp(line) ""
	}
	close(path)
	if (rc < 0) return -1
	return n
}

function fexists(p,   r, junk) {
	r = (getline junk < p)
	if (r >= 0) close(p)
	return r >= 0
}

function prob(m) {
	np++
	pm[np] = "ledger: " m
}

# cprob: a problem only the check op reports, and late-check while it reads the late
# file (inadv), since a problem of another file is not the late adversary's to fix.
function cprob(m) {
	if (op == "check" || (op == "late-check" && inadv)) prob(m)
}

function pprob(c, m) {
	if (c == 2) BADFLAG = 1
	else if (c) cprob(m)
	else prob(m)
}

function emit(s) {
	no++
	out[no] = s
}

function hasp(l, key) {
	return index(l, key) == 1
}

function kv(l, key) {
	return trim(substr(l, length(key) + 1))
}

function sevmed(s) {
	return (s == "blocker" || s == "high" || s == "medium")
}

function isid(s) {
	if (s ~ /^[XL][0-9]+$/) return 1
	if (s ~ /[ \t:]/) return 0
	if (match(s, /-[FPT][0-9]+$/) && RSTART > 1) return 1
	return 0
}

# idk: F, P, T, X, or L for an id; the empty string for anything else.
function idk(s) {
	if (!isid(s)) return ""
	if (s ~ /^[XL][0-9]+$/) return substr(s, 1, 1)
	match(s, /-[FPT][0-9]+$/)
	return substr(s, RSTART + 1, 1)
}

# isend: a line that only ends a block: runs:, consumed:, opened: (alone or with none),
# or status: complete, ignoring trailing blanks. Any other line starting with those words
# is body text.
function isend(l) {
	sub(/[ \t]+$/, "", l)
	return (l == "runs:" || l == "runs: none" || l == "consumed:" || l == "consumed: none" || l == "opened:" || l == "opened: none" || l == "status: complete")
}

# classify: set K[i] for each line of a. H2 and H3 start a block, E is a line that only
# ends one, C is a line inside a code fence (fence lines included), T is any other line.
# Returns 1 when the file ends inside a fence.
function classify(a, n,   i, inf, t, l) {
	delete K
	inf = 0
	for (i = 1; i <= n; i++) {
		l = a[i]
		t = l
		sub(/^[ \t]+/, "", t)
		if (index(t, "```") == 1) {
			inf = !inf
			K[i] = "C"
			continue
		}
		if (inf) {
			K[i] = "C"
			continue
		}
		if (index(l, "### ") == 1) K[i] = "H3"
		else if (index(l, "## ") == 1) K[i] = "H2"
		else if (isend(l)) K[i] = "E"
		else K[i] = "T"
	}
	return inf
}

# extent: the last line of the block that starts at line i.
function extent(i, n,   e) {
	e = i
	while (e + 1 <= n && (K[e + 1] == "T" || K[e + 1] == "C")) e++
	return e
}

# lastnb: the last line from i to e that is not blank.
function lastnb(a, i, e) {
	while (e > i && trim(a[e]) == "") e--
	return e
}

# check_finding: the severity and label rules for the finding block of lines s to e.
# Sets G_sev and G_lab.
function check_finding(a, s, e, who, c,   k, ns, nl, sv, lb) {
	ns = 0
	nl = 0
	sv = ""
	lb = ""
	for (k = s + 1; k <= e; k++) {
		if (K[k] != "T") continue
		if (hasp(a[k], "- severity:")) {
			ns++
			sv = kv(a[k], "- severity:")
		} else if (hasp(a[k], "- label:")) {
			nl++
			lb = kv(a[k], "- label:")
		}
	}
	if (ns != 1) pprob(c, who "needs exactly one - severity: line")
	else if (!(sv in okSev)) pprob(c, who "severity '" sv "' is not blocker, high, medium, low, or note")
	if (nl != 1) pprob(c, who "needs exactly one - label: line")
	else if (!(lb in okLab)) pprob(c, who "label '" lb "' is not verified fact, unverified assumption, or convention")
	G_sev = sv
	G_lab = lb
}

# parse_verdict: the rules for the verdict block of lines s to e. Sets V_sev and V_lab
# (the new value, or the empty string for unchanged), V_ev, and V_reason. Returns 1 when
# the block is well formed.
function parse_verdict(a, s, e, word, who, c,   k, l, t, ns, nl, ne, nr, cur, ok, sv, lb, ev, rsn, p, o, nw) {
	ok = 1
	if (!(word in okVerdict)) {
		pprob(c, who "verdict '" word "' is not survives, downgraded, reworded, or dropped")
		ok = 0
	}
	ns = 0
	nl = 0
	ne = 0
	nr = 0
	cur = ""
	sv = ""
	lb = ""
	ev = ""
	rsn = ""
	for (k = s + 1; k <= e; k++) {
		l = a[k]
		if (K[k] == "T") {
			if (hasp(l, "- severity:")) { ns++; sv = kv(l, "- severity:"); cur = "s"; continue }
			if (hasp(l, "- label:")) { nl++; lb = kv(l, "- label:"); cur = "l"; continue }
			if (hasp(l, "- evidence:")) { ne++; ev = kv(l, "- evidence:"); cur = "e"; continue }
			if (hasp(l, "- reason:")) { nr++; rsn = kv(l, "- reason:"); cur = "r"; continue }
			if (l ~ /^- [A-Za-z ]+:/) { cur = ""; continue }
		}
		t = trim(l)
		if (t == "") continue
		if (cur == "e") ev = (ev == "" ? t : ev " " t)
		else if (cur == "r") rsn = (rsn == "" ? t : rsn " " t)
	}
	V_sev = ""
	V_lab = ""
	if (ns != 1) { pprob(c, who "needs exactly one - severity: line"); ok = 0 }
	else if (sv != "unchanged") {
		p = index(sv, " -> ")
		o = substr(sv, 1, p - 1)
		nw = substr(sv, p + 4)
		if (p == 0 || !(o in okSev) || !(nw in okSev)) {
			pprob(c, who "- severity: must be '<old> -> <new>' with allowed values, or unchanged")
			ok = 0
		} else V_sev = nw
	}
	if (nl != 1) { pprob(c, who "needs exactly one - label: line"); ok = 0 }
	else if (lb != "unchanged") {
		p = index(lb, " -> ")
		o = substr(lb, 1, p - 1)
		nw = substr(lb, p + 4)
		if (p == 0 || !(o in okLab) || !(nw in okLab)) {
			pprob(c, who "- label: must be '<old> -> <new>' with allowed values, or unchanged")
			ok = 0
		} else V_lab = nw
	}
	if (ne != 1 || ev == "") { pprob(c, who "needs exactly one nonempty - evidence: line"); ok = 0 }
	if (nr > 1) { pprob(c, who "has more than one - reason: line"); ok = 0 }
	V_ev = ev
	V_reason = rsn
	return ok
}

# fhead: set HID to the id of a finding heading text (after "### "); 1 when it is one.
function fhead(head,   p, id) {
	p = index(head, ": ")
	id = ""
	if (p > 0 && trim(substr(head, p + 2)) != "") id = substr(head, 1, p - 1)
	if (id != "" && isid(id)) {
		HID = id
		return 1
	}
	return 0
}

# malformed: a "### " heading that names an id but is not a finding or verdict heading.
# xl is 0 for a pass file, where an X or L id never belongs, so `### x86: notes` there
# is text; it is 1 for the files that carry additions, where a lower-case x<n> or l<n>
# is a mis-cased id.
function malformed(head, xl,   p, tok) {
	p = index(head, " ")
	tok = (p > 0 ? substr(head, 1, p - 1) : head)
	p = index(tok, ":")
	if (p > 0) tok = substr(tok, 1, p - 1)
	return (isid(tok) || (xl && tok ~ /^[xl][0-9]+$/) || tok ~ /.-[fpt][0-9]+$/)
}

# ---------------------------------------------------------------------------
# The inventory.

function load_inv(   n, i, line, f, nf, k, sc, st, key, r, c, p, fl) {
	n = readfile(run "/ledger/inventory.txt", IA)
	nrec = 0
	for (i = 1; i <= n; i++) {
		line = trim(IA[i])
		if (line == "") continue
		nf = split(line, f, /[ \t]+/)
		if (nf != 5) {
			prob("ledger/inventory.txt:" i ": expected 5 fields, got " nf)
			continue
		}
		k = f[1]
		sc = f[2]
		st = f[5]
		if (k != "pass1" && k != "pass2" && k != "topup") {
			prob("ledger/inventory.txt:" i ": unknown record kind '" k "'")
			continue
		}
		if (st != "complete" && st != "failed" && !(k == "pass2" && st == "not-run")) {
			prob("ledger/inventory.txt:" i ": status '" st "' is not allowed for " k)
			continue
		}
		if (f[3] == "-" && st == "complete") {
			prob("ledger/inventory.txt:" i ": a complete " k " record needs a path")
			continue
		}
		if (f[3] ~ /\.pre-topup\.md$/) {
			prob("ledger/inventory.txt:" i ": " f[3] " is a pre-top-up copy and has no record")
			continue
		}
		key = k SUBSEP sc
		if (key in recof) {
			prob("ledger/inventory.txt:" i ": duplicate " k " record for scope " sc)
			continue
		}
		nrec++
		rk[nrec] = k
		rs[nrec] = sc
		rp[nrec] = f[3]
		rm[nrec] = f[4]
		rst[nrec] = st
		rl[nrec] = i
		recof[key] = nrec
		if (!(sc in scidx)) {
			nsc++
			scname[nsc] = sc
			scidx[sc] = nsc
		}
		if (f[3] != "-") {
			if (f[3] in recpath) prob("ledger/inventory.txt:" i ": " f[3] " is named by two records")
			recpath[f[3]] = 1
		}
		if (k == "pass2" && st == "complete") p2c[f[3]] = 1
	}
	for (r = 1; r <= nrec; r++) {
		if (rk[r] != "pass1" && !((("pass1") SUBSEP rs[r]) in recof))
			prob("ledger/inventory.txt:" rl[r] ": " rk[r] " record for scope " rs[r] " has no pass1 record")
		if (rk[r] == "pass1" && rst[r] == "complete" && !((("pass2") SUBSEP rs[r]) in recof))
			prob("ledger/inventory.txt: complete pass1 scope " rs[r] " has no pass2 record")
		if (rp[r] != "-" && !fexists(run "/" rp[r]))
			prob("ledger/inventory.txt:" rl[r] ": " rp[r] " does not exist")
	}
	for (i = 1; i <= nfl; i++) {
		fl = FL[i]
		if ((index(fl, "pass1/") == 1 || index(fl, "pass2/") == 1) && !(fl in recpath))
			prob(fl " is not in ledger/inventory.txt")
	}
}

# ---------------------------------------------------------------------------
# Pass-one, pass-two, and top-up files.

# sp: a problem in a complete file; in a failed file, a block that is skipped and counted.
function sp(m) {
	if (LEN) badn++
	else prob(m)
}

function parse_source(r,   path, kind, sc, m, n, i, e, e2, head, p, rest, id, word, hd, cap, k, want, need_, unclosed, last, lastl) {
	path = rp[r]
	kind = rk[r]
	sc = rs[r]
	m = rm[r]
	LEN = (rst[r] == "failed")
	badn = 0
	n = readfile(run "/" path, SA)
	if (n < 0) {
		sp(path ": cannot read the file")
		return
	}
	unclosed = classify(SA, n)
	if (unclosed && !LEN) prob(path ": the file ends inside a code fence")
	if (!LEN) {
		last = n
		while (last > 0 && trim(SA[last]) == "") last--
		lastl = SA[last]
		sub(/[ 	]+$/, "", lastl)
		if (last == 0 || lastl != "status: complete") prob(path ": the inventory says complete, but the file does not end with status: complete")
	}
	i = 1
	while (i <= n) {
		if (K[i] == "H3") {
			e = extent(i, n)
			head = substr(SA[i], 5)
			if (LEN && index(head, "verdict on ") == 1) {
			} else if (index(head, "verdict on ") == 1) {
				rest = substr(head, 12)
				p = index(rest, ": ")
				if (p == 0) sp(path ":" i ": malformed verdict heading")
				else if (kind != "pass2") sp(path ":" i ": a verdict block belongs in a pass-two file")
				else {
					id = substr(rest, 1, p - 1)
					word = trim(substr(rest, p + 2))
					if (id in v_word || id in v_bad) sp(path ":" i ": duplicate verdict for " id)
					else if (parse_verdict(SA, i, e, word, path ":" i ": verdict on " id ": ", 0)) {
						v_word[id] = word
						v_sev[id] = V_sev
						v_lab[id] = V_lab
						v_ev[id] = V_ev
						v_reason[id] = V_reason
						v_path[id] = path
						v_model[id] = m
						v_scope[id] = sc
						v_line[id] = i
						nv++
						v_ord[nv] = id
					} else v_bad[id] = 1
				}
			} else if (fhead(head)) {
				id = HID
				want = (kind == "pass1" ? "F" : (kind == "pass2" ? "P" : "T"))
				if (index(id, sc "-") != 1) sp(path ":" i ": " id " does not start with its scope '" sc "-'")
				else if (idk(id) != want) sp(path ":" i ": " id " is not a " kind " finding id")
				else if (id in f_origin) sp(path ":" i ": duplicate finding id " id)
				else {
					BADFLAG = 0
					check_finding(SA, i, e, path ":" i ": " id ": ", LEN ? 2 : 0)
					if (LEN && (BADFLAG || (unclosed && e == n))) { badn++; i = e + 1; continue }
					f_failed[id] = LEN
					f_origin[id] = kind
					f_scope[id] = sc
					f_path[id] = path
					f_model[id] = m
					f_sev[id] = G_sev
					f_lab[id] = G_lab
					e2 = lastnb(SA, i, e)
					f_n[id] = e2 - i + 1
					for (k = i; k <= e2; k++) f_ol[id, k - i + 1] = SA[k]
					if (kind == "pass1") L1[sc] = L1[sc] " " id
					else if (kind == "pass2") Lp[sc] = Lp[sc] " " id
					else Lt[sc] = Lt[sc] " " id
				}
			} else if (malformed(head, 0)) sp(path ":" i ": malformed finding heading")
			i = e + 1
			continue
		}
		if (K[i] == "H2" && kind == "pass2" && !LEN) {
			hd = trim(SA[i])
			cap = 0
			if (hd == "## Verified OK challenged") cap = 1
			else if (hd == "## Coverage gaps") cap = 2
			if (cap) {
				e = extent(i, n)
				e2 = lastnb(SA, i, e)
				if ((cap == 1 && (sc in vokN)) || (cap == 2 && (sc in gapN))) sp(path ":" i ": duplicate '" hd "' section")
				else if (cap == 1) {
					vokN[sc] = e2 - i
					for (k = i + 1; k <= e2; k++) vokL[sc, k - i] = SA[k]
				} else {
					gapN[sc] = e2 - i
					for (k = i + 1; k <= e2; k++) gapL[sc, k - i] = SA[k]
				}
			}
		}
		i++
	}
	rbad[r] = badn
}

function load_sources(   r, pass, kinds, i, id, sc, path, ids, nid, k) {
	kinds[1] = "pass1"
	kinds[2] = "pass2"
	kinds[3] = "topup"
	for (pass = 1; pass <= 3; pass++)
		for (r = 1; r <= nrec; r++)
			if (rk[r] == kinds[pass] && rst[r] != "not-run" && rp[r] != "-" && fexists(run "/" rp[r])) parse_source(r)
	for (i = 1; i <= nv; i++) {
		id = v_ord[i]
		if (!(id in f_origin)) prob(v_path[id] ":" v_line[id] ": verdict on " id " has no finding")
		else if (f_origin[id] != "pass1") prob(v_path[id] ":" v_line[id] ": verdict on " id ", which is not a pass-one finding")
		else if (f_scope[id] != v_scope[id]) prob(v_path[id] ":" v_line[id] ": verdict on " id ", a finding of scope " f_scope[id])
	}
	for (r = 1; r <= nrec; r++) {
		if (rk[r] != "pass2" || rst[r] != "complete" || rp[r] == "-" || !fexists(run "/" rp[r])) continue
		sc = rs[r]
		path = rp[r]
		nid = split(L1[sc], ids, " ")
		for (k = 1; k <= nid; k++)
			if (!f_failed[ids[k]] && !(ids[k] in v_word) && !(ids[k] in v_bad)) prob(path ": no verdict for " ids[k])
		if (!(sc in vokN)) prob(path ": no '## Verified OK challenged' section")
		if (!(sc in gapN)) prob(path ": no '## Coverage gaps' section")
	}
}

function p2status(sc,   key) {
	key = "pass2" SUBSEP sc
	if (!(key in recof)) return ""
	return rst[recof[key]]
}

function emit_finding(id,   sc, kind, ag, sv, lb, state, st, k) {
	sc = f_scope[id]
	kind = f_origin[id]
	ag = (kind == "pass2" ? "cca:adversary" : "cca:auditor")
	emit("## " id)
	emit("- origin: " kind)
	emit("- author: " ag ", model " f_model[id] ", file " f_path[id])
	emit("### Original")
	for (k = 1; k <= f_n[id]; k++) emit(f_ol[id, k])
	emit("### Pass-two verdicts")
	sv = f_sev[id]
	lb = f_lab[id]
	if (f_failed[id]) {
		emit("- none")
		state = "no verdict: output failed"
	} else if (id in v_word) {
		emit("- " v_word[id] " by cca:adversary (model " v_model[id] ") in " v_path[id] ": " v_reason[id] "; evidence: " v_ev[id])
		if (v_sev[id] != "") sv = v_sev[id]
		if (v_lab[id] != "") lb = v_lab[id]
		state = v_word[id]
	} else {
		emit("- none")
		if (kind != "pass1") state = "no verdict: late addition"
		else {
			st = p2status(sc)
			if (st == "failed") state = "no verdict: scope failed"
			else if (st == "not-run") state = "no verdict: not run, budget expired"
			else state = "no verdict: unknown"
		}
	}
	emit("### State after pass two")
	emit(sv ", " lb ", " state)
	emit("")
}

function emit_list(list,   ids, nid, k) {
	nid = split(list, ids, " ")
	for (k = 1; k <= nid; k++) emit_finding(ids[k])
}

function build_out(   s, sc, k, any, r) {
	no = 0
	for (s = 1; s <= nsc; s++) {
		sc = scname[s]
		emit_list(L1[sc])
		emit_list(Lp[sc])
		emit_list(Lt[sc])
	}
	for (s = 1; s <= nsc; s++) {
		sc = scname[s]
		if (p2status(sc) != "complete") continue
		emit("## Verified OK challenged: " sc)
		for (k = 1; k <= vokN[sc]; k++) emit(vokL[sc, k])
		emit("")
		emit("## Coverage gaps: " sc)
		for (k = 1; k <= gapN[sc]; k++) emit(gapL[sc, k])
		emit("")
	}
	any = 0
	for (r = 1; r <= nrec; r++) if (rst[r] == "failed") any = 1
	if (any) {
		emit("## Failed outputs")
		for (r = 1; r <= nrec; r++) {
			if (rst[r] != "failed") continue
			if (rp[r] == "-") emit("- " rk[r] " " rs[r] ": no file")
			else if (rbad[r] > 0) emit("- " rp[r] " (" rbad[r] " blocks not parsed)")
			else emit("- " rp[r])
		}
		emit("")
	}
}

# ---------------------------------------------------------------------------
# The ledger files.

function load_l5(   n, i, rest, cur, mode, t, st, p, q, rem, w, pp) {
	n = readfile(run "/ledger/5.md", L5A)
	if (n < 0) return
	l5nl = n
	cutline = n + 1
	if (classify(L5A, n)) prob("ledger/5.md: the file ends inside a code fence")
	cur = ""
	mode = ""
	for (i = 1; i <= n; i++) {
		if (K[i] == "H2") {
			if (trim(L5A[i]) == "## Map corrections applied" && cutline > n) cutline = i
			if (trim(L5A[i]) == "## Map corrections applied") { mapA++; if (mapA == 1) mapAline = i }
			if (trim(L5A[i]) == "## Map corrections not applied") { mapN++; if (mapN == 1) mapNline = i }
			rest = trim(substr(L5A[i], 4))
			cur = ""
			if (isid(rest)) {
				if (rest in l5seen) prob("ledger/5.md:" i ": duplicate section for " rest)
				else {
					l5seen[rest] = 1
					l5n++
					l5ord[l5n] = rest
					cur = rest
				}
			}
			mode = ""
			continue
		}
		if (K[i] == "H3") {
			if (cur != "") {
				if (trim(L5A[i]) == "### Pass-two verdicts") mode = "v"
				else if (trim(L5A[i]) == "### State after pass two") mode = "s"
				else mode = "o"
			}
			continue
		}
		if (K[i] == "E") {
			cur = ""
			mode = ""
			continue
		}
		if (cur == "" || K[i] != "T") continue
		t = L5A[i]
		if (mode == "" && hasp(t, "- origin:")) {
			if (!(cur in l5origin)) l5origin[cur] = kv(t, "- origin:")
		} else if (mode == "v" && !(cur in l5vl) && trim(t) != "") {
			l5vl[cur] = t
			w = trim(substr(t, 3))
			p = index(w, " ")
			if (p > 0) w = substr(w, 1, p - 1)
			l5vw[cur] = w
			p = index(t, ") in ")
			if (p > 0) {
				rem = substr(t, p + 5)
				q = index(rem, ": ")
				if (q > 0) l5vp[cur] = substr(rem, 1, q - 1)
			}
		} else if (mode == "s" && !(cur in l5state) && trim(t) != "") {
			st = trim(t)
			p = index(st, ", ")
			if (p > 0) {
				rem = substr(st, p + 2)
				q = index(rem, ", ")
				if (q > 0 && (substr(st, 1, p - 1) in okSev)) {
					l5sev[cur] = substr(st, 1, p - 1)
					l5lab[cur] = substr(rem, 1, q - 1)
					l5state[cur] = substr(rem, q + 2)
				}
			}
			if (!(cur in l5state)) {
				l5state[cur] = ""
				prob("ledger/5.md:" i ": malformed state line for " cur)
			}
		}
	}
	for (i = 1; i <= l5n; i++)
		if (!(l5ord[i] in l5state)) prob("ledger/5.md: section for " l5ord[i] " has no '### State after pass two' line")
}

function credit5(id) {
	return (id in l5vp) && (l5vp[id] in p2c) && (l5vw[id] in okVerdict)
}

function load_live(   n, i, rest, p) {
	n = readfile(run "/live/findings.md", LA)
	if (n >= 0) {
		# No fence handling: a section runs to the next "## " line (live.md).
		for (i = 1; i <= n; i++) {
			if (index(LA[i], "## ") != 1) continue
			rest = trim(substr(LA[i], 4))
			p = index(rest, ": ")
			if (p > 0 && isid(substr(rest, 1, p - 1))) {
				prob("live/findings.md:" i ": heading '" rest "' must be '## <id>' alone")
				continue
			}
			if (isid(rest) && !(rest in liveset)) {
				liveset[rest] = 1
				livn++
				liveord[livn] = rest
			}
		}
	}
	for (i = 1; i <= nfl; i++) {
		rest = FL[i]
		if (index(rest, "live/carried/") != 1 || rest !~ /\.md$/) continue
		rest = substr(rest, 14)
		sub(/\.md$/, "", rest)
		if (isid(rest) && (rest in liveset) && !(rest in carset)) {
			carset[rest] = 1
			carn++
			carord[carn] = rest
		}
	}
}

function ismand(id) {
	if (id in liveset) return 1
	if (!(id in l5sev)) return 0
	return (sevmed(l5sev[id]) || l5state[id] == "downgraded" || l5state[id] == "dropped")
}

function load_l6(   n, i, e, rest, cur, sec, t, id, who, k, unclosed, len6) {
	n = readfile(run "/ledger/6.md", L6A)
	if (n < 0) return
	l6ok = 1
	# With stage 6 failed the file may be partial: a file that ends inside a fence, a
	# malformed addition heading, and the X block that holds the open fence are problems
	# of check only, and that block is left out. With stage 6 complete they are errors.
	len6 = (stage6 == "failed")
	unclosed = classify(L6A, n)
	if (unclosed) pprob(len6, "ledger/6.md: the file ends inside a code fence")
	cur = ""
	sec = ""
	i = 1
	while (i <= n) {
		if (K[i] == "H2") {
			rest = trim(substr(L6A[i], 4))
			cur = ""
			sec = "other"
			if (trim(L6A[i]) == "## Seen, no position") sec = "seen"
			else if (isid(rest)) {
				sec = "pos"
				if (rest in p6seen) {
					prob("ledger/6.md:" i ": duplicate position section for " rest)
					sec = "other"
				} else {
					p6seen[rest] = 1
					p6n++
					p6ord[rest] = i
					p6list[p6n] = rest
					cur = rest
				}
			}
			i++
			continue
		}
		if (K[i] == "H3") {
			cur = ""
			sec = "other"
			e = extent(i, n)
			if (!fhead(substr(L6A[i], 5)) && malformed(substr(L6A[i], 5), 1)) pprob(len6, "ledger/6.md:" i ": malformed addition heading")
			if (fhead(substr(L6A[i], 5)) && idk(HID) == "X") {
				id = HID
				if (len6 && unclosed && e == n) {
				} else if (id in x6seen) prob("ledger/6.md:" i ": duplicate addition " id)
				else {
					x6seen[id] = 1
					x6n++
					x6ord[x6n] = id
					check_finding(L6A, i, e, "ledger/6.md:" i ": " id ": ", 1)
				}
			}
			i = e + 1
			continue
		}
		if (K[i] == "E") {
			cur = ""
			sec = ""
			i++
			continue
		}
		t = L6A[i]
		if (K[i] == "T") {
			if (sec == "pos") {
				if (hasp(t, "- position:") && !(cur in p6pos_v)) p6pos_v[cur] = kv(t, "- position:")
				else if (hasp(t, "- evidence:") && !(cur in p6ev_v)) p6ev_v[cur] = kv(t, "- evidence:")
				else if (hasp(t, "- answer location:") && !(cur in p6loc_v)) p6loc_v[cur] = kv(t, "- answer location:")
			} else if (sec == "seen" && trim(t) != "") {
				t = trim(t)
				if (t == "none" || t == "- none") {
				} else if (hasp(t, "- ") && isid(trim(substr(t, 3)))) {
					sn++
					sl[sn] = trim(substr(t, 3))
				} else cprob("ledger/6.md:" i ": unrecognized line in '## Seen, no position': " t)
			}
		}
		i++
	}
	for (k = 1; k <= p6n; k++) {
		id = p6list[k]
		if (p6pos_v[id] != "") p6pos[id] = 1
	}
}

function load_l7(   n, i, e, rest, cur, id, t, w, p) {
	n = readfile(run "/ledger/7.md", L7A)
	if (n < 0) return
	l7ok = 1
	if (classify(L7A, n)) prob("ledger/7.md: the file ends inside a code fence")
	cur = ""
	i = 1
	while (i <= n) {
		if (K[i] == "H2") {
			rest = trim(substr(L7A[i], 4))
			cur = ""
			if (isid(rest)) {
				if (rest in l7seen) prob("ledger/7.md:" i ": duplicate section for " rest)
				else {
					l7seen[rest] = 1
					l7n++
					l7ord[l7n] = rest
					cur = rest
					l7line[rest] = i
				}
			}
			i++
			continue
		}
		if (K[i] == "H3") {
			cur = ""
			e = extent(i, n)
			if (!fhead(substr(L7A[i], 5)) && malformed(substr(L7A[i], 5), 1)) prob("ledger/7.md:" i ": malformed addition heading")
			if (fhead(substr(L7A[i], 5)) && idk(HID) == "L") {
				id = HID
				if (id in l7Lseen) prob("ledger/7.md:" i ": duplicate addition " id)
				else {
					l7Lseen[id] = 1
					l7Ln++
					l7Lord[l7Ln] = id
					check_finding(L7A, i, e, "ledger/7.md:" i ": " id ": ", 1)
				}
			}
			i = e + 1
			continue
		}
		if (K[i] == "E") {
			cur = ""
			i++
			continue
		}
		if (cur != "" && K[i] == "T" && hasp(L7A[i], "- verdict:") && !(cur in l7v)) {
			t = kv(L7A[i], "- verdict:")
			l7v[cur] = t
			w = t
			p = index(w, " ")
			if (p > 0) w = substr(w, 1, p - 1)
			if (!(w in okVerdict)) prob("ledger/7.md:" i ": verdict of " cur " must start with survives, downgraded, reworded, or dropped")
		}
		i++
	}
}

# ---------------------------------------------------------------------------
# The second opinion's answer and the late adversary's file.

function load_resp(   i, j, n, f, l, t, p, tok, id, inf) {
	for (i = 1; i <= nfl; i++) {
		f = FL[i]
		if (f !~ /^codex\/response(-[0-9]+)?\.md$/) continue
		n = readfile(run "/" f, RA)
		inf = 0
		for (j = 1; j <= n; j++) {
			l = RA[j]
			if (l ~ /^--- follow-up, thread .* ---$/ || l ~ /^--- batch [0-9]+ ---$/) {
				inf = 0
				continue
			}
			t = l
			sub(/^[ 	]+/, "", t)
			if (index(t, "```") == 1) {
				inf = !inf
				continue
			}
			if (inf) continue
			t = l
			sub(/^[ 	]+/, "", t)
			sub(/^[0-9]+[.)]/, "", t)
			sub(/^[ 	*#`-]+/, "", t)
			if (l !~ /^#+ X[0-9]+:/ && l ~ /^#+ +[xX][0-9]+:/) cprob(f ":" j ": heading names an X addition but does not read #+ X<n>:")
			p = index(t, ":")
			if (p > 1) {
				tok = substr(t, 1, p - 1)
				sub(/[*`]+$/, "", tok)
				if (tok != "" && tok !~ /[ \t]/) prov[tok] = 1
			}
			if (l ~ /^#+ X[0-9]+:/) {
				id = substr(l, index(l, "X"))
				id = substr(id, 1, index(id, ":") - 1)
				if (!(id in xresp)) {
					xresp[id] = 1
					xrn++
					xrord[xrn] = id
				}
			}
		}
	}
}

function load_adv(   n, i, e, rest, p, id, word, head, last, lastl) {
	n = readfile(run "/late/adversary.md", AA)
	if (n < 0) {
		if (op == "late-check") prob("late/adversary.md: cannot read the file")
		return
	}
	advok = 1
	if (classify(AA, n)) cprob("late/adversary.md: the file ends inside a code fence")
	last = n
	while (last > 0 && trim(AA[last]) == "") last--
	lastl = AA[last]
	sub(/[ \t]+$/, "", lastl)
	if (last == 0 || lastl != "status: complete")
		cprob("late/adversary.md: " (op == "late-check" ? "" : "--late complete, but ") "the file does not end with status: complete")
	i = 1
	while (i <= n) {
		if (K[i] == "H3") {
			e = extent(i, n)
			head = substr(AA[i], 5)
			if (index(head, "verdict on ") == 1) {
				rest = substr(head, 12)
				p = index(rest, ": ")
				if (p == 0) prob("late/adversary.md:" i ": malformed verdict heading")
				else {
					id = substr(rest, 1, p - 1)
					word = trim(substr(rest, p + 2))
					if (id in advv) prob("late/adversary.md:" i ": duplicate verdict for " id)
					else {
						advv[id] = word
						advline[id] = i
						advn++
						advord[advn] = id
						parse_verdict(AA, i, e, word, "late/adversary.md:" i ": verdict on " id ": ", 0)
					}
				}
			} else if (fhead(head)) {
				id = HID
				if (idk(id) != "L") prob("late/adversary.md:" i ": " id " is not a late finding id")
				else if (id in advL) prob("late/adversary.md:" i ": duplicate finding id " id)
				else {
					check_finding(AA, i, e, "late/adversary.md:" i ": " id ": ", 0)
					advL[id] = 1
					advLn++
					advLord[advLn] = id
				}
			} else if (malformed(head, 1)) prob("late/adversary.md:" i ": malformed finding heading")
			i = e + 1
			continue
		}
		i++
	}
}

# ---------------------------------------------------------------------------
# The gate.

function addu(id) {
	if (id in guni) return
	guni[id] = 1
	gn++
	gord[gn] = id
}

function compute_gate(   i, id, org, live, s6c, pos, latev, liveok, med, r, c) {
	for (i = 1; i <= l5n; i++) addu(l5ord[i])
	for (i = 1; i <= x6n; i++) addu(x6ord[i])
	for (i = 1; i <= l7Ln; i++) addu(l7Lord[i])
	for (i = 1; i <= carn; i++) addu(carord[i])
	s6c = (stage6 == "complete")
	for (i = 1; i <= gn; i++) {
		id = gord[i]
		live = (id in liveset)
		pos = (s6c && (id in p6pos))
		latev = (late == "complete" && (id in l7v) && l7v[id] != "")
		liveok = (s6c && pos && latev)
		med = ((id in l5sev) && sevmed(l5sev[id]))
		org = (id in l5origin ? l5origin[id] : "")
		if (id in l5seen && org == "") org = "pass1"
		if (!(id in l5seen)) org = idk(id)
		r = ""
		if (live && !liveok) r = "provisional; live result not yet reviewed"
		else if (org == "pass1") {
			if (!s6c) r = "provisional; stage 6 failed"
			else if (!credit5(id)) r = "provisional; no stage 5 verdict"
			else if (med && !pos) r = "provisional; medium or above without a stage 6 position"
			else if (live) r = "counts; live review completed"
			else r = "counts; stage 5 verdict, stage 6 " (pos ? "position" : "acknowledged (low or note)")
		} else if (org == "pass2" || org == "topup") {
			if (!s6c) r = "provisional; stage 6 failed"
			else if (tier == "low" && !live) r = "provisional; late addition at low tier"
			else if (!latev) r = "provisional; no late verdict"
			else if (med && !pos) r = "provisional; medium or above without a stage 6 position"
			else if (live) r = "counts; live review completed"
			else r = "counts; late verdict, stage 6 " (pos ? "position" : "acknowledged (low or note)")
		} else if (org == "X") {
			if (tier == "low" && !live) r = "provisional; late addition at low tier"
			else if (!latev) r = "provisional; no late verdict"
			else if (live) r = "counts; live review completed"
			else r = "counts; late verdict"
		} else if (org == "L") {
			if (id in carset) r = "counts; live review completed"
			else r = "provisional; late finding"
		} else r = "counts; live review completed"
		gline[id] = id ": " r
		gcounts[id] = (index(r, "counts") == 1)
	}
}

# ---------------------------------------------------------------------------
# The checks.

function known(id) {
	return (id in l5seen) || (id in x6seen) || (id in liveset) || (id in carset) || (id in l7Lseen)
}

function addli(id) {
	if (id in liset) return
	liset[id] = 1
	lin++
	liord[lin] = id
}

# restore_req: a stage 6 position that asks for a restore, in any letter case.
function restore_req(v) {
	return (index(tolower(v), "restore requested") == 1)
}

# restore_word: a position whose first word is restore (restore:, Restore please), not
# a longer word such as restores.
function restore_word(v) {
	v = tolower(v)
	return (index(v, "restore") == 1 && substr(v, 8, 1) !~ /[a-z]/)
}

# late_ids: the ids the late adversary must challenge (liord[1..lin]).
function late_ids(   i, id) {
	lin = 0
	split("", liset)
	if (tier != "low") {
		for (i = 1; i <= l5n; i++) {
			id = l5ord[i]
			if (l5origin[id] == "pass2" || l5origin[id] == "topup") addli(id)
		}
		for (i = 1; i <= x6n; i++) addli(x6ord[i])
		for (i = 1; i <= p6n; i++) {
			id = p6list[i]
			if (stage6 == "complete" && restore_req(p6pos_v[id])) addli(id)
		}
	}
	for (i = 1; i <= livn; i++) addli(liveord[i])
}

function check5(   i, id, na, ne, m, k, first, nexp) {
	if (mapA != 1) cprob(mapA == 0 ? "ledger/5.md: no '## Map corrections applied' heading" : "ledger/5.md: '## Map corrections applied' appears " mapA " times")
	if (mapN != 1) cprob(mapN == 0 ? "ledger/5.md: no '## Map corrections not applied' heading" : "ledger/5.md: '## Map corrections not applied' appears " mapN " times")
	if (mapA >= 1 && mapN >= 1 && mapNline < mapAline) cprob("ledger/5.md: '## Map corrections not applied' comes before '## Map corrections applied'")
	for (i = 1; i <= nbid; i++) {
		id = bid[i]
		if (!(id in l5seen)) cprob("ledger/5.md: no section for " id)
	}
	for (i = 1; i <= l5n; i++) {
		id = l5ord[i]
		if (!(id in f_origin)) cprob("ledger/5.md: section for " id ", which no inventoried file holds")
	}
	if (np_src > 0) return
	ne = no
	while (ne > 0 && trim(out[ne]) == "") ne--
	na = cutline - 1
	while (na > 0 && trim(L5A[na]) == "") na--
	m = (ne < na ? ne : na)
	first = 0
	for (k = 1; k <= m; k++)
		if (out[k] != L5A[k]) { first = k; break }
	if (!first && ne != na) first = m + 1
	if (first) cprob("ledger/5.md differs from the build5 output at line " first)
}

function check6(   i, id, k, n, s6c, expect) {
	s6c = (stage6 == "complete")
	if (!s6c && !l6ok) return
	for (i = 1; i <= p6n; i++) {
		id = p6list[i]
		if (!known(id)) cprob("ledger/6.md:" p6ord[id] ": position for unknown id " id)
		if (p6pos_v[id] == "") cprob("ledger/6.md:" p6ord[id] ": " id " has no nonempty - position: line")
		else if (restore_word(p6pos_v[id]) && !restore_req(p6pos_v[id])) cprob("ledger/6.md:" p6ord[id] ": " id ": a restore position must start with \"restore requested\"")
		if (p6ev_v[id] == "") cprob("ledger/6.md:" p6ord[id] ": " id " has no nonempty - evidence: line")
		if (p6loc_v[id] == "") cprob("ledger/6.md:" p6ord[id] ": " id " has no nonempty - answer location: line")
		if (!(id in prov)) cprob("ledger/6.md:" p6ord[id] ": no line starting '" id ":' in the codex response files")
	}
	for (i = 1; i <= x6n; i++) {
		id = x6ord[i]
		if (id in carset) cprob("ledger/6.md: addition " id " reuses a carried id")
		if (!(id in xresp)) cprob("ledger/6.md: addition " id " is not a heading of the codex response files")
	}
	for (i = 1; i <= xrn; i++) {
		id = xrord[i]
		if (!(id in x6seen)) cprob("ledger/6.md: no addition " id ", which the codex response files raise")
	}
	if (!s6c) return
	for (i = 1; i <= livn; i++) {
		id = liveord[i]
		if (!(id in p6seen)) cprob("ledger/6.md: mandatory id " id " has no position")
	}
	for (i = 1; i <= l5n; i++) {
		id = l5ord[i]
		if (ismand(id) && !(id in p6seen) && !(id in liveset)) cprob("ledger/6.md: mandatory id " id " has no position")
		expect[id] = (!ismand(id) && !(id in p6seen))
	}
	for (i = 1; i <= sn; i++) {
		id = sl[i]
		if (id in sseen) cprob("ledger/6.md: '## Seen, no position' lists " id " twice")
		sseen[id] = 1
		if (!(id in l5seen)) cprob("ledger/6.md: '## Seen, no position' lists unknown id " id)
		else if (ismand(id)) cprob("ledger/6.md: '## Seen, no position' lists mandatory id " id)
		else if (id in p6seen) cprob("ledger/6.md: '## Seen, no position' lists " id ", which has a position")
	}
	for (i = 1; i <= l5n; i++) {
		id = l5ord[i]
		if (expect[id] && !(id in sseen)) cprob("ledger/6.md: '## Seen, no position' does not list " id)
	}
}

function check7(   w7, i, id, n, k, p, items, nit, c, j, hd, e, abs, na, cnt, anyc, a, ns_, ng, ln, g, exp_, seenl, gl, gid, last, nm, cnn) {
	if (late == "complete") {
		for (i = 1; i <= l7n; i++) {
			id = l7ord[i]
			if (id in l7v && !(id in advv)) cprob("ledger/7.md:" l7line[id] ": verdict of " id " has no verdict block in late/adversary.md")
			else if (id in l7v) {
				w7 = l7v[id]
				p = index(w7, " ")
				if (p > 0) w7 = substr(w7, 1, p - 1)
				if (w7 != advv[id]) cprob("ledger/7.md:" l7line[id] ": verdict of " id " is " w7 ", but late/adversary.md says " advv[id])
			}
			if (!known(id)) cprob("ledger/7.md:" l7line[id] ": section for unknown id " id)
		}
		for (i = 1; i <= advn; i++) {
			id = advord[i]
			if (!(id in l7v)) cprob("ledger/7.md: no verdict section for " id ", which late/adversary.md gives")
		}
		for (i = 1; i <= advLn; i++) {
			id = advLord[i]
			if (!(id in l7Lseen)) cprob("ledger/7.md: no addition " id ", which late/adversary.md raises")
		}
		for (i = 1; i <= l7Ln; i++) {
			id = l7Lord[i]
			if (!(id in advL)) cprob("ledger/7.md: addition " id " is not in late/adversary.md")
			if (id in carset) cprob("ledger/7.md: addition " id " reuses a carried id")
		}
		late_ids()
		for (i = 1; i <= lin; i++)
			if (l7v[liord[i]] == "") cprob("ledger/7.md: no late verdict for " liord[i] ", which late-ids lists")
	}
	# gate.md
	np0 = np
	n = readfile(run "/gate.md", GA)
	ln = 0
	for (i = 1; i <= n; i++) {
		if (trim(GA[i]) == "") continue
		p = index(GA[i], ": ")
		gid = (p > 0 ? substr(GA[i], 1, p - 1) : GA[i])
		ln++
		if (!(gid in guni)) cprob("gate.md:" i ": line for unknown id " gid)
		else if (gid in seenl) cprob("gate.md:" i ": second line for " gid)
		else if (GA[i] != gline[gid]) cprob("gate.md:" i ": '" GA[i] "', expected '" gline[gid] "'")
		else {
			gsn++
			gseq[gsn] = gid
		}
		seenl[gid] = 1
	}
	for (i = 1; i <= gn; i++)
		if (!(gord[i] in seenl)) cprob("gate.md: no line for " gord[i])
	if (np == np0 && gsn == gn)
		for (i = 1; i <= gn; i++)
			if (gseq[i] != gord[i]) {
				cprob("gate.md: the lines are not in the gate output order")
				break
			}
	# converged.md
	n = readfile(run "/converged.md", CA)
	if (n < 0) return
	classify(CA, n)
	nit = 0
	for (i = 1; i <= n; i++) {
		if (K[i] != "H2" || index(CA[i], "## C") != 1) continue
		hd = substr(CA[i], 4)
		p = index(hd, ": ")
		if (p == 0) continue
		hd = substr(hd, 1, p - 1)
		if (hd !~ /^C[0-9]+$/) continue
		if (hd in citem) cprob("converged.md:" i ": duplicate item id " hd)
		citem[hd] = 1
		e = extent(i, n)
		nit++
		na = 0
		ng = 0
		anyc = 0
		abs = ""
		g = ""
		for (j = i + 1; j <= e; j++) {
			if (K[j] != "T") continue
			if (hasp(CA[j], "- absorbs:")) { na++; abs = kv(CA[j], "- absorbs:") }
			else if (hasp(CA[j], "- gate:")) { ng++; g = kv(CA[j], "- gate:") }
		}
		if (na != 1) cprob("converged.md:" i ": " hd " needs exactly one - absorbs: line")
		if (ng != 1) cprob("converged.md:" i ": " hd " needs exactly one - gate: line")
		else if (g != "counts" && g != "provisional") cprob("converged.md:" i ": " hd " gate '" g "' is not counts or provisional")
		cnn = split(abs, a, ",")
		for (k = 1; k <= cnn; k++) {
			id = trim(a[k])
			if (id == "") { if (na == 1) cprob("converged.md:" i ": " hd " has an empty id in its - absorbs: list"); continue }
			if (!(id in guni)) cprob("converged.md:" i ": " hd " absorbs unknown id " id)
			else {
				absn[id]++
				absby[id] = (absby[id] == "" ? hd : absby[id] ", " hd)
				if (gcounts[id]) anyc = 1
			}
		}
		if (ng == 1 && na == 1 && (g == "counts" || g == "provisional")) {
			if (g == "counts" && !anyc) cprob("converged.md:" i ": " hd " gate is counts, but no absorbed id counts")
			if (g == "provisional" && anyc) cprob("converged.md:" i ": " hd " gate is provisional, but an absorbed id counts")
		}
	}
	for (i = 1; i <= gn; i++) {
		id = gord[i]
		if (absn[id] == 0) cprob("converged.md: " id " is in no - absorbs: list")
		else if (absn[id] > 1) cprob("converged.md: " id " is absorbed " absn[id] " times (" absby[id] ")")
	}
}

function finish(   i) {
	for (i = 1; i <= np; i++) print pm[i] > probf
	close(probf)
	if (np > 0) exit 1
	if (op != "check") for (i = 1; i <= no; i++) print out[i]
	exit 0
}

BEGIN {
	run = ENVIRON["LEDGER_RUN"]
	filesf = ENVIRON["LEDGER_FILES"]
	probf = ENVIRON["LEDGER_PROB"]
	okSev["blocker"] = 1; okSev["high"] = 1; okSev["medium"] = 1; okSev["low"] = 1; okSev["note"] = 1
	okLab["verified fact"] = 1; okLab["unverified assumption"] = 1; okLab["convention"] = 1
	okVerdict["survives"] = 1; okVerdict["downgraded"] = 1; okVerdict["reworded"] = 1; okVerdict["dropped"] = 1
	nfl = readfile(filesf, FL)
	if (nfl < 0) nfl = 0
	np = 0
	no = 0
	needinv = (op == "build5" || op == "gate" || op == "check")
	if (needinv) load_inv()
	if (op == "build5" || op == "check") {
		load_sources()
		np_src = np
		build_out()
		# ids the build holds, in ledger order
		for (s_ = 1; s_ <= nsc; s_++) {
			sc_ = scname[s_]
			nb_ = split(L1[sc_] " " Lp[sc_] " " Lt[sc_], tb_, " ")
			for (k_ = 1; k_ <= nb_; k_++) { nbid++; bid[nbid] = tb_[k_] }
		}
	}
	if (op == "build5") finish()
	load_l5()
	load_live()
	if (op == "mandatory") {
		for (i_ = 1; i_ <= l5n; i_++) if (ismand(l5ord[i_])) emit(l5ord[i_])
		for (i_ = 1; i_ <= livn; i_++) emit(liveord[i_])
		finish()
	}
	if (op == "missing") {
		load_resp()
		for (i_ = 1; i_ <= l5n; i_++) if (ismand(l5ord[i_]) && !(l5ord[i_] in prov)) emit(l5ord[i_])
		for (i_ = 1; i_ <= livn; i_++) if (!(liveord[i_] in prov)) emit(liveord[i_])
		finish()
	}
	if (op == "late-ids") {
		load_l6()
		late_ids()
		for (i_ = 1; i_ <= lin; i_++) emit(liord[i_])
		finish()
	}
	if (op == "late-check") {
		load_l6()
		inadv = 1
		load_adv()
		late_ids()
		for (i_ = 1; advok && i_ <= lin; i_++)
			if (!(liord[i_] in advv)) prob("late/adversary.md: no verdict for " liord[i_] ", which late-ids lists")
		for (i_ = 1; i_ <= advn; i_++)
			if (!(advord[i_] in liset)) prob("late/adversary.md:" advline[advord[i_]] ": verdict on " advord[i_] ", which late-ids does not list")
		for (i_ = 1; i_ <= advLn; i_++)
			if (advLord[i_] in carset) prob("late/adversary.md: addition " advLord[i_] " reuses a carried id")
		finish()
	}
	if (op == "seen") {
		load_l6()
		for (i_ = 1; i_ <= l5n; i_++)
			if (!ismand(l5ord[i_]) && !(l5ord[i_] in p6seen)) emit("- " l5ord[i_])
		finish()
	}
	if (op == "gate") {
		load_l6()
		load_l7()
		compute_gate()
		for (i_ = 1; i_ <= gn; i_++) emit(gline[gord[i_]])
		finish()
	}
	# check
	check5()
	if (through >= 6) {
		load_l6()
		load_resp()
		check6()
	}
	if (through >= 7) {
		load_l7()
		if (late == "complete") load_adv()
		compute_gate()
		check7()
	}
	finish()
}
EOF

: > "$tmp/prob"
LEDGER_RUN=$run LEDGER_FILES=$tmp/files.txt LEDGER_PROB=$tmp/prob \
	awk -v op="$op" -v through="${through:-0}" -v tier="$tier" -v stage6="$stage6" -v late="$late" \
	-f "$tmp/ledger.awk" > "$tmp/out" 2> "$tmp/awkerr"
st=$?
if [ "$st" -ne 0 ] && [ "$st" -ne 1 ]; then
	fatal "internal error: $(head -n 1 "$tmp/awkerr")"
fi

if [ -s "$tmp/prob" ]; then
	if [ "$op" = check ] || [ "$op" = late-check ]; then
		cat "$tmp/prob"
	else
		cat "$tmp/prob" >&2
	fi
	exit 1
fi

case $op in
mandatory | missing | late-ids) sort -u "$tmp/out" ;;
build5 | seen | gate) cat "$tmp/out" ;;
esac
exit 0
