#!/bin/sh
# handoff.sh: detect, validate, and read a cca handoff file.
#
# Usage:
#   sh handoff.sh detect <file>    exit 0 when the frontmatter has a cca-handoff: key,
#                                  1 when not, 2 when the file is unreadable
#   sh handoff.sh check <file>     validate; print "handoff: ok", exit 0
#   sh handoff.sh claims <file>    validate; print one claim per line, six fields
#                                  separated by one tab: kind, ref, bundle, ticket,
#                                  line, text
#   sh handoff.sh commits <file>   validate; print one commit per line: bundle, sha,
#                                  ticket, line, separated by one tab
#
# The format is defined in skills/cca/handoff.md, which this script follows. On a rule
# failure, check, claims, and commits print one line per error, "handoff <file>:<line>:
# <message>" in line order, print nothing else, and exit 1. Usage errors and an
# unreadable file exit 2.
#
# A UTF-8 byte order mark at the start of line 1 is ignored.
# A claim text over 8000 bytes is a rule failure, since a claim is read as one line.
#
# POSIX sh plus awk; the awk program uses only features that mawk and gawk both accept.
set -u

LC_ALL=C
export LC_ALL

usage() {
	echo "usage: handoff.sh detect|check|claims|commits <file>" >&2
	exit 2
}

[ $# -eq 2 ] || usage
mode=$1
file=$2
case $mode in
detect | check | claims | commits) ;;
*) usage ;;
esac

if [ ! -f "$file" ] || [ ! -r "$file" ]; then
	echo "handoff: cannot read $file" >&2
	exit 2
fi

if [ "$mode" = detect ]; then
	awk '
		BEGIN { st = 0; found = 0 }
		{
			l = $0
			if (NR == 1 && substr(l, 1, 3) == "\357\273\277") l = substr(l, 4)
			if (length(l) > 0 && substr(l, length(l), 1) == "\r") l = substr(l, 1, length(l) - 1)
			if (NR == 1) {
				if (l != "---") exit
				st = 1
				next
			}
			if (l == "---") exit
			if (index(l, "cca-handoff:") == 1) { found = 1; exit }
		}
		END { exit (found ? 0 : 1) }' < "$file"
	exit $?
fi

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/handoff.awk" <<'EOF'
# handoff.awk: parse one handoff on stdin. Variable mode: check, claims, or commits.
# The file name for messages comes from the environment, not from -v, which would
# process backslash escapes.

function trim(s) {
	sub(/^[ ]+/, "", s)
	sub(/[ ]+$/, "", s)
	return s
}

function err(l, msg) {
	nerr++
	eln[nerr] = l
	emsg[nerr] = msg
}

# lastidx(s, t): position of the last occurrence of t in s, 0 when none.
function lastidx(s, t,   p, off, i) {
	p = 0
	off = 0
	while ((i = index(substr(s, off + 1), t)) > 0) {
		p = off + i
		off = p
	}
	return p
}

function valid_sha(s) {
	return (length(s) >= 7 && length(s) <= 40 && s ~ /^[0-9a-f]+$/)
}

function islistkey(k) {
	return (k == "commits" || k == "verified" || k == "options")
}

# keyline(s): the key of a "- key: value" line, else "". Sets kval.
function keyline(s,   c, k) {
	kval = ""
	if (substr(s, 1, 2) != "- ") return ""
	c = index(s, ":")
	if (c < 4) return ""
	k = substr(s, 3, c - 3)
	if (k !~ /^[A-Za-z_][A-Za-z0-9_]*$/) return ""
	if (c < length(s) && substr(s, c + 1, 1) != " ") return ""
	kval = trim(substr(s, c + 1))
	return k
}

