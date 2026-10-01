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
# repository's top level. Every git call runs with GIT_OPTIONAL_LOCKS=0, so none rewrites
# the repository's index.
# - .status:  git status --porcelain=v2 --branch --untracked-files=all
#             --ignore-submodules=none, without its `# branch.ab` line (that follows the
#             upstream's remote-tracking ref, which .refs records). See nested
#             repositories below.
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
# Nested repositories: a checked-out submodule (a gitlink in the index whose directory has
# a .git) or an untracked directory that has a .git, at any depth. Each one's own status
# lines go into .status with its path from the top level in front of every path, for
# example `1 .M N... 100644 100644 100644 <h> <h> sub/s.txt`, and ` in <path>` after each
# `#` line, for example `# branch.oid <sha> in sub`, which records its HEAD. Its changed
# and untracked files get .hashes entries, and its ignored files go into .ignored, all with
# the prefixed path. A touched file in a nested repository is checked with that
# repository's own `git check-ignore`. Files of a nested repository that are neither
# changed, untracked, nor ignored are not hashed. A gitlink whose directory exists but has
# no .git (a submodule that is not checked out), at any depth, is not inspected by git, so
# every file under it, except any .git, is hashed in .hashes as untracked content, and a
# touched file under it is not passed to `git check-ignore`.
# A repository inside an ignored directory (for example, a linked worktree under an
# ignored `.worktrees/`) is not a nested repository: git lists it as one ignored
# directory, recorded in .ignored by its size and mtime, so only an entry added or
# removed at its top level shows, as `ignored changed`.
# When the repository's core.ignorecase is true, the run directory is matched against the
# top level, and against every path, without regard to case.
#
# check: refuses (exit 2) when <out prefix> has a .. path component, equals the
# baseline or the ignored base prefix, by name or as the same file (`-ef`, so other letters
# on a case-insensitive file system do not pass), is not inside the run directory (a walk
# up from its directory to one that is the same file as the run directory), or when a
# baseline file it needs is missing.
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
# No git call takes an optional lock, so none rewrites an index.
GIT_OPTIONAL_LOCKS=0
export GIT_OPTIONAL_LOCKS

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

