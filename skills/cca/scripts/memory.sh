#!/bin/sh
# memory.sh: list the memory files that mention a claim the audit found false.
#
# Usage:
#   sh memory.sh find <claims-verdicts.md> <dir>
#
# Reads the false entries of a claims-verdicts.md (LF or CRLF; format in
# skills/cca/stages/8-report.md): an entry is a main line starting "- claim <n> " with its
# two-space sub-lines, and it is false when the main line holds ": false; finding: ".
# For each false entry the keys are, in order, each once:
#   1. the "ticket:" sub-line value with a leading "github:" removed, unless none or absent
#      (a file from 0.2.0 has no such sub-line);
#   2. each non-empty span of the "text:" value between two backticks or two double quotes,
#      unless it holds a tab (a tab would split the output line);
#   3. each word of the text outside those spans, stripped of leading ([{< and trailing
#      .,;:!?)]}>, that is a number (1, 104, 1,000, 4.2), a sha (7 to 40 lowercase hex
#      digits), or an id (APP-1, #12, AB#4567, owner/app#12). Nothing else is a key.
#
# Files read: every regular file under <dir> at any depth, outside any .git, that holds no
# NUL byte (a binary file is skipped), found with find and sorted in the C locale. A file
# holds a key when one of its lines contains the key, compared literally, with neither a
# letter nor a digit right before or after it, so APP-1 does not match APP-10 and 1 does
# not match 12. A path that holds a newline is not supported.
#
# Output, one line per match, three fields separated by one tab: "claim <n>", the key, and
# the file path (<dir> as given, without trailing slashes, then the path below it), or
# "none" when no file holds the key. A false entry with no key prints "claim <n>", "-",
# "no key". Other entries print nothing. Exit 0; exit 2 on a usage error, an unreadable
# file, or a missing directory, with nothing on stdout.
#
# POSIX sh plus awk; the awk program uses only features that mawk, gawk, and BSD awk all
# accept, and builds long strings by concatenation.
set -u

LC_ALL=C
export LC_ALL

usage() {
	echo "usage: memory.sh find <claims-verdicts.md> <dir>" >&2
	exit 2
}