function fm_line(s,   c, k, v) {
	if (trim(s) == "") return
	if (s == "---") {
		fm = 3
		if (!fmver) err(ln, "missing frontmatter key 'cca-handoff'")
		if (!fmgen) err(ln, "missing frontmatter key 'generated'")
		return
	}
	c = index(s, ":")
	k = ""
	if (c > 1) k = substr(s, 1, c - 1)
	v = trim(substr(s, c + 1))
	if (k == "cca-handoff") {
		if (fmver) err(ln, "duplicate frontmatter key 'cca-handoff'")
		else if (v != "1") err(ln, "unsupported handoff version")
		fmver = 1
	} else if (k == "generated") {
		if (fmgen) err(ln, "duplicate frontmatter key 'generated'")
		else if (v == "") err(ln, "frontmatter key 'generated' has an empty value")
		fmgen = 1
	} else if (k ~ /^[A-Za-z_][A-Za-z0-9_-]*$/) {
		err(ln, "unknown frontmatter key '" k "'")
	} else {
		err(ln, "unrecognized line")
	}
}

function close_section() {
	finish_item()
	if (sec == 1 && cnt[1] == 0) err(secline[1], "section '## Bundles' needs at least one bundle")
}

function section(nm,   s, k) {
	close_section()
	k = 0
	for (s = 1; s <= 4; s++) if (nsec[s] == nm) k = s
	if (k == 0) {
		err(ln, "unknown section '## " nm "'")
		sec = 9
		return
	}
	if (secline[k] > 0) {
		err(ln, "duplicate section '## " nm "'")
		sec = 9
		return
	}
	if (k < lastsec) err(ln, "section '## " nm "' is out of order")
	else lastsec = k
	secline[k] = ln
	sec = k
}

function bundle_line(s,   c, name, r, p, path, prv, branch, base, bad) {
	cnt[1]++
	bad = "bundle line must be '- <name>: repo <path>; pr <pr>; branch <branch>; base <base>'"
	if (substr(s, 1, 2) != "- ") {
		err(ln, "unrecognized line")
		return
	}
	c = index(s, ":")
	name = ""
	if (c > 3) name = substr(s, 3, c - 3)
	r = substr(s, c + 1)
	if (name == "" || substr(r, 1, 6) != " repo ") {
		err(ln, bad)
		return
	}
	r = substr(r, 7)
	p = lastidx(r, "; base ")
	if (p == 0) { err(ln, bad); return }
	base = trim(substr(r, p + 7))
	r = substr(r, 1, p - 1)
	p = lastidx(r, "; branch ")
	if (p == 0) { err(ln, bad); return }
	branch = trim(substr(r, p + 9))
	r = substr(r, 1, p - 1)
	p = lastidx(r, "; pr ")
	if (p == 0) { err(ln, bad); return }
	prv = trim(substr(r, p + 5))
	path = trim(substr(r, 1, p - 1))
	if (name !~ /^[a-z0-9][a-z0-9._-]*$/) err(ln, "invalid bundle name '" name "'")
	else if (name in BN) err(ln, "duplicate bundle name '" name "'")
	else BN[name] = ln
	if (path == "") err(ln, "bundle line has an empty path")
	if (prv == "") err(ln, "bundle line has an empty pr")
	if (branch == "") err(ln, "bundle line has an empty branch")
	if (base == "") err(ln, "bundle line has an empty base")
}

function open_item(id) {
	finish_item()
	if (sec < 2 || sec > 4) {
		err(ln, "item heading outside Tickets, Decisions, and Raised tickets")
		return
	}
	if (noneseen[sec]) err(ln, "section '## " nsec[sec] "' holds both none and an item")
	ci = ++cnt[sec]
	itemopen = 1
	H[sec, ci] = ln
	ID[sec, ci] = id
	lastk = 0
	curlist = ""
	if (sec == 2) {
		if (id == "") err(ln, "ticket heading has no id")
		else if (id in TID) err(ln, "duplicate ticket id '" id "'")
		else TID[id] = ci
	} else if (sec == 3) {
		if (id !~ /^D[1-9][0-9]*$/) err(ln, "decision heading must be '### D<n>'")
		else if (id in DID) err(ln, "duplicate decision id '" id "'")
		else DID[id] = ci
	} else {
		if (id !~ /^R[1-9][0-9]*$/) err(ln, "raised ticket heading must be '### R<n>'")
		else if (id in RID) err(ln, "duplicate raised ticket id '" id "'")
		else RID[id] = ci
	}
}

