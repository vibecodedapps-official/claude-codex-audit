#!/bin/sh
# live.sh: validate live check results and keep the run's record of them.
#
# Usage:
#   sh live.sh check <file> <report.md>
#                                  validate a --live file against the report; print
#                                  "live: ok", exit 0
#   sh live.sh import <file> <report.md> <run dir>
#                                  validate a copy and keep it as live/results-<k>.md,
#                                  each result_file copied under live/results-<k>/
#   sh live.sh active <run dir>    list the approvals to record, the findings to carry,
#                                  and the winner of each id, as tab-separated lines
#   sh live.sh carry <run dir> <id>
#                                  copy a finding X<n> or L<n> from its ledger file to
#                                  live/carried/<id>.md
#   sh live.sh assemble <run dir> <entries dir>
#                                  build live/findings.md and live/claims.md
#   sh live.sh retire <run dir> <dest dir> <reason>
#                                  retire every active import and move the derived files
#
# The formats are defined in skills/cca/live.md, which this script follows. check
# prints one line per error, "live <file>:<line>: <message>" in line order, to stdout and
# exits 1; the other modes print their validation and state errors as "live: <message>"
# lines to stdout and exit 1, leaving the record unchanged. Usage errors, an unreadable
# input, a missing sha256sum or shasum, a missing jq (import; active with a stages.json),
# a report without its revision line or heading, and any failed operation print one
# "live: <what failed>" line to stderr and exit 2.
#
# Every write goes through a temp file in the target's directory and a rename. Files are
# read in byte order and results files in numeric order of <k>, so results-10.md follows
# results-9.md.
#
# POSIX sh plus awk; the awk programs use only features that mawk and gawk both accept.
set -u

LC_ALL=C
export LC_ALL

usage() {
	echo "usage: live.sh check <file> <report.md> | import <file> <report.md> <run dir> | active <run dir> | carry <run dir> <id> | assemble <run dir> <entries dir> | retire <run dir> <dest dir> <reason>" >&2
	exit 2
}

fail2() {
	printf '%s\n' "live: $*" >&2
	exit 2
}

[ $# -ge 1 ] || usage
mode=$1
shift
case $mode in
check) [ $# -eq 2 ] || usage ;;
import) [ $# -eq 3 ] || usage ;;
active) [ $# -eq 1 ] || usage ;;
carry) [ $# -eq 2 ] || usage ;;
assemble) [ $# -eq 2 ] || usage ;;
retire) [ $# -eq 3 ] || usage ;;
*) usage ;;
esac

tab=$(printf '\t')
nl='
'
cr=$(printf '\r')

tmp=$(mktemp -d) || fail2 "cannot create a temp directory"
trap 'rm -rf "$tmp"' EXIT

# put <src> <target>: write target through a temp file in its directory and a rename.
put() {
	pd=$(dirname "$2") || fail2 "cannot write $2"
	pt=$(mktemp "$pd/.live.XXXXXX" 2>/dev/null) || fail2 "cannot create a temp file in $pd"
	cp "$1" "$pt" 2>/dev/null || { rm -f "$pt"; fail2 "cannot write $2"; }
	chmod 644 "$pt" 2>/dev/null || { rm -f "$pt"; fail2 "cannot write $2"; }
	mv "$pt" "$2" 2>/dev/null || { rm -f "$pt"; fail2 "cannot write $2"; }
}

# cr_mark <in> <out>: copy <in> with each carriage return turned into \001. Some awks
# (gawk under Git Bash) drop a CR before an LF on reading, so the programs that must see a
# CR read this copy and look for \001.
cr_mark() {
	tr '\r' '\001' < "$1" > "$2" || fail2 "cannot read $1"
}

# ---------------------------------------------------------------------------
# check: the report, and the awk program that validates a live file against it.

# need_sha: sets shacmd, or exits 2 when neither sha256sum nor shasum is found.
need_sha() {
	if command -v sha256sum >/dev/null 2>&1; then
		shacmd=sha256sum
	elif command -v shasum >/dev/null 2>&1; then
		shacmd="shasum -a 256"
	else
		fail2 "no sha256sum or shasum"
	fi
}

# load_report <report>: sets report, run_id, rev_hex, rev_bad.
load_report() {
	report=$1
	if [ ! -f "$report" ] || [ ! -r "$report" ]; then
		fail2 "cannot read $report"
	fi
	need_sha
	first=$(head -n 1 "$report") || fail2 "cannot read $report"
	first=${first%"$cr"}
	case $first in
	"revision: sha256:"*) rev_hex=${first#revision: sha256:} ;;
	*) fail2 "$report has no 'revision: sha256:<hex>' first line" ;;
	esac
	case $rev_hex in
	*[!0-9a-f]*) fail2 "$report has no 'revision: sha256:<hex>' first line" ;;
	esac
	[ "${#rev_hex}" -eq 64 ] || fail2 "$report has no 'revision: sha256:<hex>' first line"
	if run_id=$(awk '
		substr($0, 1, 2) == "# " {
			l = $0
			if (substr(l, length(l), 1) == "\r") l = substr(l, 1, length(l) - 1)
			if (substr(l, 1, 20) == "# cca audit report: ") {
				r = substr(l, 21)
				sub(/[ ]+$/, "", r)
				print r
				f = 1
			}
			exit
		}
		END { exit (f ? 0 : 1) }' "$report"); then
		:
	else
		fail2 "$report has no '# cca audit report: <run-id>' heading"
	fi
	[ -n "$run_id" ] || fail2 "$report has no '# cca audit report: <run-id>' heading"
	tail -n +2 "$report" > "$tmp/body" || fail2 "cannot read $report"
	sum_out=$($shacmd < "$tmp/body") || fail2 "cannot hash $report"
	sum=${sum_out%% *}
	rev_bad=0
	[ "$sum" = "$rev_hex" ] || rev_bad=1
}

