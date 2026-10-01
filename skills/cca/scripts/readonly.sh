#!/bin/sh
# readonly.sh: snapshot a git repository's state and check it later for changes, so a
# run can show it left the repository alone.
#
# Usage:
#   sh readonly.sh snapshot <repo> <run dir> <out prefix>
#   sh readonly.sh check <repo> <run dir> <baseline prefix> <ignored base prefix> <out prefix>
#
# Portability: POSIX sh (dash, bash, Git Bash), and awk in forms mawk and gawk accept.
# Every intermediate goes to a temporary file, removed on exit, and every command's exit
# status is checked, so an incomplete collection exits 2.
#
# snapshot: creates <out prefix>.marker (an empty file, written fresh), then writes six
# files, each renamed into place only when every part succeeded. Paths are relative to the
# repository's top level.
# - .status:  git status --porcelain=v2 --branch --untracked-files=all (every status runs
#             with --no-optional-locks, so it does not rewrite the repository's index)
# - .refs:    git for-each-ref
# - .stash:   git stash list
# - .config:  git config --list --local
# - .hashes:  one line per path the status lists as changed (types 1, 2, u) or untracked:
#             `<hash> <path>`, `symlink <target> <path>`, `dir <path>`, or
#             `deleted <path>`. Sorted.
# - .ignored: `<size> <mtime> <path>` per ignored file, excluding .git/ and the run
#             directory when it is inside the repository. Sorted. The mtime has
#             sub-second precision when `stat` gives it (GNU `stat -c`, else BSD
#             `stat -f`, chosen by probing the marker). Otherwise it is whole seconds
#             and every check prints `note mtime precision: seconds`.
# A file that vanishes while the snapshot runs is recorded as absent: left out of
# .ignored, or `deleted <path>` in .hashes.
# A path git prints quoted (one with a double quote, backslash, tab, newline, or other
# control character) is not supported: exit 2 naming it.
#
# check: refuses (exit 2) when <out prefix> equals the baseline or the ignored base
# prefix, is not inside the run directory, or when a baseline file it needs is missing.
# Otherwise it runs snapshot into <out prefix>, then prints one line per difference, in
# this order, each group sorted:
#   blocked <status|stash|config|hashes|refs> <-|+> <line>
#   remote-ref <-|+> <line>
#   ignored <added|deleted|changed> <path>
#   touched <path>
# `-` is a line only in the baseline, `+` a line only now. A refs line whose ref name
# starts with refs/remotes/ is `remote-ref`, any other is `blocked refs`. Ignored files are
# compared with <ignored base prefix>.ignored by path, on size and mtime. `touched` is a
# file newer than <baseline prefix>.marker that is not ignored and not part of a blocked
# line.
#
# Exit status, the first that holds:
#   2  a collection or comparison step failed, or the arguments are wrong (one line on
#      stderr; nothing is printed on stdout)
#   1  a `blocked` line was printed
#   3  only `remote-ref` or `ignored` lines were printed
#   0  otherwise (`touched` lines may be printed)

set -u

# C collation for sort, comm, and awk, on every platform.
LC_ALL=C
export LC_ALL

names='status refs stash config hashes ignored'
out=
tmp=$(mktemp -d) || {
	echo "readonly: cannot create a temporary directory" >&2
	exit 2
}

cleanup() {
	rm -rf "$tmp"
	if [ -n "$out" ]; then
		for n in $names; do
			rm -f "$out.$n.part.$$"
		done
	fi
}
trap cleanup EXIT
trap 'exit 2' HUP INT TERM

die() {
	echo "readonly: $*" >&2
	exit 2
}

usage() {
	echo "usage: readonly.sh snapshot <repo> <run dir> <out prefix>" >&2
	echo "       readonly.sh check <repo> <run dir> <baseline prefix> <ignored base prefix> <out prefix>" >&2
	exit 2
}

# normprefix <prefix>: print the prefix as an absolute path whose directory part is
# normalized with `pwd -P`, even when part of the directory does not exist yet.
normprefix() {
	np_d=$(dirname -- "$1") && np_b=$(basename -- "$1") || return 1
	np_rest=
	while [ ! -d "$np_d" ]; do
		np_rest=/$(basename -- "$np_d")$np_rest
		np_d=$(dirname -- "$np_d") || return 1
	done
	np_n=$(cd "$np_d" && pwd -P) || return 1
	[ "$np_n" = / ] && np_n=
	printf '%s%s/%s\n' "$np_n" "$np_rest" "$np_b"
}