function finish_item(   i, k, st) {
	if (!itemopen) return
	itemopen = 0
	for (i = 1; i <= nk[sec]; i++) {
		k = kname[sec, i]
		if (!((sec, ci, k) in P)) err(H[sec, ci], "missing key '" k "'")
		else if (islistkey(k) && listmode[sec, ci, k] == "entries" && EC[sec, ci, k] == 0)
			err(L[sec, ci, k], "key '" k "' has no entries")
	}
	if (sec == 3 && ((sec, ci, "status") in P) && ((sec, ci, "options") in P)) {
		st = P[sec, ci, "status"]
		if ((st == "taken" || st == "default taken") && EC[sec, ci, "options"] > 0 && chosen[ci] == 0)
			err(L[sec, ci, "options"], "status '" st "' with options needs exactly one chosen entry")
	}
}

# bundles_check(v, allownone): validate a bundles value, remember the first bundle and
# the set of bundles for the current item.
function bundles_check(v, allownone,   n, a, i, b, set) {
	if (allownone && v == "none") {
		FB[sec, ci] = "none"
		BS[sec, ci] = ","
		return
	}
	set = ","
	n = split(v, a, ",")
	for (i = 1; i <= n; i++) {
		b = trim(a[i])
		if (b == "") {
			err(ln, "empty bundle name in bundles")
			continue
		}
		if (!(b in BN)) err(ln, "unknown bundle '" b "'")
		else if (index(set, "," b ",") > 0) err(ln, "duplicate bundle '" b "' in bundles")
		if (FB[sec, ci] == "") FB[sec, ci] = b
		set = set b ","
	}
	BS[sec, ci] = set
}

function check_value(k, v,   ok) {
	if (k == "bundles") {
		bundles_check(v, sec == 4)
	} else if (sec == 3 && k == "status") {
		ok = 0
		if (v == "taken" || v == "default taken" || v == "deferred") ok = 1
		else if (substr(v, 1, 12) == "deferred to " && trim(substr(v, 13)) != "") ok = 1
		if (!ok) err(ln, "invalid status '" v "'")
	} else if (sec == 3 && k == "decided_by") {
		ok = 0
		if (v == "not recorded" || v == "checkpoint (recommended option taken)") ok = 1
		else if (substr(v, 1, 8) == "person: " && trim(substr(v, 9)) != "") ok = 1
		else if (substr(v, 1, 6) == "role: " && trim(substr(v, 7)) != "") ok = 1
		if (!ok) err(ln, "invalid decided_by '" v "'")
	} else if (sec == 3 && k == "recorded_at") {
		ok = 0
		if (v == "not recorded") ok = 1
		else if (substr(v, 1, 7) == "commit " && valid_sha(trim(substr(v, 8)))) ok = 1
		else if (substr(v, 1, 4) == "url " && trim(substr(v, 5)) != "") ok = 1
		else if (substr(v, 1, 12) == "checkpoint: " && trim(substr(v, 13)) != "") ok = 1
		if (!ok) err(ln, "invalid recorded_at '" v "'")
	} else if (sec == 4 && k == "rank") {
		if (v !~ /^[1-9][0-9]*$/) err(ln, "rank must be a whole number from 1")
		else if (v in RK) err(ln, "duplicate rank '" v "'")
		else RK[v] = ci
	} else if (sec == 4 && k == "in_bundle_confidence") {
		if (!(v == "include" || v == "lean include" || v == "lean defer" || v == "defer"))
			err(ln, "invalid in_bundle_confidence '" v "'")
	} else if (sec == 4 && k == "ticket") {
		if (v in TID) err(ln, "raised ticket '" v "' is already a ticket id in Tickets")
		else if (v in RTK) err(ln, "duplicate raised ticket '" v "'")
		else RTK[v] = ci
	}
}