# collect <path>: record one repository's state. <path> is `.` for the top level, else the
# nested repository's path from the top level. Appends to $tmp/status (its status lines,
# with the path prefixed), $tmp/paths (the changed and untracked paths, prefixed), and
# $tmp/ign.paths (its ignored files, prefixed), and queues the repositories nested in it
# in $tmp/next and $tmp/nested.
collect() {
	if [ "$1" = . ]; then
		cdir=$top
		cpre=
	else
		cdir=$top/$1
		cpre=$1/
	fi
	# --ignore-submodules=none so a configured `ignore` cannot hide a submodule's changes.
	git -c core.quotePath=false -C "$cdir" status --porcelain=v2 --branch \
		--untracked-files=all --ignore-submodules=none > "$tmp/st.one" < /dev/null ||
		die "git status failed${cpre:+ in $1}"

	# The paths the status lists as changed or untracked, one per line, and any that git
	# printed quoted. A rename's old path is only checked. The status lines are kept with
	# the repository's path in front of each path, and `in <path>` after each `#` line. The
	# `# branch.ab` line is left out: it follows the upstream's remote-tracking ref, which
	# the refs file records. An untracked directory is a nested repository candidate.
	: > "$tmp/dirs"
	BADF=$tmp/bad STF=$tmp/status DIRF=$tmp/dirs PRE=$cpre awk '
		function rest(s, n,   i) {
			for (i = 0; i < n; i++) sub(/^[^ ]+ /, "", s)
			return s
		}
		BEGIN {
			badf = ENVIRON["BADF"]; stf = ENVIRON["STF"]; dirf = ENVIRON["DIRF"]
			pre = ENVIRON["PRE"]
			lab = pre
			sub(/\/$/, "", lab)
		}
		/^# branch\.ab / { next }
		/^# / {
			if (pre != "") print $0 " in " lab >> stf
			else print $0 >> stf
			next
		}
		/^[12u?] / {
			t = substr($0, 1, 1)
			o = ""
			if (t == "?") {
				p = substr($0, 3)
				head = "? "
			} else {
				if (t == "1") n = 8
				else if (t == "u") n = 10
				else n = 9
				p = rest($0, n)
				head = substr($0, 1, length($0) - length(p))
				if (t == "2") {
					k = index(p, "\t")
					if (k > 0) {
						o = substr(p, k + 1)
						p = substr(p, 1, k - 1)
						if (substr(o, 1, 1) == "\"") print o > badf
					}
				}
			}
			if (substr(p, 1, 1) == "\"") print p > badf
			if (o != "") print head pre p "\t" pre o >> stf
			else print head pre p >> stf
			print pre p
			if (t == "?" && substr(p, length(p)) == "/") print pre p >> dirf
		}' "$tmp/st.one" >> "$tmp/paths" || die "cannot read the status"
	check_quoted "$tmp/bad"

	# The ignored inventory.
	git -c core.quotePath=false -C "$cdir" status --porcelain=v2 --ignored \
		--untracked-files=all --ignore-submodules=none > "$tmp/st.ign" < /dev/null ||
		die "git status --ignored failed${cpre:+ in $1}"
	BADF=$tmp/bad.ign PRE=$cpre RUNPRE=${relrun:+$relrun/} IC=$ic awk '
		BEGIN {
			badf = ENVIRON["BADF"]; pre = ENVIRON["PRE"]; rr = ENVIRON["RUNPRE"]
			ic = ENVIRON["IC"]; rrl = tolower(rr)
		}
		/^! / {
			p = substr($0, 3)
			if (substr(p, 1, 1) == "\"") { print p > badf; next }
			if (index(p, ".git/") == 1) next
			p = pre p
			if (rr != "") {
				if (ic == 1) { if (index(tolower(p), rrl) == 1) next }
				else if (index(p, rr) == 1) next
			}
			print p
		}' "$tmp/st.ign" >> "$tmp/ign.paths" || die "cannot read the ignored status"
	check_quoted "$tmp/bad.ign"

	# The nested repositories: a checked-out submodule (a gitlink in the index whose
	# directory has a .git), and an untracked directory that has a .git.
	git -c core.quotePath=false -C "$cdir" ls-files -s > "$tmp/ls" < /dev/null ||
		die "git ls-files failed${cpre:+ in $1}"
	BADF=$tmp/bad PRE=$cpre awk '
		BEGIN { badf = ENVIRON["BADF"]; pre = ENVIRON["PRE"] }
		$1 == "160000" {
			p = substr($0, index($0, "\t") + 1)
			if (substr(p, 1, 1) == "\"") print p > badf
			else print pre p
		}' "$tmp/ls" > "$tmp/gitlinks" || die "cannot read the index"
	check_quoted "$tmp/bad"
	# A gitlink whose directory exists but has no .git (a submodule that is not checked
	# out) is not inspected by git: its files are untracked content, hashed below.
	while IFS= read -r c; do
		if [ -d "$top/$c" ] && [ ! -e "$top/$c/.git" ]; then
			printf '%s\n' "$c" >> "$tmp/uninit"
		fi
	done < "$tmp/gitlinks"
	cat "$tmp/dirs" >> "$tmp/gitlinks" || die "cat failed"
	while IFS= read -r c; do
		c=${c%/}
		if [ -e "$top/$c/.git" ]; then
			printf '%s\n' "$c" >> "$tmp/next"
			printf '%s\n' "$c" >> "$tmp/nested"
		fi
	done < "$tmp/gitlinks"
}

