#!/bin/sh
# working-tree.sh: build a commit from a repository's working tree, so a run can audit
# uncommitted work, without touching the repository's index, refs, or working tree.
#
# Usage:
#   sh working-tree.sh build <repo>
#
# Portability: POSIX sh (dash, bash, Git Bash), and awk in forms mawk and gawk accept.
# Every intermediate goes to a file in one temporary directory, removed on every exit, and
# every git step's exit status is checked.
#
# build: GIT_DIR, GIT_WORK_TREE, and GIT_INDEX_FILE from the caller are unset first, and
# every git call runs with GIT_OPTIONAL_LOCKS=0. The commit is built in a temporary index
# inside the script's own temporary directory: `read-tree HEAD`, `add -A`, `write-tree`,
# then `commit-tree` with parent HEAD, which is resolved once, first. Author and committer
# are `cca <cca@example.invalid>`, both dates `@946684800 +0000`, the message
# `cca: working tree`, `commit-tree` is passed --no-gpg-sign, and fsmonitor is off, so an
# unchanged working tree and HEAD give the same commit sha. Filters are never disabled:
# the tree holds what the user's own commit would.
#
# Refusals: exit 1, on stderr, before any write, one line per reason that holds, in this
# order. A reason that names a path names the first one.
#   working-tree: refused: no HEAD commit
#   working-tree: refused: sparse checkout is on
#   working-tree: refused: <n> paths are skip-worktree or assume-unchanged, first <path>
#   working-tree: refused: unmerged paths, first <path>
#   working-tree: refused: submodule <path> has uncommitted changes or untracked files
#   working-tree: refused: untracked nested repository <path>
#   working-tree: refused: Git LFS filter on <path>
#   working-tree: refused: filter '<driver>' runs a program on <path>
#   working-tree: refused: unsupported path (git prints it quoted): <path>
# A skip-worktree path missing on disk would read as a deletion. A dirty submodule's
# files, and an untracked nested repository's commits, are not in the parent's tree. A
# filter driver with a `clean` or `process` command in any config scope runs a program
# inside `add -A`, which may write or reach a service. A driver with neither key runs
# nothing, so git stores the file as is. Git LFS is always refused. When a filter reason
# holds, `git status` is not run, since it would run the filter, so the two submodule and
# nested repository reasons are then not reported.
#
# Output, exit 0, on stdout:
#   head <sha>
#   parent <sha>
#   tree <sha>
#   untracked <path>          one per untracked, not ignored file, sorted
# The only writes outside the temporary directory are the objects `add -A`, `write-tree`,
# and `commit-tree` put in the repository's object store. The commit has no ref.
#
# Exit status:
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

die() {
	printf '%s\n' "working-tree: $*" >&2
	exit 2
}

usage() {
	echo "usage: working-tree.sh build <repo>" >&2
	exit 2
}

tab=$(printf '\t')

# g <git args>: git in the top level, quoting only the paths git must quote.
g() {
	git -c core.quotePath=false -c core.fsmonitor=false -C "$top" "$@" < /dev/null
}

# cfgset <key>: success when the key is set in any scope.
cfgset() {
	g config --get "$1" > /dev/null
	cs_rc=$?
	[ "$cs_rc" -le 1 ] || die "git config failed: $1"
	[ "$cs_rc" -eq 0 ]
}

