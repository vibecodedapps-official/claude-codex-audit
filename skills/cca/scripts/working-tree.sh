#!/bin/sh
# working-tree.sh: build a commit from a repository's working tree, so a run can audit
# uncommitted work, without touching the repository's index, refs, or working tree.
#
# Usage:
#   sh working-tree.sh build <repo>
#   sh working-tree.sh check <repo>
#
# Portability: POSIX sh (dash, bash, Git Bash), and awk in forms mawk and gawk accept.
# Every intermediate goes to a file in one temporary directory, removed on every exit, and
# every git step's exit status is checked.
#
# build: GIT_DIR, GIT_WORK_TREE, and GIT_INDEX_FILE from the caller are unset first, and
# every git call runs with GIT_OPTIONAL_LOCKS=0. The commit is built in a temporary index
# inside the script's own temporary directory, a copy (`cp -p`, so its mtime is kept) of
# the repository's own index, so the tree is what `git add -A && git commit` would make
# from the user's own index, a file staged with `git add -f` despite an ignore rule
# included. Then
# `add -A`, `write-tree`, and `commit-tree` with parent HEAD, which is resolved once,
# first. The git steps that touch the temporary index run with core.splitIndex=false and
# core.untrackedCache=false, so no shared index or cache lands in .git. Author and
# committer are `cca <cca@example.invalid>`, both dates `@946684800 +0000`, the message
# `cca: working tree`, `commit-tree` is passed --no-gpg-sign, and fsmonitor is off, so
# an unchanged working tree and HEAD give the same commit sha. Filters are never
# disabled: the tree holds what the user's own commit would.
#
# Every git call runs with hooks disabled (core.hooksPath is an empty directory in the
# temporary directory), since a hook such as post-index-change could write or reach a
# service. The submodule test reads `git status --porcelain=v2 --no-renames` (git 2.18 or
# later), so a renamed submodule is a type 1 entry like any other, not a type 2 rename.
#
# check: runs the refusal checks below and nothing else. It writes nothing (no temporary
# index, no object) and runs no filter, hook, or program: exit 0 with nothing printed, or
# exit 1 or 2 as `build` does. `build` runs the same checks first.
#
# Refusals: exit 1, on stderr, before any write, one line per reason that holds, in this
# order. A reason that names a path names the first one.
#   working-tree: refused: no HEAD commit
#   working-tree: refused: no index file in <path>
#   working-tree: refused: sparse checkout is on
#   working-tree: refused: sparse checkout is on in <path>
#   working-tree: refused: <n> flagged paths cannot be held at the index version, first <path>
#   working-tree: refused: unmerged paths, first <path>
#   working-tree: refused: submodule <path> has uncommitted changes or untracked files
#   working-tree: refused: untracked nested repository <path>
#   working-tree: refused: Git LFS filter on <path>
#   working-tree: refused: filter '<driver>' runs a program on <path>
#   working-tree: refused: unsupported path (git prints it quoted): <path>
# A flagged path (skip-worktree or assume-unchanged, `ls-files -v` tag S, h, or s) is
# held at its index version: the build copies the index with its flags, so `add -A`
# leaves the entry alone whether the file is edited or missing on disk. Five cases break
# that or cannot be verified, so they are refused: a flagged gitlink hides the submodule
# from the parent's `git status`, so the dirty submodule reason would not see it;
# `write-tree` leaves out an intent-to-add entry; when the path is a directory on disk
# (not a symlink), or a leading component of it is a symlink or anything but a directory,
# `add -A` adds what is on disk and drops the flagged entry; and a path git prints quoted
# cannot be tested on disk, so it is an unverifiable quoted path (a quoted file in a
# checked-out submodule is not refused as a quoted path). A dirty submodule's files, and
# an untracked nested repository's commits, are not in the parent's tree. A filter driver
# with a `clean` or `process` command in any config scope runs a program inside `add -A`,
# which may write or reach a service. A driver with neither key runs nothing, so git
# stores the file as is. Git LFS is always refused. When a filter reason holds,
# `git status` is not run, since it would run the filter, so the two submodule and nested
# repository reasons are then not reported.
# The filter scan covers the top level and then each checked-out submodule (a gitlink whose
# directory holds a .git), depth first, each with its own paths, attributes, and config,
# before any `git status`, which would run a submodule's filter on a modified file. A
# path in a submodule carries its prefix (`sub/x.dat`). One LFS line (the first path found
# overall), and one filter line per driver and repository (its first path).
# Every attribute value is a driver name, `set`, `unset`, and `unspecified` included (a
# string `filter=set` names a driver `set`); one is refused only when its `clean` or
# `process` key is set, as for any driver. A checked-out repository always has an index
# file, and the build copies it, so a top level or checked-out submodule with none is
# refused (`<path>` is `.` for the top level, else the submodule's path): a HEAD-only
# start would restore attributes the scan never saw. Like a filter reason, it skips
# `git status`. It is not checked without a HEAD commit. A submodule path git quotes, at
# any depth, is never scanned, so it is refused as a quoted path (the top level's first
# quoted path first, else the first such submodule, with its prefix) and also skips
# `git status`, which would recurse into it. The sparse checkout check also runs in every
# checked-out submodule: one line, for the first repository in scan order that has it on,
# naming a submodule by its path. So does the flagged path check: the count is summed
# over the repositories, and the first path is the first in scan order, with its prefix.
# After `write-tree`, each flagged path of the top level must be in the tree with the mode
# and object of its entry in the copied index, else exit 2 (`working-tree: flagged path
# <path> is not at its index version in the built tree`); the refusals make this safety
# net unreachable.
#
# Output, exit 0, on stdout:
#   head <sha>
#   parent <sha>
#   tree <sha>
#   untracked <path>          one per untracked, not ignored file, sorted
#   flagged <path>            one per flagged path, held at its index version, in scan
#                             order (the top level, then each checked-out submodule depth
#                             first, each in `ls-files` order), with the submodule prefix
# The only writes outside the temporary directory are the objects `add -A`, `write-tree`,
# and `commit-tree` put in the repository's object store. The commit has no ref.
#
# Exit status (`check` prints nothing on stdout and exits 0 where `build` would build):
#   2  the arguments are wrong, <repo> is not a git work tree, or a git step failed (one
#      line on stderr; nothing is printed on stdout)
#   1  a refusal
#   0  otherwise