# snapshot <repo> <run dir> <out prefix>: sets top, rd, relrun, and statkind for check.
snapshot() {
	repo=$1
	out=$3
	top=$(git -C "$repo" rev-parse --show-toplevel) || die "not a git work tree: $repo"
	top=$(cd "$top" && pwd -P) || die "cannot enter the repository: $repo"
	rd=$(cd "$2" && pwd -P) || die "run directory not found: $2"
	# A case-insensitive file system keeps the case the caller typed in `pwd -P`, so the
	# run directory is matched against the top level without regard to case.
	ic=0
	if [ "$(git -C "$top" config --bool core.ignorecase 2> /dev/null)" = true ]; then
		ic=1
	fi
	relrun=
	if [ "$ic" = 1 ]; then
		rdl=$(printf '%s' "$rd" | tr 'A-Z' 'a-z') || die "tr failed"
		topl=$(printf '%s' "$top" | tr 'A-Z' 'a-z') || die "tr failed"
		case $rdl in
		"$topl"/*) relrun=$(printf '%s' "$rd" | cut -c "$((${#top} + 2))-") ;;
		esac
	else
		case $rd in
		"$top"/*) relrun=${rd#"$top"/} ;;
		esac
	fi

	mkdir -p -- "$(dirname -- "$out")" || die "cannot create the directory for $out"
	# A failed snapshot must not leave files that look complete.
	for n in $names; do
		rm -f "$out.$n"
	done
	rm -f "$out.marker"
	: > "$out.marker" || die "cannot write $out.marker"

	git -C "$top" for-each-ref > "$tmp/refs" || die "git for-each-ref failed"
	git -C "$top" stash list > "$tmp/stash" || die "git stash list failed"
	git -C "$top" config --list --local > "$tmp/config" || die "git config failed"

	# The top level, then the repositories nested in it, level by level. Nothing past the
	# top level runs when it has no nested repository.
	: > "$tmp/status"
	: > "$tmp/paths"
	: > "$tmp/ign.paths"
	: > "$tmp/nested"
	: > "$tmp/uninit"
	echo . > "$tmp/level"
	while [ -s "$tmp/level" ]; do
		: > "$tmp/next"
		while IFS= read -r rp; do
			collect "$rp"
		done < "$tmp/level"
		sort -u "$tmp/next" > "$tmp/level.new" && mv -f "$tmp/level.new" "$tmp/level" ||
			die "sort failed"
	done
	sort -u "$tmp/nested" > "$tmp/nested.sorted" || die "sort failed"
	# Every file under a submodule that is not checked out, except any .git, is hashed.
	while IFS= read -r u; do
		(cd "$top" && find "$u" -name .git -prune -o \( -type f -o -type l \) -print) >> "$tmp/paths" ||
			die "find failed: $u"
	done < "$tmp/uninit"

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
	# A .. component would let the path resolve to another place once its missing
	# directories exist, past the identity check below. A . component cannot: it never
	# changes the directory, so a relative prefix such as ./x stays allowed.
	case "/$5/" in
	*/../*) die "out prefix has a .. component: $5" ;;
	esac
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
	# The same files under another spelling (case, links) pass the name checks above, so
	# compare by identity too. `-ef` is not in POSIX test, but dash, bash, and macOS sh have it.
	if [ -e "$5.marker" ] && [ "$5.marker" -ef "$base.marker" ]; then
		die "out prefix equals the baseline prefix: $5"
	fi
	if [ -e "$5.ignored" ] && [ "$5.ignored" -ef "$ibase.ignored" ]; then
		die "out prefix equals the ignored base prefix: $5"
	fi
	np_run=$(cd "$2" && pwd -P) || die "run directory not found: $2"
	# Walk up from the out prefix's directory (it may not exist yet; np_out is absolute, so the
	# walk ends at /) to a directory that is the run directory, compared by file identity.
	inside=
	d=$(dirname -- "$np_out")
	while :; do
		if [ -d "$d" ] && [ "$d" -ef "$np_run" ]; then
			inside=1
			break
		fi
		p=$(dirname -- "$d") || die "cannot resolve $5"
		# The top is where dirname stops moving: / for most paths, // for a UNC path.
		[ "$p" = "$d" ] && break
		d=$p
	done
	[ -n "$inside" ] || die "out prefix is not inside the run directory: $5"

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

	# Touched: newer than the baseline marker, not ignored, not part of a blocked line. A
	# .git (a directory, or a submodule's file) is pruned at any depth.
	(cd "$top" && find . -name .git -prune -o -type f -newer "$np_base.marker" -print) \
		> "$tmp/found" || die "find failed"
	sed 's|^\./||' "$tmp/found" > "$tmp/found.rel" || die "sed failed"
	PRE=${relrun:+$relrun/} IC=$ic awk '
		BEGIN { pre = ENVIRON["PRE"]; ic = ENVIRON["IC"]; prel = tolower(pre) }
		{
			if (pre != "") {
				if (ic == 1) { if (index(tolower($0), prel) == 1) next }
				else if (index($0, pre) == 1) next
			}
			print
		}' "$tmp/found.rel" |
		sort > "$tmp/cand" || die "cannot list the files newer than the marker"
	: > "$tmp/touched"
	if [ -s "$tmp/cand" ]; then
		# Each candidate goes to the innermost repository that holds it, as a path
		# relative to that repository: group 0 is the top level, group n the nth line of
		# $tmp/nested.sorted. A path below a nested repository must not reach the top
		# level's check-ignore, which fails on it.
		# A candidate under a submodule that is not checked out reaches no check-ignore:
		# .hashes covers it.
		if [ -s "$tmp/uninit" ]; then
			awk '
				NR == FNR { up[++nu] = $0 "/"; next }
				{
					for (i = 1; i <= nu; i++) if (index($0, up[i]) == 1) next
					print
				}' "$tmp/uninit" "$tmp/cand" > "$tmp/cand.chk" || die "awk failed"
		else
			cp "$tmp/cand" "$tmp/cand.chk" || die "cp failed"
		fi
		if [ -s "$tmp/nested.sorted" ]; then
			awk '
				NR == FNR { np[++nn] = $0 "/"; next }
				{
					best = 0; bl = 0
					for (i = 1; i <= nn; i++)
						if (index($0, np[i]) == 1 && length(np[i]) > bl) { best = i; bl = length(np[i]) }
					print best " " substr($0, bl + 1)
				}' "$tmp/nested.sorted" "$tmp/cand.chk" > "$tmp/groups" || die "awk failed"
		else
			sed 's/^/0 /' "$tmp/cand.chk" > "$tmp/groups" || die "sed failed"
		fi
		: > "$tmp/cand.ign"
		g=0
		ng=$(wc -l < "$tmp/nested.sorted") || die "wc failed"
		ng=$((ng + 0))
		while [ "$g" -le "$ng" ]; do
			if [ "$g" -eq 0 ]; then
				gdir=$top
				gpre=
			else
				gp=$(sed -n "${g}p" "$tmp/nested.sorted") || die "sed failed"
				gdir=$top/$gp
				gpre=$gp/
			fi
			awk -v g="$g" '{
				s = index($0, " ")
				if (substr($0, 1, s - 1) == g) print substr($0, s + 1)
			}' "$tmp/groups" > "$tmp/group" || die "awk failed"
			if [ -s "$tmp/group" ]; then
				tr '\n' '\0' < "$tmp/group" > "$tmp/cand.nul" || die "tr failed"
				git -C "$gdir" check-ignore -z --stdin < "$tmp/cand.nul" > "$tmp/ign.nul" 2> /dev/null
				[ $? -le 1 ] || die "git check-ignore failed"
				tr '\0' '\n' < "$tmp/ign.nul" |
					PRE=$gpre awk '{ print ENVIRON["PRE"] $0 }' >> "$tmp/cand.ign" ||
					die "check-ignore output failed"
			fi
			g=$((g + 1))
		done
		sort "$tmp/cand.ign" > "$tmp/cand.ign.sorted" || die "sort failed"
		comm -23 "$tmp/cand" "$tmp/cand.ign.sorted" > "$tmp/cand.free" || die "comm failed"
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