write_check_awk() {
	cat > "$tmp/check.awk" <<'EOF'
# check.awk: validate a live file against its report. The first file is the report, the
# second the live file. The names and the report's identity come from the environment,
# not from -v, which would process backslash escapes.

function trim(s) {
	sub(/^[ ]+/, "", s)
	sub(/[ ]+$/, "", s)
	return s
}

function rtrim(s) {
	sub(/[ ]+$/, "", s)
	return s
}

function err(l, msg) {
	nerr++
	eln[nerr] = l
	emsg[nerr] = msg
}

# keyval(l, k): 1 when l is "- <k>: <value>" or "- <k>:", with the value, trailing
# spaces removed, in rv.
function keyval(l, k,   p) {
	p = "- " k ":"
	if (substr(l, 1, length(p)) != p) return 0
	if (length(l) > length(p) && substr(l, length(p) + 1, 1) != " ") return 0
	rv = rtrim(substr(l, length(p) + 2))
	return 1
}

function report_line(s,   l, id) {
	l = s
	if (substr(l, length(l), 1) == "\r") l = substr(l, 1, length(l) - 1)
	if (substr(l, 1, 10) == "#### live ") {
		id = trim(substr(l, 11))
		cur = ""
		if (id != "" && !(id in BLK)) {
			BLK[id] = 1
			cur = id
		}
		return
	}
	if (l ~ /^#+ /) {
		cur = ""
		return
	}
	if (cur == "") return
	if (keyval(l, "query")) {
		if (!(cur in HASQ)) {
			HASQ[cur] = 1
			Q[cur] = rv
		}
	} else if (keyval(l, "env")) {
		if (!(cur in HASE)) {
			HASE[cur] = 1
			E[cur] = rv
		}
	}
}

function fm_line(s,   c, k, v) {
	if (trim(s) == "") return
	if (s == "---") {
		fm = 3
		if (!fmver) err(ln, "missing frontmatter key 'cca-live'")
		if (!fmrun) err(ln, "missing frontmatter key 'run'")
		if (!fmrep) err(ln, "missing frontmatter key 'report'")
		return
	}
	c = index(s, ":")
	k = ""
	if (c > 1) k = substr(s, 1, c - 1)
	v = trim(substr(s, c + 1))
	if (k == "cca-live") {
		if (fmver) err(ln, "duplicate frontmatter key 'cca-live'")
		else if (v != "1") err(ln, "unsupported live version")
		fmver = 1
	} else if (k == "run") {
		if (fmrun) err(ln, "duplicate frontmatter key 'run'")
		else if (v == "") err(ln, "frontmatter key 'run' has an empty value")
		else if (v != run) err(ln, "run '" v "' is not the report's run '" run "'")
		fmrun = 1
	} else if (k == "report") {
		if (fmrep) err(ln, "duplicate frontmatter key 'report'")
		else if (v == "") err(ln, "frontmatter key 'report' has an empty value")
		else if (v != rev) err(ln, "report '" v "' is not the report's revision '" rev "'")
		fmrep = 1
	} else if (k ~ /^[A-Za-z_][A-Za-z0-9_-]*$/) {
		err(ln, "unknown frontmatter key '" k "'")
	} else {
		err(ln, "unrecognized line")
	}
}

function close_entry(   i, k) {
	if (!inent) return
	inent = 0
	for (i = 1; i <= 6; i++) {
		k = kname[i]
		if (k == "env" && !eclaim) continue
		if (k == "result") {
			if (!("result" in HASK) && !("result_file" in HASK))
				err(ehl, "missing key 'result' or 'result_file'")
			continue
		}
		if (!(k in HASK)) err(ehl, "missing key '" k "'")
	}
}

function open_entry(id) {
	close_entry()
	nent++
	inent = 1
	ehl = ln
	eid = id
	eclaim = (substr(id, 1, 6) == "claim ")
	eknown = 0
	lastk = 0
	split("", HASK)
	if (id == "") {
		err(ln, "heading has no id")
		eknown = 0
	} else {
		if (id in SEEN) err(ln, "duplicate id '" id "'")
		SEEN[id] = 1
		if (id in BLK) eknown = 1
		else err(ln, "'" id "' is not a live check of the report")
	}
}

function key_line(k, v,   i, n, parts, up) {
	i = kidx[k]
	if (i == "") {
		err(ln, "unknown key '" k "'")
		return
	}
	if (k in HASK) {
		err(ln, "duplicate key '" k "'")
		return
	}
	if ((k == "result" && ("result_file" in HASK)) || (k == "result_file" && ("result" in HASK))) {
		err(ln, "keys 'result' and 'result_file' are both given")
		return
	}
	HASK[k] = 1
	if (i < lastk) err(ln, "key '" k "' is out of order")
	else lastk = i
	if (k == "env" && !eclaim) {
		err(ln, "key 'env' is not allowed on a finding entry")
		return
	}
	if (v == "") {
		err(ln, "key '" k "' has an empty value")
		return
	}
	if (k == "query") {
		if (eknown && !((eid in HASQ) && v == Q[eid]))
			err(ln, "query does not match the report's query for '" eid "'")
	} else if (k == "env") {
		if (eknown && !((eid in HASE) && v == E[eid]))
			err(ln, "env '" v "' does not match the report's env '" E[eid] "'")
	} else if (k == "approved_at") {
		if (v !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
			err(ln, "approved_at must start with YYYY-MM-DD")
	} else if (k == "result_file") {
		# Only a path under the live file's directory, so a live file cannot send an
		# unrelated file (a key, an .env) to the reviewers. The shell tests the file once
		# the format has no error.
		v = trim(v)
		n = split(v, parts, /[\/\\]/)
		up = 0
		for (i = 1; i <= n; i++) if (parts[i] == "..") up = 1
		if (v ~ /^[\/\\]/ || v ~ /^[A-Za-z]:/ || up)
			err(ln, "result_file '" v "' is not a relative path under the live file's directory")
		else
			print ehl "\t" ln "\t" v > files
	}
}

function live_line(s,   l, n, c, k) {
	l = s
	if (FNR == 1 && substr(l, 1, 3) == "\357\273\277") l = substr(l, 4)
	n = length(l)
	if (n > 0 && substr(l, n, 1) == "\r") l = substr(l, 1, n - 1)
	ln = FNR
	if (index(l, "\t") > 0) err(ln, "tab in line")
	if (fm == 0) {
		fm = 1
		if (l == "---") return
		err(ln, "missing frontmatter: the first line must be ---")
		fm = 3
	} else if (fm == 1) {
		if (substr(l, 1, 3) == "## ") {
			err(ln, "frontmatter is not closed")
			fm = 3
		} else {
			fm_line(l)
			return
		}
	}
	if (trim(l) == "") return
	if (substr(l, 1, 3) == "## ") {
		open_entry(trim(substr(l, 4)))
		return
	}
	if (inent && l ~ /^- [a-z_]+:( |$)/) {
		c = index(l, ":")
		k = substr(l, 3, c - 3)
		keyval(l, k)
		key_line(k, rv)
		return
	}
	err(ln, "unrecognized line")
}

BEGIN {
	name = ENVIRON["LIVE_NAME"]
	run = ENVIRON["LIVE_RUN"]
	rev = ENVIRON["LIVE_REV"]
	files = ENVIRON["LIVE_FILES"]
	kname[1] = "query"
	kname[2] = "env"
	kname[3] = "where"
	kname[4] = "result"
	kname[5] = "approved_by"
	kname[6] = "approved_at"
	for (i = 1; i <= 6; i++) kidx[kname[i]] = i
	# result_file takes result's place: an entry has one of the two.
	kidx["result_file"] = 4
}

FNR == 1 { fidx++ }
fidx == 1 { report_line($0); next }
{ live_line($0) }

END {
	last = (ln > 0 ? ln : 1)
	if (fm == 0) err(1, "missing frontmatter: the first line must be ---")
	if (fm == 1) err(last, "frontmatter is not closed")
	close_entry()
	if (fm == 3 && nent == 0) err(last, "no entries")
	if (nerr > 0) {
		# Insertion sort by line, stable, so messages come out in file order.
		for (i = 1; i <= nerr; i++) ord[i] = i
		for (i = 2; i <= nerr; i++) {
			v = ord[i]
			j = i - 1
			while (j >= 1 && eln[ord[j]] > eln[v]) {
				ord[j + 1] = ord[j]
				j--
			}
			ord[j + 1] = v
		}
		for (i = 1; i <= nerr; i++)
			print "live " name ":" eln[ord[i]] ": " emsg[ord[i]]
		exit 1
	}
	exit 0
}
EOF
}

# run_check <path> <name> <dir>: validate the live file at <path>, naming it <name> in
# the messages, with each result_file taken relative to <dir>. Prints the errors; returns
# 0 when none, 1 when there are errors. Leaves in $tmp/files one line per result_file,
# `<heading line><TAB><line><TAB><path>`. The files are tested only when the format has
# no error, so the lines stay in line order.
run_check() {
	if [ "$rev_bad" = 1 ]; then
		echo "live $report:1: the revision line does not match the SHA-256 of the report body"
		return 1
	fi
	: > "$tmp/files" || fail2 "cannot write a temp file"
	LIVE_NAME=$2 LIVE_RUN=$run_id LIVE_REV="sha256:$rev_hex" LIVE_FILES=$tmp/files awk -f "$tmp/check.awk" "$report" "$1"
	rcc=$?
	[ "$rcc" -le 1 ] || fail2 "awk failed while checking $2"
	[ "$rcc" = 0 ] || return 1
	while IFS=$tab read -r fh fl fp; do
		rp=$3/$fp
		if [ ! -f "$rp" ] || [ ! -r "$rp" ]; then
			printf '%s
' "live $2:$fl: result_file '$fp' is not a readable file"
			rcc=1
		elif [ ! -s "$rp" ]; then
			printf '%s
' "live $2:$fl: result_file '$fp' is empty"
			rcc=1
		fi
	done < "$tmp/files"
	return "$rcc"
}

# ---------------------------------------------------------------------------
# Run state: results files, retirements, derived files.

need_run() {
	run=$1
	[ -d "$run" ] || fail2 "cannot read run directory $run"
	live=$run/live
}

# list_ks: write the numbers <k> of the live/results-<k>.md files, in numeric order, to
# $tmp/all.ks.
list_ks() {
	: > "$tmp/all.raw" || fail2 "cannot write a temp file"
	if [ -d "$live" ]; then
		for lf in "$live"/results-*.md; do
			[ -f "$lf" ] || continue
			lb=${lf##*/}
			lk=${lb#results-}
			lk=${lk%.md}
			case $lk in
			'' | 0* | *[!0-9]*) continue ;;
			esac
			echo "$lk" >> "$tmp/all.raw" || fail2 "cannot write a temp file"
		done
	fi
	sort -n "$tmp/all.raw" > "$tmp/all.ks" || fail2 "cannot sort the results files"
}

# rm_pending: remove what an import left uncommitted: each results-*.md.pending, each
# results-<k>.pending/ directory, and each results-<k>/ directory without its
# results-<k>.md (an import stopped between its two renames).
rm_pending() {
	[ -d "$live" ] || return 0
	for pf in "$live"/results-*.md.pending; do
		[ -e "$pf" ] || continue
		rm -f "$pf" 2>/dev/null || fail2 "cannot remove $pf"
	done
	for pd in "$live"/results-*; do
		[ -d "$pd" ] || continue
		pb=${pd##*/}
		pk=${pb#results-}
		pk=${pk%.pending}
		case $pk in
		'' | 0* | *[!0-9]*) continue ;;
		esac
		if [ "$pb" = "results-$pk.pending" ] || [ ! -e "$live/results-$pk.md" ]; then
			rm -rf "$pd" 2>/dev/null || fail2 "cannot remove $pd"
		fi
	done
}

# read_retired: check live/retired.md; write "R <k>" lines to $tmp/ret.R. Prints the
# errors and returns 1 when a line is not a retirement record.
read_retired() {
	: > "$tmp/ret.R" || fail2 "cannot write a temp file"
	rf=$live/retired.md
	[ -e "$rf" ] || return 0
	if [ ! -f "$rf" ] || [ ! -r "$rf" ]; then
		fail2 "cannot read live/retired.md"
	fi
	cr_mark "$rf" "$tmp/retired.marked"
	RET_OUT=$tmp/ret.R awk '
		BEGIN { out = ENVIRON["RET_OUT"] }
		{
			l = $0
			if (index(l, "\001") > 0 || l !~ /^[1-9][0-9]* retired [^ ]+: ./) {
				print "live: live/retired.md:" NR ": not a retirement record"
				next
			}
			print "R " $1 > out
		}' "$tmp/retired.marked" > "$tmp/rerr" || fail2 "awk failed on live/retired.md"
	if [ -s "$tmp/rerr" ]; then
		cat "$tmp/rerr" || fail2 "cannot read a temp file"
		return 1
	fi
	return 0
}

# derived_check <name>: check live/<name> (findings.md or claims.md); write its "D <id>
# <source>" lines to $tmp/D.<name>. Prints the errors and returns 1 when it is malformed.
derived_check() {
	: > "$tmp/D.$1" || fail2 "cannot write a temp file"
	df=$live/$1
	[ -e "$df" ] || return 0
	if [ ! -f "$df" ] || [ ! -r "$df" ]; then
		fail2 "cannot read live/$1"
	fi
	dnofinal=0
	if [ -s "$df" ]; then
		tail -c 1 "$df" > "$tmp/last" || fail2 "cannot read live/$1"
		cmp -s "$tmp/last" "$tmp/nl"
		crc=$?
		case $crc in
		0) ;;
		1) dnofinal=1 ;;
		*) fail2 "cannot read live/$1" ;;
		esac
	fi
	cr_mark "$df" "$tmp/derived.marked"
	DNAME=$1 DNOFINAL=$dnofinal DOUT=$tmp/D.$1 awk '
		function e(l, m) {
			print "live: live/" name ":" l ": " m "; delete the file to rebuild it"
		}
		function endsec() {
			if (!open) return
			if (nder == 0) e(sechead, "no derivation lines")
			if (!curdup && src != "") print "D\t" id "\t" src > dout
			open = 0
		}
		BEGIN {
			name = ENVIRON["DNAME"]
			dout = ENVIRON["DOUT"]
			nofinal = ENVIRON["DNOFINAL"]
		}
		{
			l = $0
			if (index(l, "\001") > 0) {
				e(NR, "carriage return")
				if (substr(l, length(l), 1) == "\001") l = substr(l, 1, length(l) - 1)
			}
			if (l == "") {
				e(NR, "empty line")
				if (open) pos++
				next
			}
			if (substr(l, 1, 3) == "## ") {
				endsec()
				id = substr(l, 4)
				curdup = 0
				if (id in seen) {
					e(NR, "section \047" id "\047 twice")
					curdup = 1
				}
				seen[id] = 1
				open = 1
				pos = 1
				sechead = NR
				nder = 0
				src = ""
				next
			}
			if (!open) {
				e(NR, "line before the first section")
				next
			}
			pos++
			if (pos == 2) {
				if (substr(l, 1, 10) == "- source: " && length(l) > 10) src = substr(l, 11)
				else e(NR, "line 2 of a section must be \047- source: <source>\047")
			} else if (pos == 3) {
				if (!(substr(l, 1, 11) == "- earlier: " && length(l) > 11))
					e(NR, "line 3 of a section must be \047- earlier: <sources>\047")
			} else {
				nder++
			}
		}
		END {
			if (nofinal == "1") e(NR, "no final newline")
			endsec()
		}' "$tmp/derived.marked" > "$tmp/derr.$1" || fail2 "awk failed on live/$1"
	if [ -s "$tmp/derr.$1" ]; then
		cat "$tmp/derr.$1" || fail2 "cannot read a temp file"
		return 1
	fi
	return 0
}