function key_line(k, v,   i) {
	curlist = ""
	i = kidx[sec, k]
	if (i == "") {
		err(ln, "unknown key '" k "'")
		return
	}
	if ((sec, ci, k) in P) {
		err(ln, "duplicate key '" k "'")
		return
	}
	if (i < lastk) err(ln, "key '" k "' is out of order")
	else lastk = i
	P[sec, ci, k] = v
	L[sec, ci, k] = ln
	if (islistkey(k)) {
		EC[sec, ci, k] = 0
		if (v == "") {
			listmode[sec, ci, k] = "entries"
			curlist = k
		} else if ((k == "options" && v == "none recorded") || (k != "options" && v == "none")) {
			listmode[sec, ci, k] = "none"
		} else {
			err(ln, "key '" k "' takes entries or " (k == "options" ? "'none recorded'" : "'none'"))
		}
		return
	}
	if (v == "") {
		err(ln, "key '" k "' has an empty value")
		return
	}
	check_value(k, v)
}

function commit_entry(e, kk,   i, b, r, j, sha, text) {
	bad = "commit entry must be '<bundle> <sha>: <text>'"
	i = index(e, " ")
	if (i == 0) { err(ln, bad); return }
	b = substr(e, 1, i - 1)
	r = substr(e, i + 1)
	j = index(r, ":")
	if (j == 0) { err(ln, bad); return }
	sha = substr(r, 1, j - 1)
	text = substr(r, j + 1)
	if (text != "" && substr(text, 1, 1) != " ") { err(ln, bad); return }
	text = trim(text)
	if (text == "") err(ln, "commit entry text is empty")
	if (!valid_sha(sha)) err(ln, "commit sha '" sha "' must be 7 to 40 lowercase hex digits")
	if (!(b in BN)) err(ln, "unknown bundle '" b "'")
	else if (((2, ci, "bundles") in P) && index(BS[2, ci], "," b ",") == 0)
		err(ln, "commit bundle '" b "' is not one of the ticket bundles")
	if ((ci SUBSEP b " " sha) in CK) err(ln, "duplicate commit entry '" b " " sha "'")
	else if (valid_sha(sha)) {
		for (i = 1; i < kk; i++)
			if (CB[ci, i] == b && (index(CS[ci, i], sha) == 1 || index(sha, CS[ci, i]) == 1)) {
				err(ln, "duplicate commit entry '" b " " sha "' (same commit as '" b " " CS[ci, i] "')")
				break
			}
	}
	CK[ci SUBSEP b " " sha] = 1
	CB[ci, kk] = b
	CS[ci, kk] = sha
	CT[ci, kk] = text
	CL[ci, kk] = ln
}

function verified_entry(e, kk,   i, stmt, chk) {
	i = index(e, "; check: ")
	if (i == 0) {
		if (length(e) >= 8 && substr(e, length(e) - 7) == "; check:") err(ln, "verified entry has an empty check")
		else err(ln, "verified entry must be '<statement>; check: <check>'")
		return
	}
	stmt = trim(substr(e, 1, i - 1))
	chk = trim(substr(e, i + 9))
	if (stmt == "") err(ln, "verified entry has an empty statement")
	if (chk == "") err(ln, "verified entry has an empty check")
	V[ci, kk] = e
	VL[ci, kk] = ln
}