# check_quoted <file>: exit 2 naming the first path git printed quoted.
check_quoted() {
	if [ -s "$1" ]; then
		read -r cq_path < "$1"
		die "unsupported path (git prints it quoted): $cq_path"
	fi
}

# snapshot <repo> <run dir> <out prefix>: sets top, rd, relrun, and statkind for check.
snapshot() {
	repo=$1
	out=$3
	top=$(git -C "$repo" rev-parse --show-toplevel) || die "not a git work tree: $repo"
	top=$(cd "$top" && pwd -P) || die "cannot enter the repository: $repo"
	rd=$(cd "$2" && pwd -P) || die "run directory not found: $2"
	relrun=
	case $rd in
	"$top"/*) relrun=${rd#"$top"/} ;;
	esac

	mkdir -p -- "$(dirname -- "$out")" || die "cannot create the directory for $out"
	# A failed snapshot must not leave files that look complete.
	for n in $names; do
		rm -f "$out.$n"
	done
	rm -f "$out.marker"
	: > "$out.marker" || die "cannot write $out.marker"

	git --no-optional-locks -c core.quotePath=false -C "$top" status --porcelain=v2 --branch \
		--untracked-files=all > "$tmp/status" || die "git status failed"
	git -C "$top" for-each-ref > "$tmp/refs" || die "git for-each-ref failed"
	git -C "$top" stash list > "$tmp/stash" || die "git stash list failed"
	git -C "$top" config --list --local > "$tmp/config" || die "git config failed"

	# The paths the status lists as changed or untracked, one per line, and any that git
	# printed quoted. A rename's old path is only checked.
	BADF=$tmp/bad awk '
		function rest(s, n,   i) {
			for (i = 0; i < n; i++) sub(/^[^ ]+ /, "", s)
			return s
		}
		BEGIN { badf = ENVIRON["BADF"] }
		/^[12u?] / {
			t = substr($0, 1, 1)
			if (t == "?") p = substr($0, 3)
			else if (t == "1") p = rest($0, 8)
			else if (t == "u") p = rest($0, 10)
			else {
				p = rest($0, 9)
				n = index(p, "\t")
				if (n > 0) {
					o = substr(p, n + 1)
					p = substr(p, 1, n - 1)
					if (substr(o, 1, 1) == "\"") print o > badf
				}
			}
			if (substr(p, 1, 1) == "\"") print p > badf
			print p
		}' "$tmp/status" > "$tmp/paths" || die "cannot read the status"
	check_quoted "$tmp/bad"

	while IFS= read -r p; do
		if [ -L "$top/$p" ]; then
			t=$(readlink "$top/$p") || die "readlink failed: $p"
			printf 'symlink %s %s\n' "$t" "$p"
		elif [ -d "$top/$p" ]; then
			printf 'dir %s\n' "$p"
		elif [ -f "$top/$p" ]; then
			if h=$(git -C "$top" hash-object --no-filters -- "$p" 2> /dev/null); then
				printf '%s %s\n' "$h" "$p"
			elif [ -e "$top/$p" ] || [ -L "$top/$p" ]; then
				die "hash-object failed: $p"
			else
				printf 'deleted %s\n' "$p"
			fi
		else
			printf 'deleted %s\n' "$p"
		fi
	done < "$tmp/paths" > "$tmp/hashes.raw"
	sort "$tmp/hashes.raw" > "$tmp/hashes" || die "sort failed"

	# The ignored inventory.
	git --no-optional-locks -c core.quotePath=false -C "$top" status --porcelain=v2 --ignored \
		--untracked-files=all > "$tmp/st.ign" || die "git status --ignored failed"
	BADF=$tmp/bad.ign PRE=${relrun:+$relrun/} awk '
		BEGIN { badf = ENVIRON["BADF"]; pre = ENVIRON["PRE"] }
		/^! / {
			p = substr($0, 3)
			if (substr(p, 1, 1) == "\"") { print p > badf; next }
			if (index(p, ".git/") == 1) next
			if (pre != "" && index(p, pre) == 1) next
			print p
		}' "$tmp/st.ign" > "$tmp/ign.paths" || die "cannot read the ignored status"
	check_quoted "$tmp/bad.ign"
	sort "$tmp/ign.paths" > "$tmp/ign.sorted" || die "sort failed"

	# Probe the stat form once, on the marker.
	statkind=
	v=$(stat -c '%s %.9Y' "$out.marker" 2>/dev/null) &&
		printf '%s\n' "${v#* }" | grep -Eq '^[0-9]+\.[0-9]+$' && statkind=gnu
	if [ -z "$statkind" ]; then
		v=$(stat -f '%z %Fm' "$out.marker" 2>/dev/null) &&
			printf '%s\n' "${v#* }" | grep -Eq '^[0-9]+\.[0-9]+$' && statkind=bsd
	fi
	if [ -z "$statkind" ]; then
		if stat -c '%s %Y' "$out.marker" > /dev/null 2>&1; then
			statkind=gnu-seconds
		elif stat -f '%z %m' "$out.marker" > /dev/null 2>&1; then
			statkind=bsd-seconds
		else
			die "stat gives neither GNU nor BSD output"
		fi
	fi

	if [ -s "$tmp/ign.sorted" ]; then
		tr '\n' '\0' < "$tmp/ign.sorted" > "$tmp/ign.nul" || die "tr failed"
		case $statkind in
		gnu) set -- stat -c '%s %.9Y %n' -- ;;
		bsd) set -- stat -f '%z %Fm %N' -- ;;
		gnu-seconds) set -- stat -c '%s %Y %n' -- ;;
		bsd-seconds) set -- stat -f '%z %m %N' -- ;;
		esac
		if ! (cd "$top" && xargs -0 "$@" < "$tmp/ign.nul" > "$tmp/ign.stat") 2> /dev/null; then
			# A file may vanish between the status and the batch. Retry one path at a
			# time and leave out a path that is gone; fail only for one that exists.
			(
				cd "$top" || exit 1
				while IFS= read -r p; do
					if v=$("$@" "$p" 2> /dev/null); then
						printf '%s\n' "$v"
					elif [ -e "$p" ] || [ -L "$p" ]; then
						exit 1
					fi
				done < "$tmp/ign.sorted"
			) > "$tmp/ign.stat" || die "stat failed on an ignored file"
		fi
		sort "$tmp/ign.stat" > "$tmp/ignored" || die "sort failed"
	else
		: > "$tmp/ignored"
	fi

	for n in $names; do
		cp "$tmp/$n" "$out.$n.part.$$" && mv -f "$out.$n.part.$$" "$out.$n" ||
			die "cannot write $out.$n"
	done
}

# diff_lines <sorted baseline> <sorted now>: write the lines only in the baseline to
# only.base and the lines only now to only.now (both files sorted in the C locale).
diff_lines() {
	comm -23 "$1" "$2" > "$tmp/only.base" || die "comm failed"
	comm -13 "$1" "$2" > "$tmp/only.now" || die "comm failed"
}

# check <repo> <run dir> <baseline prefix> <ignored base prefix> <out prefix>
check() {
	base=$3
	ibase=$4
	for n in status refs stash config hashes; do
		[ -f "$base.$n" ] || die "baseline file missing: $base.$n"
	done
	[ -f "$base.marker" ] || die "baseline file missing: $base.marker"
	[ -f "$ibase.ignored" ] || die "baseline file missing: $ibase.ignored"

	np_out=$(normprefix "$5") || die "cannot resolve $5"
	np_base=$(normprefix "$base") || die "cannot resolve $base"
	np_ibase=$(normprefix "$ibase") || die "cannot resolve $ibase"
	[ "$np_out" != "$np_base" ] || die "out prefix equals the baseline prefix: $5"
	[ "$np_out" != "$np_ibase" ] || die "out prefix equals the ignored base prefix: $5"
	np_run=$(cd "$2" && pwd -P) || die "run directory not found: $2"
	case $np_out in
	"$np_run"/*) ;;
	*) die "out prefix is not inside the run directory: $5" ;;
	esac

	snapshot "$1" "$2" "$5"

	: > "$tmp/blocked"
	: > "$tmp/remote"
	for n in status stash config hashes; do
		sort "$base.$n" > "$tmp/b.sorted" || die "sort failed"
		sort "$out.$n" > "$tmp/n.sorted" || die "sort failed"
		diff_lines "$tmp/b.sorted" "$tmp/n.sorted"
		sed "s/^/blocked $n - /" "$tmp/only.base" >> "$tmp/blocked" || die "sed failed"
		sed "s/^/blocked $n + /" "$tmp/only.now" >> "$tmp/blocked" || die "sed failed"
	done

	sort "$base.refs" > "$tmp/b.sorted" || die "sort failed"
	sort "$out.refs" > "$tmp/n.sorted" || die "sort failed"
	diff_lines "$tmp/b.sorted" "$tmp/n.sorted"
	for sign in - +; do
		if [ "$sign" = - ]; then f=$tmp/only.base; else f=$tmp/only.now; fi
		BLK=$tmp/blocked REM=$tmp/remote awk -v sign="$sign" '
			BEGIN { blk = ENVIRON["BLK"]; rem = ENVIRON["REM"] }
			{
				n = index($0, "\t")
				ref = substr($0, n + 1)
				if (n > 0 && index(ref, "refs/remotes/") == 1) print "remote-ref " sign " " $0 >> rem
				else print "blocked refs " sign " " $0 >> blk
			}' "$f" || die "awk failed"
	done

	# Ignored files, by path, on size and mtime.
	{
		sed 's/^/B /' "$ibase.ignored" && sed 's/^/N /' "$out.ignored"
	} > "$tmp/both" || die "sed failed"
	awk '
		{
			tag = substr($0, 1, 1)
			body = substr($0, 3)
			if (!match(body, /^[^ ]+ [^ ]+ /)) next
			sig = substr(body, 1, RLENGTH - 1)
			path = substr(body, RLENGTH + 1)
			if (tag == "B") base[path] = sig
			else now[path] = sig
		}
		END {
			for (p in now) {
				if (!(p in base)) print "ignored added " p
				else if (base[p] != now[p]) print "ignored changed " p
			}
			for (p in base) if (!(p in now)) print "ignored deleted " p
		}' "$tmp/both" > "$tmp/ignored.diff" || die "awk failed"

	# Touched: newer than the baseline marker, not ignored, not part of a blocked line.
	(cd "$top" && find . -path ./.git -prune -o -type f -newer "$np_base.marker" -print) \
		> "$tmp/found" || die "find failed"
	sed 's|^\./||' "$tmp/found" > "$tmp/found.rel" || die "sed failed"
	PRE=${relrun:+$relrun/} awk '
		BEGIN { pre = ENVIRON["PRE"] }
		{ if (pre != "" && index($0, pre) == 1) next; print }' "$tmp/found.rel" |
		sort > "$tmp/cand" || die "cannot list the files newer than the marker"
	: > "$tmp/touched"
	if [ -s "$tmp/cand" ]; then
		tr '\n' '\0' < "$tmp/cand" > "$tmp/cand.nul" || die "tr failed"
		git -C "$top" check-ignore -z --stdin < "$tmp/cand.nul" > "$tmp/ign.nul" 2> /dev/null
		[ $? -le 1 ] || die "git check-ignore failed"
		tr '\0' '\n' < "$tmp/ign.nul" | sort > "$tmp/cand.ign" || die "check-ignore output failed"
		comm -23 "$tmp/cand" "$tmp/cand.ign" > "$tmp/cand.free" || die "comm failed"
		{
			sed 's/^/B /' "$tmp/blocked" && sed 's/^/C /' "$tmp/cand.free"
		} > "$tmp/both" || die "sed failed"
		awk '
			{
				tag = substr($0, 1, 1)
				body = substr($0, 3)
				if (tag == "B") {
					k = split(body, parts, "\t")
					for (i = 1; i <= k; i++) blocked[++nb] = parts[i]
					next
				}
				for (j = 1; j <= nb; j++) {
					s = blocked[j]
					if (length(s) > length(body) &&
					    substr(s, length(s) - length(body)) == " " body) next
				}
				print "touched " body
			}' "$tmp/both" > "$tmp/touched" || die "awk failed"
	fi

	# Everything collected; print it.
	: > "$tmp/final"
	case $statkind in
	*-seconds) echo "note mtime precision: seconds" > "$tmp/final" ;;
	esac
	for f in blocked remote ignored.diff; do
		sort "$tmp/$f" >> "$tmp/final" || die "sort failed"
	done
	cat "$tmp/touched" >> "$tmp/final" || die "cat failed"
	cat "$tmp/final"
	if [ -s "$tmp/blocked" ]; then
		exit 1
	elif [ -s "$tmp/remote" ] || [ -s "$tmp/ignored.diff" ]; then
		exit 3
	fi
	exit 0
}

case ${1:-} in
snapshot)
	[ $# -eq 4 ] || usage
	snapshot "$2" "$3" "$4"
	;;
check)
	[ $# -eq 6 ] || usage
	check "$2" "$3" "$4" "$5" "$6"
	;;
*) usage ;;
esac