# verify_copies: for each active import in $tmp/active.ks whose entries have a
# result_file, check that live/results-<k>/SHA256SUMS lists exactly the copies those
# entries imply (<heading line>.txt, in line order) and that each copy matches its hash.
# Prints the errors and returns 1 when one fails.
verify_copies() {
	vbad=0
	while read -r vk; do
		awk '
			{
				l = $0
				if (substr(l, length(l), 1) == "\r") l = substr(l, 1, length(l) - 1)
				if (substr(l, 1, 3) == "## ") { hl = FNR; next }
				if (hl && substr(l, 1, 15) == "- result_file: ") print hl ".txt"
			}' "$live/results-$vk.md" > "$tmp/want" || fail2 "cannot read $live/results-$vk.md"
		[ -s "$tmp/want" ] || continue
		vs=$live/results-$vk/SHA256SUMS
		if [ ! -f "$vs" ]; then
			echo "live: live/results-$vk/SHA256SUMS is missing"
			vbad=1
			continue
		fi
		awk '{ print substr($0, 67) }' "$vs" > "$tmp/got" || fail2 "cannot read $vs"
		if ! cmp -s "$tmp/want" "$tmp/got"; then
			echo "live: live/results-$vk/SHA256SUMS does not list the result files of live/results-$vk.md"
			vbad=1
			continue
		fi
		[ -n "${shacmd:-}" ] || need_sha
		while IFS= read -r vl || [ -n "$vl" ]; do
			vh=${vl%% *}
			vn=${vl#*  }
			vf=$live/results-$vk/$vn
			if [ ! -f "$vf" ]; then
				printf '%s
' "live: live/results-$vk/$vn is missing"
				vbad=1
				continue
			fi
			vo=$($shacmd < "$vf") || fail2 "cannot hash $vf"
			if [ "${vo%% *}" != "$vh" ]; then
				printf '%s
' "live: live/results-$vk/$vn does not match live/results-$vk/SHA256SUMS"
				vbad=1
			fi
		done < "$vs"
	done < "$tmp/active.ks"
	[ "$vbad" = 0 ]
}

# build_state <with approvals 0|1>: read the state under $live and compute, in $tmp,
# active.out (the lines `active` prints) and winners.tsv (id, source, earlier, state, tab
# separated, in winner order). Prints the errors and returns 1 when the retirement
# record or a derived file is malformed. A missing live/ gives empty outputs.
build_state() {
	: > "$tmp/active.out" || fail2 "cannot write a temp file"
	: > "$tmp/winners.tsv" || fail2 "cannot write a temp file"
	[ -e "$live" ] || return 0
	[ -d "$live" ] || fail2 "$live is not a directory"
	printf '\n' > "$tmp/nl" || fail2 "cannot write a temp file"
	bad=0
	read_retired || bad=1
	derived_check findings.md || bad=1
	derived_check claims.md || bad=1
	[ "$bad" = 0 ] || return 1
	: > "$tmp/state.tsv" || fail2 "cannot write a temp file"
	if [ "$1" = 1 ] && [ -e "$run/stages.json" ]; then
		command -v jq >/dev/null 2>&1 || fail2 "jq not found"
		jq -r '.approvals[]? | select(.kind == "live") | .source' "$run/stages.json" > "$tmp/approvals.raw" 2>/dev/null ||
			fail2 "cannot read the approvals in $run/stages.json"
		awk '{ if (substr($0, length($0), 1) == "\r") $0 = substr($0, 1, length($0) - 1); print "A\t" $0 }' "$tmp/approvals.raw" >> "$tmp/state.tsv" ||
			fail2 "awk failed"
	fi
	cat "$tmp/D.findings.md" "$tmp/D.claims.md" >> "$tmp/state.tsv" || fail2 "cannot write a temp file"
	if [ -d "$live/carried" ]; then
		for cf in "$live"/carried/*.md; do
			[ -f "$cf" ] || continue
			cb=${cf##*/}
			printf 'C\t%s\n' "${cb%.md}" >> "$tmp/state.tsv" || fail2 "cannot write a temp file"
		done
	fi
	list_ks
	awk '{ print "K " $0 }' "$tmp/all.ks" > "$tmp/all.K" || fail2 "awk failed"
	cat "$tmp/ret.R" "$tmp/all.K" > "$tmp/combo" || fail2 "cannot write a temp file"
	awk '$1 == "R" { r[$2] = 1; next } !($2 in r) { print $2 }' "$tmp/combo" > "$tmp/active.ks" || fail2 "awk failed"
	verify_copies || return 1
	while read -r ak; do
		awk -v k="$ak" '
			function trim(s) {
				sub(/^[ ]+/, "", s)
				sub(/[ ]+$/, "", s)
				return s
			}
			function flush() {
				if (id != "") print "E\t" k "\t" hl "\t" id "\t" by "\t" at
			}
			{
				l = $0
				if (substr(l, length(l), 1) == "\r") l = substr(l, 1, length(l) - 1)
				if (substr(l, 1, 3) == "## ") {
					flush()
					id = trim(substr(l, 4))
					hl = FNR
					by = ""
					at = ""
					next
				}
				if (id == "") next
				if (substr(l, 1, 15) == "- approved_by: ") by = trim(substr(l, 16))
				else if (substr(l, 1, 15) == "- approved_at: ") at = trim(substr(l, 16))
			}
			END { flush() }' "$live/results-$ak.md" >> "$tmp/state.tsv" || fail2 "cannot read $live/results-$ak.md"
	done < "$tmp/active.ks"
	ST_OUT=$tmp/active.out ST_WIN=$tmp/winners.tsv awk '
		BEGIN {
			FS = "\t"
			out = ENVIRON["ST_OUT"]
			wout = ENVIRON["ST_WIN"]
		}
		$1 == "A" { AP[$2] = 1; next }
		$1 == "D" { DS[$2] = $3; next }
		$1 == "C" { CA[$2] = 1; next }
		$1 == "E" {
			id = $4
			s = "live/results-" $2 ".md:" $3
			if (!(id in CNT)) {
				n++
				ORD[n] = id
				CNT[id] = 0
			}
			CNT[id]++
			SRC[id, CNT[id]] = s
			if (!(s in AP)) {
				na++
				APL[na] = "approve\t" s "\t" id "\t" $5 "\t" $6
			}
			next
		}
		END {
			for (i = 1; i <= na; i++) print APL[i] > out
			for (i = 1; i <= n; i++) {
				id = ORD[i]
				if (id ~ /^X[0-9]+$/ && !(id in CA)) print "carry\t" id "\tledger/6.md" > out
				else if (id ~ /^L[0-9]+$/ && !(id in CA)) print "carry\t" id "\tledger/7.md" > out
			}
			for (i = 1; i <= n; i++) {
				id = ORD[i]
				c = CNT[id]
				w = SRC[id, c]
				e = "none"
				if (c > 1) {
					e = SRC[id, 1]
					for (j = 2; j < c; j++) e = e ", " SRC[id, j]
				}
				if (id in DS) st = (DS[id] == w ? "kept" : "changed")
				else st = "new"
				print "winner\t" id "\t" w "\t" e "\t" st > out
				print id "\t" w "\t" e "\t" st > wout
			}
		}' "$tmp/state.tsv" || fail2 "awk failed"
	return 0
}