set -u

# C collation for sort and awk, on every platform.
LC_ALL=C
export LC_ALL
# No git call takes an optional lock, so none rewrites an index.
GIT_OPTIONAL_LOCKS=0
export GIT_OPTIONAL_LOCKS
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

tmp=$(mktemp -d) || {
	echo "working-tree: cannot create a temporary directory" >&2
	exit 2
}

cleanup() {
	rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 2' HUP INT TERM

# An empty directory for core.hooksPath, so no git call runs a hook of the repository.
nohooks=$tmp/nohooks
mkdir "$nohooks" || {
	echo "working-tree: cannot create a directory in $tmp" >&2
	exit 2
}

die() {
	printf '%s\n' "working-tree: $*" >&2
	exit 2
}

usage() {
	echo "usage: working-tree.sh build <repo>" >&2
	echo "       working-tree.sh check <repo>" >&2
	exit 2
}

tab=$(printf '\t')

# g <git args>: git in the top level, quoting only the paths git must quote.
g() {
	git -c core.quotePath=false -c core.fsmonitor=false -c core.hooksPath="$nohooks" -C "$top" "$@" < /dev/null
}

# gd <dir> <git args>: git in a directory, quoting only the paths git must quote.
gd() {
	gd_dir=$1
	shift
	git -c core.quotePath=false -c core.fsmonitor=false -c core.hooksPath="$nohooks" -C "$gd_dir" "$@" < /dev/null
}

# cfgset <dir> <key>: success when the key is set in any scope of the repository in <dir>.
cfgset() {
	gd "$1" config --get "$2" > /dev/null
	cs_rc=$?
	[ "$cs_rc" -le 1 ] || die "git config failed: $2"
	[ "$cs_rc" -eq 0 ]
}

# index_file <dir>: print the path of the index file of the repository in <dir>, absolute.
index_file() {
	if_p=$(gd "$1" rev-parse --git-path index) || die "git rev-parse failed"
	case $if_p in
	/* | [A-Za-z]:/*) printf '%s\n' "$if_p" ;;
	*) printf '%s\n' "$1/$if_p" ;;
	esac
}

# list_repos <dir> <prefix>: append `<dir><TAB><prefix>` to $tmp/repos for the repository
# in <dir>, then for each checked-out submodule of it (a gitlink whose directory holds a
# .git), depth first, in `ls-files` order. The prefix is the path from the top level, with
# a trailing slash, or empty.
list_repos() {
	printf '%s\t%s\n' "$1" "$2" >> "$tmp/repos"
	lr=$((lr + 1))
	lrf=$tmp/subs.$lr
	gd "$1" ls-files -s > "$lrf.raw" || die "git ls-files failed${2:+ in $2}"
	awk '$1 == "160000" { print substr($0, index($0, "\t") + 1) }' "$lrf.raw" > "$lrf" ||
		die "awk failed"
	while IFS= read -r lrs; do
		case $lrs in
		'"'*)
			# Never scanned, so refused (9), and `git status` is not run.
			printf '%s%s\n' "$2" "$lrs" >> "$tmp/qsubs"
			continue
			;;
		esac
		if [ -e "$1/$lrs/.git" ]; then
			list_repos "$1/$lrs" "$2$lrs/"
		fi
	done < "$lrf"
}

# held_on_disk <dir> <path>: success when `add -A` keeps the flagged <path> of the
# repository in <dir> at its index entry, as far as the disk goes: no leading component is
# a symlink or exists as anything but a directory, and the path is not a directory (a
# symlink is not). A missing component or path is held.
held_on_disk() {
	hd_rest=$2
	hd_pre=$1
	while :; do
		case $hd_rest in
		*/*) ;;
		*) break ;;
		esac
		hd_pre=$hd_pre/${hd_rest%%/*}
		hd_rest=${hd_rest#*/}
		if [ -h "$hd_pre" ] || { [ -e "$hd_pre" ] && [ ! -d "$hd_pre" ]; }; then
			return 1
		fi
	done
	[ -h "$1/$2" ] || [ ! -d "$1/$2" ]
}