function options_entry(e,   body, i, opt, why) {
	if (e == "chosen:" || substr(e, 1, 8) == "chosen: ") {
		if (trim(substr(e, 8)) == "") err(ln, "chosen option is empty")
		chosen[ci]++
		if (chosen[ci] > 1) err(ln, "more than one chosen option")
	} else if (e == "rejected:" || substr(e, 1, 10) == "rejected: ") {
		body = trim(substr(e, 10))
		i = index(body, "; why: ")
		if (i == 0) {
			err(ln, "rejected option must be 'rejected: <option>; why: <reason>'")
		} else {
			opt = trim(substr(body, 1, i - 1))
			why = trim(substr(body, i + 7))
			if (opt == "") err(ln, "rejected option is empty")
			if (why == "") err(ln, "rejected option has an empty reason")
		}
	} else {
		err(ln, "options entry must start with 'chosen: ' or 'rejected: '")
		return
	}
	OJ[ci] = (OJ[ci] == "" ? e : OJ[ci] "; " e)
}

function entry_line(s,   e, kk) {
	if (curlist == "") {
		err(ln, "list entry outside a list key")
		return
	}
	e = trim(substr(s, 5))
	kk = ++EC[sec, ci, curlist]
	if (e == "") {
		err(ln, "empty list entry")
		return
	}
	if (curlist == "commits") commit_entry(e, kk)
	else if (curlist == "verified") verified_entry(e, kk)
	else options_entry(e)
}

function process(s,   k, nm) {
	if (fm == 0) {
		fm = 1
		if (s == "---") return
		err(ln, "missing frontmatter: the first line must be ---")
		fm = 3
	} else if (fm == 1) {
		fm_line(s)
		return
	}
	if (trim(s) == "") return
	if (s ~ /^## /) {
		section(trim(substr(s, 4)))
		return
	}
	if (s ~ /^# /) {
		if (sec == 0 && !title) title = 1
		else err(ln, "title line must appear once, before '## Bundles'")
		return
	}
	if (s ~ /^###( |$)/) {
		open_item(trim(substr(s, 4)))
		return
	}
	if (s == "none" && sec == 1) {
		err(ln, "section '## Bundles' never holds none")
		return
	}
	if (s == "none" && sec >= 2 && sec <= 4 && !noneseen[sec] && cnt[sec] == 0) {
		noneseen[sec] = 1
		return
	}
	if (sec == 1) {
		bundle_line(s)
		return
	}
	if (sec >= 2 && sec <= 4 && itemopen) {
		if (substr(s, 1, 4) == "  - ") {
			entry_line(s)
			return
		}
		k = keyline(s)
		if (k != "") {
			key_line(k, kval)
			return
		}
	}
	err(ln, "unrecognized line")
}

# cl(...): add one claim to the output and check its text against the cap, so the checks
# and the printed claims come from the same pass.
function cl(kind, ref, b, t, l, text) {
	if (length(text) > CLAIM_MAX)
		err(l, "claim text is " length(text) " bytes, over the " CLAIM_MAX "-byte cap")
	# Concatenation, not sprintf: mawk caps a sprintf result at 8192 bytes, and a claim over
	# the cap must still reach the error above rather than abort awk.
	OUT[++nout] = kind "\t" ref "\t" b "\t" t "\t" l "\t" text
}

function ftext(s, i, id) {
	return id ": type " P[s, i, "type"] "; state " P[s, i, "state"] "; iteration " P[s, i, "iteration"] "; owner " P[s, i, "owner"]
}