# ---------------------------------------------------------------------------
# Modes.

mode_check() {
	[ -f "$1" ] && [ -r "$1" ] || fail2 "cannot read $1"
	load_report "$2"
	write_check_awk
	cdir=$(dirname "$1") || fail2 "cannot read $1"
	if run_check "$1" "$1" "$cdir"; then
		echo "live: ok"
		exit 0
	fi
	exit 1
}

mode_import() {
	file=$1
	need_run "$3"
	[ -f "$file" ] && [ -r "$file" ] || fail2 "cannot read $file"
	# The reconcile after an import runs `active`, which needs jq: without it, keep nothing.
	command -v jq >/dev/null 2>&1 || fail2 "jq not found"
	load_report "$2"
	write_check_awk
	rm_pending
	list_ks
	# State that would stop the reconcile after this import (a malformed record or derived
	# file, a broken result copy) would let each retry commit another import: check first.
	if [ -d "$live" ]; then
		build_state 0 || exit 1
	fi
	hi=$(tail -n 1 "$tmp/all.ks") || fail2 "cannot read a temp file"
	[ -n "$hi" ] || hi=0
	ik=$((hi + 1))
	mkdir -p "$live" 2>/dev/null || fail2 "cannot create $live"
	pend=$live/results-$ik.md.pending
	pdir=$live/results-$ik.pending
	cp "$file" "$pend" 2>/dev/null || fail2 "cannot copy $file to $pend"
	cdir=$(dirname "$file") || fail2 "cannot read $file"
	if run_check "$pend" "$file" "$cdir"; then
		:
	else
		rm -f "$pend" 2>/dev/null || fail2 "cannot remove $pend"
		exit 1
	fi
	# Each result_file is copied to results-<k>/<heading line>.txt, and SHA256SUMS hashes
	# the copies. The copies are tested again, since a file can change after its check.
	if [ -s "$tmp/files" ]; then
		mkdir "$pdir" 2>/dev/null || fail2 "cannot create $pdir"
		: > "$tmp/sums" || fail2 "cannot write a temp file"
		cbad=0
		while IFS=$tab read -r fh fl fp; do
			rp=$cdir/$fp
			cp "$rp" "$pdir/$fh.txt" 2>/dev/null || fail2 "cannot copy $fp to $pdir/$fh.txt"
			if [ ! -s "$pdir/$fh.txt" ]; then
				printf '%s
' "live $file:$fl: result_file '$fp' is empty"
				cbad=1
				continue
			fi
			fs=$($shacmd < "$pdir/$fh.txt") || fail2 "cannot hash $pdir/$fh.txt"
			printf '%s  %s\n' "${fs%% *}" "$fh.txt" >> "$tmp/sums" || fail2 "cannot write a temp file"
		done < "$tmp/files"
		if [ "$cbad" = 1 ]; then
			rm -rf "$pdir" "$pend" 2>/dev/null || fail2 "cannot remove $pdir"
			exit 1
		fi
		cp "$tmp/sums" "$pdir/SHA256SUMS" 2>/dev/null || fail2 "cannot write $pdir/SHA256SUMS"
		[ ! -e "$live/results-$ik" ] || fail2 "$live/results-$ik exists"
		mv "$pdir" "$live/results-$ik" 2>/dev/null || fail2 "cannot rename $pdir"
	fi
	[ ! -e "$live/results-$ik.md" ] || fail2 "$live/results-$ik.md exists"
	mv "$pend" "$live/results-$ik.md" 2>/dev/null || fail2 "cannot rename $pend"
	echo "live: imported live/results-$ik.md"
	exit 0
}