# build <build|check> <repo>
build() {
	mode=$1
	repo=$2
	top=$(git -c core.hooksPath="$nohooks" -C "$repo" rev-parse --show-toplevel 2> /dev/null) ||
		die "not a git work tree: $repo"
	r=$tmp/r
	mkdir "$r" || die "cannot create a directory in $tmp"
	n=1
	while [ "$n" -le 9 ]; do
		: > "$r/$n"
		n=$((n + 1))
	done

	# 1. no HEAD commit. The sha is resolved once and used for the parent.
	if ! head=$(g rev-parse --verify -q 'HEAD^{commit}'); then
		head=
		echo "working-tree: refused: no HEAD commit" > "$r/1"
	fi

	# The top level, then each checked-out submodule, depth first.
	: > "$tmp/repos"
	: > "$tmp/qsubs"
	lr=0
	list_repos "$top" ""

	# 2. sparse checkout, in the first repository in scan order that has it on.
	while IFS=$tab read -r rd rp; do
		if [ "$(gd "$rd" config --bool --get core.sparseCheckout 2> /dev/null)" = true ]; then
			sp=${rp%/}
			printf '%s\n' "working-tree: refused: sparse checkout is on${sp:+ in $sp}" > "$r/2"
			break
		fi
	done < "$tmp/repos"

	# 1b. no index file in the top level or a checked-out submodule: a checked-out
	# repository always has one, and the build copies it. Written after the HEAD line, and
	# not checked without a HEAD commit (a new repository has none yet).
	noindex=
	while IFS=$tab read -r rd rp; do
		if [ -n "$head" ] && [ ! -f "$(index_file "$rd")" ]; then
			noindex=1
			ip=${rp%/}
			printf '%s\n' "working-tree: refused: no index file in ${ip:-.}" >> "$r/1"
		fi
	done < "$tmp/repos"

	# 3. skip-worktree or assume-unchanged paths (`ls-files -v` tags S, h, and s) the build
	# cannot hold at the index version, in every repository: a gitlink, an intent-to-add
	# entry, a directory on disk, a leading component on disk that is a symlink or not a
	# directory, or a path git prints quoted, which cannot be tested. An intent-to-add path
	# is one with a `diff-index --cached --name-status` line in the --ita-visible-in-index
	# run or the --ita-invisible-in-index run that the other run lacks; it reads no work
	# tree and runs no filter, and it is read only for a repository with a HEAD commit and
	# a flagged entry whose object is the empty blob. The count is summed, and
	# the first path is the first in scan order. Every flagged path of a submodule goes to
	# $tmp/flagged for the output; the top level's are read from the copied index.
	nflag=0
	firstflag=
	: > "$tmp/flagged"
	while IFS=$tab read -r rd rp; do
		gd "$rd" ls-files -s -v > "$tmp/lsv" || die "git ls-files failed${rp:+ in $rp}"
		# The flagged entries, each line as `ls-files -s -v` prints it:
		# `tag mode sha stage<TAB>path`.
		awk '
			{
				t = substr($0, 1, 1)
				if (t == "S" || t == "h" || t == "s") print
			}
		' "$tmp/lsv" > "$tmp/flagv" || die "awk failed"
		[ -s "$tmp/flagv" ] || continue
		# Every intent-to-add entry has the empty blob as its object (SHA-1 or SHA-256), so
		# a repository without one among its flagged entries needs no `diff-index`.
		: > "$tmp/itai"
		: > "$tmp/itav"
		awk '
			$3 == "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391" ||
			$3 == "473a0f4c3be8a93681a267e3b1e9a7dcda1185436fe141f7749120a303721813" { print; exit }
		' "$tmp/flagv" > "$tmp/emptyb" || die "awk failed"
		if [ -s "$tmp/emptyb" ] && fh=$(gd "$rd" rev-parse --verify -q 'HEAD^{commit}'); then
			gd "$rd" diff-index --cached --name-status --no-renames --ita-invisible-in-index \
				"$fh" -- > "$tmp/itai" || die "git diff-index failed${rp:+ in $rp}"
			gd "$rd" diff-index --cached --name-status --no-renames --ita-visible-in-index \
				"$fh" -- > "$tmp/itav" || die "git diff-index failed${rp:+ in $rp}"
		fi
		# `kind<TAB>path` per flagged entry: g a gitlink, i intent-to-add, else d (test on
		# disk). A path is intent-to-add when a `status<TAB>path` line of one run is not
		# among the other run's lines, in either direction: an entry HEAD lacks prints `A`
		# only when visible; one over a tracked file prints `M` visible and `D` invisible;
		# one over a tracked empty file of the same mode prints only `D`, invisible. A path
		# staged otherwise prints the same line in both runs.
		awk '
			FILENAME == ARGV[1] { inv[$0] = 1; next }
			FILENAME == ARGV[2] {
				vis[$0] = 1
				if (!($0 in inv)) ita[substr($0, index($0, "\t") + 1)] = 1
				next
			}
			!done {
				for (l in inv)
					if (!(l in vis)) ita[substr(l, index(l, "\t") + 1)] = 1
				done = 1
			}
			{
				p = substr($0, index($0, "\t") + 1)
				k = "d"
				if ($2 == "160000") k = "g"
				else if (p in ita) k = "i"
				print k "\t" p
			}
		' "$tmp/itai" "$tmp/itav" "$tmp/flagv" > "$tmp/flags" || die "awk failed"
		while IFS=$tab read -r fk fp; do
			[ -z "$rp" ] || printf '%s%s\n' "$rp" "$fp" >> "$tmp/flagged"
			# A quoted path cannot be tested on disk, so it is not held.
			if [ "$fk" = d ]; then
				case $fp in
				'"'*) ;;
				*) held_on_disk "$rd" "$fp" && continue ;;
				esac
			fi
			[ "$nflag" -gt 0 ] || firstflag=$rp$fp
			nflag=$((nflag + 1))
		done < "$tmp/flags"
	done < "$tmp/repos"
	if [ "$nflag" -gt 0 ]; then
		printf '%s\n' "working-tree: refused: $nflag flagged paths cannot be held at the index version, first $firstflag" > "$r/3"
	fi

	# 4. unmerged paths.
	g ls-files -u > "$tmp/lsu" || die "git ls-files failed"
	awk '{ print substr($0, index($0, "\t") + 1); exit }' "$tmp/lsu" > "$tmp/unmerged" ||
		die "awk failed"
	if [ -s "$tmp/unmerged" ]; then
		IFS= read -r line < "$tmp/unmerged"
		printf '%s\n' "working-tree: refused: unmerged paths, first $line" > "$r/4"
	fi

	# The paths a build would add, and the driver of each, in the top level and then in
	# each checked-out submodule, depth first, so no filter can run in a later step. Quoted
	# paths are refused (9). 7 and 8: Git LFS (the first path found), and a driver whose
	# `clean` or `process` is set, one line per driver and repository, with the first path.
	k=0
	while IFS=$tab read -r rd rp; do
		k=$((k + 1))
		gd "$rd" ls-files --cached --others --exclude-standard > "$tmp/paths.$k" ||
			die "git ls-files failed${rp:+ in $rp}"
		git -c core.quotePath=false -c core.fsmonitor=false -c core.hooksPath="$nohooks" -C "$rd" check-attr --stdin filter \
			< "$tmp/paths.$k" > "$tmp/attr" || die "git check-attr failed${rp:+ in $rp}"
		# `driver<TAB>path` for the first path of each driver, in first-seen order.
		awk '
			{
				n = split($0, f, " ")
				v = f[n]
				if (!(v in seen)) {
					seen[v] = 1
					print v "\t" substr($0, 1, length($0) - length(v) - 10)
				}
			}
		' "$tmp/attr" > "$tmp/drivers" || die "awk failed"
		while IFS=$tab read -r drv p; do
			if [ "$drv" = lfs ]; then
				[ -s "$r/7" ] ||
					printf '%s\n' "working-tree: refused: Git LFS filter on $rp$p" > "$r/7"
			elif cfgset "$rd" "filter.$drv.clean" || cfgset "$rd" "filter.$drv.process"; then
				printf '%s\n' "working-tree: refused: filter '$drv' runs a program on $rp$p" >> "$r/8"
			fi
		done < "$tmp/drivers"
	done < "$tmp/repos"
	paths=$tmp/paths.1

	# 9. a path git prints quoted even with core.quotePath=false: the first in the top
	# level, else the first submodule path quoted inside a checked-out submodule.
	awk '/^"/ { print; exit }' "$paths" > "$tmp/quoted" || die "awk failed"
	[ -s "$tmp/quoted" ] || head -n 1 "$tmp/qsubs" > "$tmp/quoted" || die "head failed"
	if [ -s "$tmp/quoted" ]; then
		IFS= read -r line < "$tmp/quoted"
		printf '%s\n' "working-tree: refused: unsupported path (git prints it quoted): $line" > "$r/9"
	fi

	# 5 and 6. A dirty submodule, and an untracked nested repository. A status would run
	# a filter that a reason above names, or one in a quoted submodule the scan skipped,
	# so it waits for them to be absent.
	if [ ! -s "$r/7" ] && [ ! -s "$r/8" ] && [ -z "$noindex" ] && [ ! -s "$tmp/qsubs" ]; then
		g status --porcelain=v2 --no-renames --untracked-files=all --ignore-submodules=none \
			> "$tmp/status" || die "git status failed"
		awk '
			function rest(s, n,   i) {
				for (i = 0; i < n; i++) sub(/^[^ ]+ /, "", s)
				return s
			}
			$1 == "1" && substr($3, 1, 1) == "S" &&
			    (substr($3, 3, 1) == "M" || substr($3, 4, 1) == "U") {
				if (!sm) { print "S\t" rest($0, 8); sm = 1 }
			}
			$1 == "?" {
				p = substr($0, 3)
				if (substr(p, length(p)) == "/") print "D\t" p
			}
		' "$tmp/status" > "$tmp/special" || die "awk failed"
		while IFS=$tab read -r kind p; do
			if [ "$kind" = S ]; then
				printf '%s\n' "working-tree: refused: submodule $p has uncommitted changes or untracked files" > "$r/5"
			elif [ ! -s "$r/6" ] && [ -e "$top/${p%/}/.git" ]; then
				printf '%s\n' "working-tree: refused: untracked nested repository ${p%/}" > "$r/6"
			fi
		done < "$tmp/special"
	fi

	cat "$r/1" "$r/2" "$r/3" "$r/4" "$r/5" "$r/6" "$r/7" "$r/8" "$r/9" > "$tmp/refusals" ||
		die "cat failed"
	if [ -s "$tmp/refusals" ]; then
		cat "$tmp/refusals" >&2
		exit 1
	fi

	[ "$mode" = build ] || exit 0

	# The build, in a temporary index of its own, a copy of the repository's index. The
	# path is absolute or relative to the repository's directory.
	idx=$tmp/index
	# No shared index and no untracked cache may be written into .git.
	ti='-c core.splitIndex=false -c core.untrackedCache=false'
	cp -p "$(index_file "$top")" "$idx" || die "cannot copy the index"
	# `mode sha<TAB>path` of each flagged path of the top level, from the copied index the
	# tree is built from, checked against the tree after `write-tree` and printed as the
	# top level's `flagged` lines. The refusals (3) should make a mismatch unreachable;
	# this is a safety net.
	GIT_INDEX_FILE=$idx g $ti ls-files -s -v > "$tmp/lsc" || die "git ls-files failed"
	awk '
		{
			t = substr($0, 1, 1)
			if (t == "S" || t == "h" || t == "s")
				print $2 " " $3 "\t" substr($0, index($0, "\t") + 1)
		}
	' "$tmp/lsc" > "$tmp/held" || die "awk failed"
	GIT_INDEX_FILE=$idx g $ti add -A || die "git add failed"
	tree=$(GIT_INDEX_FILE=$idx g $ti write-tree) || die "git write-tree failed"
	if [ -s "$tmp/held" ]; then
		g ls-tree -r "$tree" > "$tmp/lstree" || die "git ls-tree failed"
		# The first recorded path whose `mode sha` the tree does not hold.
		awk '
			NR == FNR {
				i = index($0, "\t")
				want[substr($0, i + 1)] = substr($0, 1, i - 1)
				order[++n] = substr($0, i + 1)
				next
			}
			{
				i = index($0, "\t")
				split(substr($0, 1, i - 1), e, " ")
				have[substr($0, i + 1)] = e[1] " " e[3]
			}
			END {
				for (j = 1; j <= n; j++)
					if (have[order[j]] != want[order[j]]) { print order[j]; exit }
			}
		' "$tmp/held" "$tmp/lstree" > "$tmp/notheld" || die "awk failed"
		if [ -s "$tmp/notheld" ]; then
			IFS= read -r line < "$tmp/notheld"
			die "flagged path $line is not at its index version in the built tree"
		fi
	fi
	commit=$(GIT_AUTHOR_NAME=cca GIT_AUTHOR_EMAIL=cca@example.invalid \
		GIT_AUTHOR_DATE='@946684800 +0000' \
		GIT_COMMITTER_NAME=cca GIT_COMMITTER_EMAIL=cca@example.invalid \
		GIT_COMMITTER_DATE='@946684800 +0000' \
		g -c i18n.commitEncoding=UTF-8 commit-tree --no-gpg-sign \
		"$tree" -p "$head" -m 'cca: working tree') || die "git commit-tree failed"

	g ls-files --others --exclude-standard > "$tmp/untracked" || die "git ls-files failed"
	sort "$tmp/untracked" > "$tmp/untracked.sorted" || die "sort failed"
	{
		echo "head $commit"
		echo "parent $head"
		echo "tree $tree"
		sed 's/^/untracked /' "$tmp/untracked.sorted"
		# The top level's from the copied index, then the submodules' from step 3.
		awk '{ print "flagged " substr($0, index($0, "\t") + 1) }' "$tmp/held" &&
			sed 's/^/flagged /' "$tmp/flagged"
	} > "$tmp/final" || die "cannot write the output"
	cat "$tmp/final"
	exit 0
}

case ${1:-} in
build | check)
	[ $# -eq 2 ] || usage
	build "$1" "$2"
	;;
*) usage ;;
esac