[ $# -eq 3 ] || usage
[ "$1" = find ] || usage
verdicts=$2
dir=$3

if [ ! -f "$verdicts" ] || [ ! -r "$verdicts" ]; then
	echo "memory: cannot read $verdicts" >&2
	exit 2
fi
if [ ! -d "$dir" ] || [ ! -r "$dir" ]; then
	echo "memory: cannot read directory $dir" >&2
	exit 2
fi

# Trailing slashes off the directory, but keep a lone /.
while [ "${dir#?}" != "" ] && [ "${dir%/}" != "$dir" ]; do
	dir=${dir%/}
done

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

find "$dir" -name .git -prune -o -type f -print > "$tmp/found" || {
	echo "memory: cannot read directory $dir" >&2
	exit 2
}
sort "$tmp/found" > "$tmp/all" || exit 2

: > "$tmp/list"
while IFS= read -r f; do
	if [ ! -r "$f" ]; then
		echo "memory: cannot read $f" >&2
		exit 2
	fi
	if tr -d '\000' < "$f" | cmp -s - "$f"; then
		printf '%s\n' "$f" >> "$tmp/list"
	fi
done < "$tmp/all"

cat > "$tmp/memory.awk" <<'EOF'
# memory.awk: read the verdicts file and the list of memory files named in the environment
# (MEMORY_VERDICTS, MEMORY_LIST), and print the matches.

function trim(s) {
	sub(/^[ \t]+/, "", s)
	sub(/[ \t\r]+$/, "", s)
	return s
}

function addkey(k) {
	if (k == "" || (k in seen) || index(k, "\t") > 0) return
	seen[k] = 1
	nkeys++
	ekey[nkeys] = k
}

function alnum_at(s, p,   c) {
	if (p < 1) return 0
	c = substr(s, p, 1)
	return (c ~ /^[A-Za-z0-9]$/)
}

# holds(line, key): 1 when line contains key with no letter or digit on either side.
function holds(line, key,   off, i, p, kl) {
	kl = length(key)
	off = 0
	while ((i = index(substr(line, off + 1), key)) > 0) {
		p = off + i
		if (!alnum_at(line, p - 1) && !alnum_at(line, p + kl)) return 1
		off = p
	}
	return 0
}

function iskey(w,   n) {
	n = length(w)
	if (w ~ /^[0-9]+([.,][0-9]+)*$/) return 1
	if (n >= 7 && n <= 40 && w ~ /^[0-9a-f]+$/) return 1
	if (w ~ /^[A-Za-z][A-Za-z0-9_]*-[0-9]+$/) return 1
	if (w ~ "^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?[A-Za-z]*#[0-9]+$") return 1
	return 0
}

# textkeys(t): add the keys of a text value, quoted spans first, then words.
function textkeys(t,   rest, outside, b, d, p, q, after, j, span, nw, i, w) {
	rest = t
	outside = ""
	while (rest != "") {
		b = index(rest, "`")
		d = index(rest, "\"")
		if (b == 0 || (d > 0 && d < b)) {
			p = d
			q = "\""
		} else {
			p = b
			q = "`"
		}
		if (p == 0) {
			outside = outside rest
			break
		}
		after = substr(rest, p + 1)
		j = index(after, q)
		if (j == 0) {
			# An unpaired quote mark is an ordinary character.
			outside = outside substr(rest, 1, p)
			rest = after
			continue
		}
		outside = outside substr(rest, 1, p - 1) " "
		span = substr(after, 1, j - 1)
		if (span != "") addkey(span)
		rest = substr(after, j + 1)
	}
	nw = split(outside, W, " ")
	for (i = 1; i <= nw; i++) {
		w = W[i]
		while (w != "" && index("([{<", substr(w, 1, 1)) > 0) w = substr(w, 2)
		while (w != "" && index(".,;:!?)]}>", substr(w, length(w), 1)) > 0)
			w = substr(w, 1, length(w) - 1)
		if (w != "" && iskey(w)) addkey(w)
	}
}

function finish_entry(   k, i) {
	if (!inent) return
	inent = 0
	if (!isfalse) return
	split("", seen)
	nkeys = 0
	k = trim(eticket)
	if (substr(k, 1, 7) == "github:") k = trim(substr(k, 8))
	if (k != "" && k != "none") addkey(k)
	textkeys(etext)
	if (nkeys == 0) {
		nout++
		oclaim[nout] = eclaim
		okey[nout] = ""
		return
	}
	for (i = 1; i <= nkeys; i++) {
		nout++
		oclaim[nout] = eclaim
		okey[nout] = ekey[i]
		if (!(ekey[i] in uidx)) {
			nu++
			uidx[ekey[i]] = nu
			ukey[nu] = ekey[i]
			nhit[nu] = 0
			last[nu] = 0
		}
	}
}

BEGIN {
	vf = ENVIRON["MEMORY_VERDICTS"]
	lf = ENVIRON["MEMORY_LIST"]
	inent = 0
	while ((r = (getline line < vf)) > 0) {
		if (substr(line, length(line), 1) == "\r") line = substr(line, 1, length(line) - 1)
		if (substr(line, 1, 8) == "- claim ") {
			finish_entry()
			rest = substr(line, 9)
			sp = index(rest, " ")
			num = (sp > 0) ? substr(rest, 1, sp - 1) : ""
			if (num ~ /^[0-9]+$/) {
				inent = 1
				eclaim = num
				isfalse = (index(line, ": false; finding: ") > 0)
				eticket = ""
				haveticket = 0
				etext = ""
				havetext = 0
			}
		} else if (inent && substr(line, 1, 2) == "  ") {
			s = substr(line, 3)
			if (!haveticket && substr(s, 1, 7) == "ticket:") {
				haveticket = 1
				eticket = substr(s, 8)
			} else if (!havetext && substr(s, 1, 5) == "text:") {
				havetext = 1
				etext = substr(s, 6)
			}
		} else {
			finish_entry()
		}
	}
	if (r < 0) {
		print "memory: cannot read " vf > "/dev/stderr"
		exit 2
	}
	close(vf)
	finish_entry()

	nf = 0
	while ((r = (getline path < lf)) > 0) {
		nf++
		fidx = nf
		while ((r2 = (getline line < path)) > 0) {
			for (u = 1; u <= nu; u++) {
				if (last[u] == fidx) continue
				if (holds(line, ukey[u])) {
					last[u] = fidx
					nhit[u]++
					hit[u, nhit[u]] = path
				}
			}
		}
		if (r2 < 0) {
			print "memory: cannot read " path > "/dev/stderr"
			exit 2
		}
		close(path)
	}
	if (r < 0) {
		print "memory: cannot read " lf > "/dev/stderr"
		exit 2
	}

	for (o = 1; o <= nout; o++) {
		if (okey[o] == "") {
			print "claim " oclaim[o] "\t-\tno key"
			continue
		}
		u = uidx[okey[o]]
		if (nhit[u] == 0) {
			print "claim " oclaim[o] "\t" okey[o] "\tnone"
			continue
		}
		for (i = 1; i <= nhit[u]; i++)
			print "claim " oclaim[o] "\t" okey[o] "\t" hit[u, i]
	}
	exit 0
}
EOF

MEMORY_VERDICTS=$verdicts MEMORY_LIST=$tmp/list awk -f "$tmp/memory.awk" > "$tmp/out"
rc=$?
if [ "$rc" -ne 0 ]; then
	exit "$rc"
fi
cat "$tmp/out"
exit 0