mode_active() {
	need_run "$1"
	if build_state 1; then
		cat "$tmp/active.out" || fail2 "cannot read a temp file"
		exit 0
	fi
	exit 1
}

mode_carry() {
	need_run "$1"
	cid=$2
	case $cid in
	X[1-9]*) ;;
	L[1-9]*) ;;
	*) usage ;;
	esac
	case ${cid#?} in
	*[!0-9]*) usage ;;
	esac
	case $cid in
	X*) cn=6 ;;
	*) cn=7 ;;
	esac
	if [ -e "$live/carried/$cid.md" ]; then
		echo "live: live/carried/$cid.md exists"
		exit 1
	fi
	: > "$tmp/cut" || fail2 "cannot write a temp file"
	lf=$run/ledger/$cn.md
	if [ -e "$lf" ]; then
		[ -f "$lf" ] && [ -r "$lf" ] || fail2 "cannot read $lf"
		CARRY_ID=$cid awk '
			BEGIN { pre = "### " ENVIRON["CARRY_ID"] ": " }
			{
				if (!on && !done && index($0, pre) == 1) {
					on = 1
					print
					next
				}
				if (on) {
					if (substr($0, 1, 3) == "## " || $0 ~ /^### [^ :]+: /) {
						on = 0
						done = 1
						next
					}
					print
				}
			}' "$lf" > "$tmp/cut" || fail2 "cannot read $lf"
	fi
	if [ ! -s "$tmp/cut" ]; then
		echo "live: no block for $cid in ledger/$cn.md"
		exit 1
	fi
	mkdir -p "$live/carried" 2>/dev/null || fail2 "cannot create $live/carried"
	put "$tmp/cut" "$live/carried/$cid.md"
	exit 0
}