build() {
	repo=$1
	top=$(git -C "$repo" rev-parse --show-toplevel 2> /dev/null) ||
		die "not a git work tree: $repo"
	r=$tmp/r
	mkdir "$r" || die "cannot create a directory in $tmp"
	n=1
	while [ "$n" -le 9 ]; do
		: > "$r/$n"
		n=$((n + 1))
	done

	# 1. no HEAD commit. The sha is resolved once and used for the parent and read-tree.
	if ! head=$(g rev-parse --verify -q 'HEAD^{commit}'); then
		head=
		echo "working-tree: refused: no HEAD commit" > "$r/1"
	fi

	# 2. sparse checkout.
	if [ "$(g config --bool --get core.sparseCheckout 2> /dev/null)" = true ]; then
		echo "working-tree: refused: sparse checkout is on" > "$r/2"
	fi

	# 3. skip-worktree or assume-unchanged paths: `ls-files -v` tags S, h, and s.
	g ls-files -v > "$tmp/lsv" || die "git ls-files failed"
	awk '
		{
			c = substr($0, 1, 1)
			if (c == "S" || c == "h" || c == "s") {
				n++
				if (n == 1) p = substr($0, 3)
			}
		}
		END { if (n > 0) print n " paths are skip-worktree or assume-unchanged, first " p }
	' "$tmp/lsv" > "$tmp/flags" || die "awk failed"
	if [ -s "$tmp/flags" ]; then
		IFS= read -r line < "$tmp/flags"
		printf '%s\n' "working-tree: refused: $line" > "$r/3"
	fi

	# 4. unmerged paths.
	g ls-files -u > "$tmp/lsu" || die "git ls-files failed"
	awk '{ print substr($0, index($0, "\t") + 1); exit }' "$tmp/lsu" > "$tmp/unmerged" ||
		die "awk failed"
	if [ -s "$tmp/unmerged" ]; then
		IFS= read -r line < "$tmp/unmerged"
		printf '%s\n' "working-tree: refused: unmerged paths, first $line" > "$r/4"
	fi

	# The paths a build would add, and the driver of each. Quoted paths are refused (9).
	g ls-files --cached --others --exclude-standard > "$tmp/paths" ||
		die "git ls-files failed"
	git -c core.quotePath=false -c core.fsmonitor=false -C "$top" check-attr --stdin filter < "$tmp/paths" > "$tmp/attr" ||
		die "git check-attr failed"
	# 7 and 8. `driver<TAB>path` for the first path of each driver, in first-seen order.
	awk '
		{
			n = split($0, f, " ")
			v = f[n]
			if (v == "unspecified" || v == "unset" || v == "set") next
			if (!(v in seen)) {
				seen[v] = 1
				print v "\t" substr($0, 1, length($0) - length(v) - 10)
			}
		}
	' "$tmp/attr" > "$tmp/drivers" || die "awk failed"
	while IFS=$tab read -r drv p; do
		if [ "$drv" = lfs ]; then
			printf '%s\n' "working-tree: refused: Git LFS filter on $p" > "$r/7"
		elif cfgset "filter.$drv.clean" || cfgset "filter.$drv.process"; then
			printf '%s\n' "working-tree: refused: filter '$drv' runs a program on $p" >> "$r/8"
		fi
	done < "$tmp/drivers"

	# 9. a path git prints quoted even with core.quotePath=false.
	awk '/^"/ { print; exit }' "$tmp/paths" > "$tmp/quoted" || die "awk failed"
	if [ -s "$tmp/quoted" ]; then
		IFS= read -r line < "$tmp/quoted"
		printf '%s\n' "working-tree: refused: unsupported path (git prints it quoted): $line" > "$r/9"
	fi

	# 5 and 6. A dirty submodule, and an untracked nested repository. A status would run
	# a filter that a reason above names, so it waits for them to be absent.
	if [ ! -s "$r/7" ] && [ ! -s "$r/8" ]; then
		g status --porcelain=v2 --untracked-files=all --ignore-submodules=none \
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

	# The build, in a temporary index of its own.
	idx=$tmp/index
	GIT_INDEX_FILE=$idx g read-tree "$head" ||
		die "git read-tree failed"
	GIT_INDEX_FILE=$idx g add -A || die "git add failed"
	tree=$(GIT_INDEX_FILE=$idx g write-tree) ||
		die "git write-tree failed"
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
	} > "$tmp/final" || die "cannot write the output"
	cat "$tmp/final"
	exit 0
}

case ${1:-} in
build)
	[ $# -eq 2 ] || usage
	build "$2"
	;;
*) usage ;;
esac