function build_claims(   i, j, id, b, h, nc, t, opts, db) {
	for (i = 1; i <= cnt[2]; i++) {
		id = ID[2, i]
		b = FB[2, i]
		h = H[2, i]
		cl("status", "tickets/" id "/fields", b, id, h, ftext(2, i, id))
		cl("code", "tickets/" id "/problem", b, id, h, P[2, i, "problem"])
		cl("code", "tickets/" id "/decision", b, id, h, P[2, i, "decision"])
		nc = EC[2, i, "commits"] + 0
		for (j = 1; j <= nc; j++)
			cl("code", "tickets/" id "/commit/" CB[i, j] "/" CS[i, j], CB[i, j], id, CL[i, j], CB[i, j] " " CS[i, j] ": " CT[i, j])
		nc = EC[2, i, "verified"] + 0
		for (j = 1; j <= nc; j++)
			cl("verification", "tickets/" id "/verified/" j, b, id, VL[i, j], V[i, j])
	}
	for (i = 1; i <= cnt[3]; i++) {
		id = ID[3, i]
		t = P[3, i, "ticket"]
		db = "none"
		if (t in TID) db = FB[2, TID[t]]
		else if (t in RTK) db = FB[4, RTK[t]]
		opts = P[3, i, "options"]
		if (EC[3, i, "options"] > 0) opts = OJ[i]
		cl("decision", "decisions/" id, db, t, H[3, i], P[3, i, "decision"] " | rationale: " P[3, i, "rationale"] " | options: " opts " | decided_by: " P[3, i, "decided_by"] " | recorded_at: " P[3, i, "recorded_at"] " | status: " P[3, i, "status"])
	}
	for (i = 1; i <= cnt[4]; i++) {
		id = ID[4, i]
		t = P[4, i, "ticket"]
		b = FB[4, i]
		h = H[4, i]
		cl("scope", "raised/" id, b, t, h, t ": " P[4, i, "summary"] " | rank " P[4, i, "rank"] ", " P[4, i, "in_bundle_confidence"] ": " P[4, i, "reason"])
		cl("status", "raised/" id "/fields", b, t, h, ftext(4, i, t))
	}
}

function print_commits(   i, j, nc) {
	for (i = 1; i <= cnt[2]; i++) {
		nc = EC[2, i, "commits"] + 0
		for (j = 1; j <= nc; j++)
			printf "%s\t%s\t%s\t%s\n", CB[i, j], CS[i, j], ID[2, i], CL[i, j]
	}
}

BEGIN {
	file = ENVIRON["HANDOFF_FILE"]
	CLAIM_MAX = 8000   # the most bytes a claim text may hold; a claim is read as one line
	nsec[1] = "Bundles"
	nsec[2] = "Tickets"
	nsec[3] = "Decisions"
	nsec[4] = "Raised tickets"
	spec[2] = "type state iteration owner bundles problem decision commits verified"
	spec[3] = "ticket decision rationale options decided_by recorded_at status"
	spec[4] = "ticket type state iteration owner bundles summary rank in_bundle_confidence reason"
	for (s = 2; s <= 4; s++) {
		nk[s] = split(spec[s], parts, " ")
		for (i = 1; i <= nk[s]; i++) {
			kname[s, i] = parts[i]
			kidx[s, parts[i]] = i
		}
	}
}

{
	line = $0
	if (NR == 1 && substr(line, 1, 3) == "\357\273\277") line = substr(line, 4)
	n = length(line)
	if (n > 0 && substr(line, n, 1) == "\r") line = substr(line, 1, n - 1)
	ln = NR
	if (index(line, "\t") > 0) err(ln, "tab in line")
	process(line)
}

END {
	last = (NR > 0 ? NR : 1)
	ln = last
	if (fm == 0) err(1, "missing frontmatter: the first line must be ---")
	if (fm == 1) err(last, "frontmatter is not closed")
	close_section()
	for (s = 1; s <= 4; s++)
		if (secline[s] == 0) err(last, "missing section '## " nsec[s] "'")
	for (i = 1; i <= cnt[3]; i++) {
		if (!((3, i, "ticket") in P)) continue
		t = P[3, i, "ticket"]
		if (t == "") continue
		if (!(t in TID) && !(t in RTK))
			err(L[3, i, "ticket"], "ticket '" t "' is not in Tickets or Raised tickets")
	}
	build_claims()
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
			print "handoff " file ":" eln[ord[i]] ": " emsg[ord[i]]
		exit 1
	}
	if (mode == "check") print "handoff: ok"
	else if (mode == "claims") for (i = 1; i <= nout; i++) print OUT[i]
	else print_commits()
	exit 0
}
EOF

HANDOFF_FILE=$file awk -v mode="$mode" -f "$tmp/handoff.awk" < "$file"
rc=$?
exit "$rc"