mode_assemble() {
	need_run "$1"
	ents=$2
	if ! build_state 0; then
		exit 1
	fi
	: > "$tmp/aerr" || fail2 "cannot write a temp file"
	: > "$tmp/entry-map.tsv" || fail2 "cannot write a temp file"
	if [ -d "$ents" ]; then
		for ef in "$ents"/*.md; do
			[ -f "$ef" ] || continue
			[ -r "$ef" ] || fail2 "cannot read $ef"
			eb=${ef##*/}
			: > "$tmp/entry.id" || fail2 "cannot write a temp file"
			cr_mark "$ef" "$tmp/entry.marked"
			ENTRY_F=$eb ENTRY_ID=$tmp/entry.id awk '
				function e(l, m) { print "live: " f ":" l ": " m }
				BEGIN {
					f = ENVIRON["ENTRY_F"]
					idout = ENVIRON["ENTRY_ID"]
				}
				function trim(s) {
					sub(/^[ ]+/, "", s)
					sub(/[ ]+$/, "", s)
					return s
				}
				NR == 1 {
					l = $0
					if (index(l, "\001") > 0) {
						e(1, "carriage return")
						if (substr(l, length(l), 1) == "\001") l = substr(l, 1, length(l) - 1)
					}
					if (substr(l, 1, 3) != "## " || trim(substr(l, 4)) == "")
						e(1, "first line must be \047## <id>\047")
					else print trim(substr(l, 4)) > idout
					next
				}
				{
					n++
					l = $0
					if (index(l, "\001") > 0) e(NR, "carriage return")
					else if (l == "") e(NR, "empty line")
					else if (substr(l, 1, 3) == "## ") e(NR, "line starts with \047## \047")
					else if (substr(l, 1, 9) == "- source:") e(NR, "line starts with \047- source:\047")
					else if (substr(l, 1, 10) == "- earlier:") e(NR, "line starts with \047- earlier:\047")
				}
				END {
					if (NR == 0) e(1, "first line must be \047## <id>\047")
					if (n == 0) print "live: " f ": no derivation lines"
				}' "$tmp/entry.marked" >> "$tmp/aerr" || fail2 "cannot read $ef"
			eid=
			read -r eid < "$tmp/entry.id" || :
			[ -n "$eid" ] || continue
			prev=$(QID=$eid awk -F '\t' 'BEGIN { q = ENVIRON["QID"] } $1 == q { print $2; exit }' "$tmp/entry-map.tsv") || fail2 "awk failed"
			if [ -n "$prev" ]; then
				echo "live: $eb: '$eid' is also in $prev" >> "$tmp/aerr" || fail2 "cannot write a temp file"
			else
				est=$(QID=$eid awk -F '\t' 'BEGIN { q = ENVIRON["QID"] } $1 == q { print $4; exit }' "$tmp/winners.tsv") || fail2 "awk failed"
				case $est in
				new | changed) ;;
				*) echo "live: $eb: '$eid' is not a new or changed winner" >> "$tmp/aerr" || fail2 "cannot write a temp file" ;;
				esac
				printf '%s\t%s\n' "$eid" "$eb" >> "$tmp/entry-map.tsv" || fail2 "cannot write a temp file"
			fi
		done
	fi
	while IFS=$tab read -r wid wsrc wearlier wstate; do
		if [ "$wstate" != kept ]; then
			wf=$(QID=$wid awk -F '\t' 'BEGIN { q = ENVIRON["QID"] } $1 == q { print $2; exit }' "$tmp/entry-map.tsv") || fail2 "awk failed"
			[ -n "$wf" ] || echo "live: no entry for '$wid'" >> "$tmp/aerr" || fail2 "cannot write a temp file"
		fi
		case $wid in
		X[0-9]* | L[0-9]*)
			if [ ! -f "$live/carried/$wid.md" ]; then
				echo "live: live/carried/$wid.md is missing" >> "$tmp/aerr" || fail2 "cannot write a temp file"
			fi
			;;
		esac
	done < "$tmp/winners.tsv"
	if [ -s "$tmp/aerr" ]; then
		cat "$tmp/aerr" || fail2 "cannot read a temp file"
		exit 1
	fi
	: > "$tmp/new-findings.md" || fail2 "cannot write a temp file"
	: > "$tmp/new-claims.md" || fail2 "cannot write a temp file"
	nf=0
	nc=0
	while IFS=$tab read -r wid wsrc wearlier wstate; do
		case $wid in
		"claim "*)
			dest=$tmp/new-claims.md
			cur=$live/claims.md
			nc=$((nc + 1))
			;;
		*)
			dest=$tmp/new-findings.md
			cur=$live/findings.md
			nf=$((nf + 1))
			;;
		esac
		if [ "$wstate" = kept ]; then
			SECID=$wid awk '
				BEGIN { id = ENVIRON["SECID"] }
				substr($0, 1, 3) == "## " { on = ($0 == "## " id) }
				on { print }' "$cur" >> "$dest" || fail2 "cannot read $cur"
		else
			wf=$(QID=$wid awk -F '\t' 'BEGIN { q = ENVIRON["QID"] } $1 == q { print $2; exit }' "$tmp/entry-map.tsv") || fail2 "awk failed"
			printf '## %s\n- source: %s\n- earlier: %s\n' "$wid" "$wsrc" "$wearlier" >> "$dest" || fail2 "cannot write a temp file"
			awk 'NR > 1 { print }' "$ents/$wf" >> "$dest" || fail2 "cannot read $ents/$wf"
		fi
	done < "$tmp/winners.tsv"
	for an in findings claims; do
		cur=$live/$an.md
		new=$tmp/new-$an.md
		if [ "$an" = findings ]; then cnt=$nf; else cnt=$nc; fi
		if [ "$cnt" -eq 0 ]; then
			if [ -e "$cur" ]; then
				rm -f "$cur" 2>/dev/null || fail2 "cannot remove live/$an.md"
				echo "live: removed live/$an.md"
			else
				echo "live: absent live/$an.md"
			fi
		elif [ -f "$cur" ] && cmp -s "$new" "$cur"; then
			echo "live: kept live/$an.md"
		else
			put "$new" "$cur"
			echo "live: wrote live/$an.md"
		fi
	done
	if [ -e "$ents" ]; then
		rm -rf "$ents" 2>/dev/null || fail2 "cannot remove $ents"
	fi
	exit 0
}

mode_retire() {
	need_run "$1"
	dest=$2
	reason=$3
	case $reason in
	'' | *"$nl"*) fail2 "the reason is empty or has a newline" ;;
	esac
	[ -e "$live" ] || exit 0
	[ -d "$live" ] || fail2 "$live is not a directory"
	if ! read_retired; then
		exit 1
	fi
	rm_pending
	list_ks
	cat "$tmp/ret.R" > "$tmp/combo" || fail2 "cannot write a temp file"
	awk '{ print "K " $0 }' "$tmp/all.ks" >> "$tmp/combo" || fail2 "awk failed"
	awk '$1 == "R" { r[$2] = 1; next } !($2 in r) { print $2 }' "$tmp/combo" > "$tmp/active.ks" || fail2 "awk failed"
	moves=
	for mn in findings.md claims.md carried; do
		[ -e "$live/$mn" ] && moves="$moves $mn"
	done
	if [ ! -s "$tmp/active.ks" ] && [ -z "$moves" ]; then
		exit 0
	fi
	if [ -n "$moves" ]; then
		mkdir -p "$dest" 2>/dev/null || fail2 "cannot create $dest"
		for mn in $moves; do
			[ ! -e "$dest/$mn" ] || fail2 "$dest/$mn exists"
		done
	fi
	if [ -s "$tmp/active.ks" ]; then
		now=$(date -u +%Y-%m-%dT%H:%M:%SZ) || fail2 "cannot read the time"
		: > "$tmp/retired.new" || fail2 "cannot write a temp file"
		if [ -f "$live/retired.md" ]; then
			awk '{ print }' "$live/retired.md" > "$tmp/retired.new" || fail2 "cannot read live/retired.md"
		fi
		while read -r rk; do
			printf '%s retired %s: %s\n' "$rk" "$now" "$reason" >> "$tmp/retired.new" || fail2 "cannot write a temp file"
		done < "$tmp/active.ks"
		put "$tmp/retired.new" "$live/retired.md"
		while read -r rk; do
			echo "live: retired $rk"
		done < "$tmp/active.ks"
	fi
	for mn in $moves; do
		mv "$live/$mn" "$dest/$mn" 2>/dev/null || fail2 "cannot move live/$mn to $dest"
		echo "live: moved live/$mn"
	done
	exit 0
}

case $mode in
check) mode_check "$@" ;;
import) mode_import "$@" ;;
active) mode_active "$@" ;;
carry) mode_carry "$@" ;;
assemble) mode_assemble "$@" ;;
retire) mode_retire "$@" ;;
esac
