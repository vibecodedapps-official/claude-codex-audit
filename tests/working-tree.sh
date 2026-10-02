#!/bin/sh
# working-tree.sh: test skills/cca/scripts/working-tree.sh against the solo fixture.
#
# Usage: sh tests/working-tree.sh
#
# The solo fixture is built once (tests/fixture/build.sh); each case works on a fresh copy
# of its app repo, or on a repo built inline with a pinned identity and commit date, so
# every sha in an expected line is a literal and is the same on every machine. Git runs
# with no global or system config. Each run of the script gets an empty TMPDIR, which must
# be empty again afterwards, so the script's temporary index is always removed. The script
# under test runs under `sh`, or under $WT_SH when set, for example
# `WT_SH=dash sh tests/working-tree.sh`.
#
# The literal shas: the solo app's feature head, 0c23936980b254c4abd489d3ecfd296f5e7bc0db,
# is the parent of every build. The synthetic head and tree are the script's output for
# the fixture with its one untracked file (notes/deactivate-draft.txt), written down once.
# Every file the fixture writes is a regular file without the executable bit, and git runs
# with core.autocrlf unset, so a literal does not depend on the operating system.
#
# Cases:
#  1 build on the solo app             2 a second build
#  3 a tracked file edited             4 commit.gpgSign=true in local config
#  5 GIT_INDEX_FILE set by the caller  4b core.fsmonitor hook not run
#  6 refusals (6a to 6l), each with the object count
#  7 a submodule whose HEAD moved      8 a failed git step (8a, 8b)
#  9 not a work tree, and usage errors
# 10 a staged file that matches an ignore rule   11 no index file
# 12 `check`: no output and no write, and the same refusal lines as `build`
# 13 a submodule's own program filter, refused with the submodule prefix
# 14 a repo hook is not run         15 a renamed submodule with a change is refused
# 16 a driver named `set`            17 no index file, an ignored tracked file with a filter
# 18 an assume-unchanged file in a submodule
#
# Prints one line per mismatch, then `working-tree test: ok` when there were none. Exit 0
# when every case matches, otherwise 1.

set -u

here=$(cd "$(dirname "$0")" && pwd)
wt=$here/../skills/cca/scripts/working-tree.sh
ro=$here/../skills/cca/scripts/readonly.sh
sh_bin=${WT_SH:-sh}

GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# Every temporary path lives under one root, removed as one quoted path.
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
tmp=$root/work
tdir=$root/tmpdir
mkdir "$tmp" "$tdir"
bad=0
tab=$(printf '\t')

parent=0c23936980b254c4abd489d3ecfd296f5e7bc0db
head1=1fcf8c53acc3f6e064fcb29ec0a05963b4949f2a
tree1=44cdf018ff3489bd74ad79d5cd4e74b76ff56773
head3=f4884c80127957fe66550d27ef6058ad1a4679ce
tree3=0b04038bef9a0703ea8527c554992e0c9d05ba9d

mismatch() {
	echo "working-tree test: $*"
	bad=$((bad + 1))
}

# g <git args>: git with a pinned identity and a fixed commit date.
g() {
	GIT_AUTHOR_DATE='2026-09-02 10:00:00 +0000'
	GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
	git -c user.name=fixture -c user.email=fixture@example.invalid \
		-c commit.gpgsign=false -c core.autocrlf=false -c init.defaultBranch=main "$@"
}

# run <args>: the script, with an empty TMPDIR; sets rc, and writes $tmp/out and $tmp/err.
# The temporary directory must be empty afterwards.
run() {
	TMPDIR=$tdir "$sh_bin" "$wt" "$@" > "$tmp/out" 2> "$tmp/err"
	rc=$?
	if [ -n "$(ls -A "$tdir")" ]; then
		mismatch "$case_id: the script left $(ls -A "$tdir" | tr '\n' ' ')in TMPDIR"
		rm -rf "$tdir"
		mkdir "$tdir"
	fi
}

# expect <case> <exit> <stdout> <stderr>: compare the last run. The text arguments are
# printf %b strings, so \n and \t stand for newline and tab.
expect() {
	printf '%b' "$3" > "$tmp/exp.out"
	printf '%b' "$4" > "$tmp/exp.err"
	[ "$rc" = "$2" ] || mismatch "$1: exit $rc, expected $2"
	cmp -s "$tmp/exp.out" "$tmp/out" ||
		mismatch "$1: stdout differs: got [$(tr '\n\t' '|~' < "$tmp/out")], expected [$(tr '\n\t' '|~' < "$tmp/exp.out")]"
	cmp -s "$tmp/exp.err" "$tmp/err" ||
		mismatch "$1: stderr differs: got [$(tr '\n\t' '|~' < "$tmp/err")], expected [$(tr '\n\t' '|~' < "$tmp/exp.err")]"
}

# lines <head> <tree>: the four stdout lines of a build on the solo app.
lines() {
	printf 'head %s\nparent %s\ntree %s\nuntracked notes/deactivate-draft.txt\n' "$1" "$parent" "$2"
}

# loose <repo>: the number of loose objects.
loose() {
	find "$1/.git/objects" -type f ! -path '*/pack/*' ! -path '*/info/*' | wc -l | tr -d ' '
}

# refuse <case> <repo> <stderr>: the script refuses with one line, and writes no object.
refuse() {
	n0=$(loose "$2")
	run build "$2"
	expect "$1" 1 '' "$3"
	[ "$(loose "$2")" = "$n0" ] || mismatch "$1: the object count changed"
}

# idx <repo>: the hash of the repo's index.
idx() {
	git hash-object --no-filters "$1/.git/index"
}

# The solo fixture, built once; fresh copies it to a new directory and sets A.
m=$(TMPDIR=$root sh "$here/fixture/build.sh" solo) || {
	mismatch "fixture build failed"
	exit 1
}
base=$(dirname "$m")/app
nfresh=0
fresh() {
	nfresh=$((nfresh + 1))
	A=$root/app$nfresh
	cp -R "$base" "$A" || {
		mismatch "$case_id: cannot copy the fixture"
		exit 1
	}
}

# mkrepo <dir>: a repo on main with one commit, holding s.txt and a .gitignore for out/.
mkrepo() {
	mkdir -p "$1" && g init -q "$1" && g -C "$1" symbolic-ref HEAD refs/heads/main &&
		printf 'out/\n' > "$1/.gitignore" && printf 'one\n' > "$1/s.txt" &&
		g -C "$1" add -A && g -C "$1" commit -q -m one || {
		mismatch "$case_id: cannot build $1"
		exit 1
	}
}

# add_sub: check out a copy of $root/subsrc as the submodule `sub` of $A, recorded in the
# a commit as a gitlink to its head. No .gitmodules, so no path of this run is in the tree.
add_sub() {
	g clone -q "$root/subsrc" "$A/sub" > /dev/null 2>&1 &&
		g -C "$A" update-index --add --cacheinfo "160000,$(g -C "$A/sub" rev-parse HEAD),sub" &&
		g -C "$A" commit -q -m sub || {
		mismatch "$case_id: cannot add the submodule"
		exit 1
	}
}

case_id="setup"
mkrepo "$root/subsrc"

# 1. a build on the solo app (on feature, one untracked file): the four lines, the index
# and refs unchanged, and a read-only check against an earlier baseline quiet.
case_id="case 1"
fresh
R=$root/run1
mkdir "$R"
sh "$ro" snapshot "$A" "$R" "$R/b" || mismatch "case 1: snapshot failed"
i0=$(idx "$A")
refs0=$(git -C "$A" for-each-ref)
run build "$A"
expect "case 1" 0 "$(lines "$head1" "$tree1")\n" ''
[ "$(idx "$A")" = "$i0" ] || mismatch "case 1: the index changed"
[ "$(git -C "$A" for-each-ref)" = "$refs0" ] || mismatch "case 1: a ref changed"
sh "$ro" check "$A" "$R" "$R/b" "$R/b" "$R/c" > "$tmp/out" 2> "$tmp/err"
rc=$?
expect "case 1, read-only check" 0 '' ''

# 2. a second build prints the same lines.
case_id="case 2"
run build "$A"
expect "case 2" 0 "$(lines "$head1" "$tree1")\n" ''

# 3. a tracked file edited: another head and tree.
case_id="case 3"
fresh
printf '%s\n' 'Local edit, not committed.' >> "$A/README.md"
run build "$A"
expect "case 3" 0 "$(lines "$head3" "$tree3")\n" ''

# 4. commit.gpgSign=true with a program that fails: the case 1 lines.
case_id="case 4"
fresh
git -C "$A" config commit.gpgSign true
git -C "$A" config gpg.program false
run build "$A"
expect "case 4" 0 "$(lines "$head1" "$tree1")\n" ''

# 4b. core.fsmonitor naming a hook program: no git call of the script runs it.
case_id="case 4b"
fresh
printf '%s\n' "touch '$root/fsmonitor-ran'" 'exit 1' > "$root/fsmonitor.sh"
git -C "$A" config core.fsmonitor "sh '$root/fsmonitor.sh'"
run build "$A"
expect "case 4b" 0 "$(lines "$head1" "$tree1")\n" ''
[ ! -e "$root/fsmonitor-ran" ] || mismatch "case 4b: the fsmonitor hook ran"

# 5. GIT_INDEX_FILE set by the caller to a scratch copy: the case 1 lines, and that file
# unchanged byte for byte.
case_id="case 5"
fresh
cp "$A/.git/index" "$root/scratch-index"
cp "$A/.git/index" "$root/scratch-index.orig"
GIT_INDEX_FILE=$root/scratch-index
export GIT_INDEX_FILE
run build "$A"
unset GIT_INDEX_FILE
expect "case 5" 0 "$(lines "$head1" "$tree1")\n" ''
cmp -s "$root/scratch-index" "$root/scratch-index.orig" || mismatch "case 5: the caller's index file changed"

# 6. refusals, each exit 1 with its one line, and the object count unchanged.
r="working-tree: refused:"

case_id="case 6a"
fresh
printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > "$A/.gitattributes"
printf 'binary\n' > "$A/a.bin"
refuse "case 6a, lfs" "$A" "$r Git LFS filter on a.bin\n"

case_id="case 6b"
fresh
printf '*.dat filter=mark\n' > "$A/.gitattributes"
printf 'data\n' > "$A/x.dat"
git -C "$A" config filter.mark.clean "touch '$root/filter-ran'; cat"
refuse "case 6b, filter driver" "$A" "$r filter 'mark' runs a program on x.dat\n"
[ ! -e "$root/filter-ran" ] || mismatch "case 6b: the filter ran"
# A driver with neither key runs nothing, so it is not refused.
git -C "$A" config --unset filter.mark.clean
run build "$A"
[ "$rc" = 0 ] || mismatch "case 6b, no clean command: exit $rc, expected 0"

case_id="case 6c"
fresh
git -C "$A" update-index --skip-worktree README.md
refuse "case 6c, skip-worktree" "$A" "$r 1 paths are skip-worktree or assume-unchanged, first README.md\n"

case_id="case 6d"
fresh
git -C "$A" update-index --assume-unchanged src/users.sh
refuse "case 6d, assume-unchanged" "$A" "$r 1 paths are skip-worktree or assume-unchanged, first src/users.sh\n"

case_id="case 6e"
fresh
git -C "$A" config core.sparseCheckout true
refuse "case 6e, sparse checkout" "$A" "$r sparse checkout is on\n"

case_id="case 6f"
mkdir "$root/unborn" && g init -q "$root/unborn" || mismatch "case 6f: cannot build the repo"
refuse "case 6f, no HEAD commit" "$root/unborn" "$r no HEAD commit\n"

case_id="case 6g"
U=$root/conflict
mkrepo "$U"
g -C "$U" checkout -q -b other
printf 'two\n' > "$U/s.txt"
g -C "$U" commit -q -a -m other
g -C "$U" checkout -q main
printf 'three\n' > "$U/s.txt"
g -C "$U" commit -q -a -m three
g -C "$U" merge other > /dev/null 2>&1
refuse "case 6g, unmerged path" "$U" "$r unmerged paths, first s.txt\n"

case_id="case 6h"
fresh
add_sub
printf '%s\n' 'edit' >> "$A/sub/s.txt"
refuse "case 6h, dirty submodule" "$A" "$r submodule sub has uncommitted changes or untracked files\n"

case_id="case 6i"
fresh
mkrepo "$A/vendor"
refuse "case 6i, untracked nested repository" "$A" "$r untracked nested repository vendor\n"

# A tab or a backslash in a name is quoted by git, so the path is refused. A file system
# that rejects the name, or maps it to another one (Windows), skips the case, and the skip
# is printed. quoted_name <name>: write the file, and succeed when git lists a quoted path.
quoted_name() {
	{ printf 'x\n' > "$A/notes/$1"; } 2> /dev/null || return 1
	git -C "$A" -c core.quotePath=false ls-files --others --exclude-standard | grep '^"' > /dev/null
}

case_id="case 6j"
fresh
if quoted_name "a${tab}b"; then
	refuse "case 6j, quoted path" "$A" "$r unsupported path (git prints it quoted): \"notes/a\\\\tb\"\n"
else
	echo "working-tree test: skipped case 6j: the file system does not keep a tab in a name"
fi

case_id="case 6k"
fresh
if quoted_name 'a\b'; then
	refuse "case 6k, quoted path" "$A" "$r unsupported path (git prints it quoted): \"notes/a\\\\\\\\b\"\n"
else
	echo "working-tree test: skipped case 6k: the file system does not keep a backslash in a name"
fi

# The same refusal for a tracked path, put in the index without a file, so it runs on every
# file system.
case_id="case 6l"
fresh
blob=$(git -C "$A" rev-parse HEAD:README.md)
git -C "$A" -c core.protectNTFS=false update-index --add --cacheinfo "100644,$blob,notes/a${tab}b"
refuse "case 6l, quoted tracked path" "$A" "$r unsupported path (git prints it quoted): \"notes/a\\\\tb\"\n"

# 7. a submodule whose HEAD moved but is otherwise clean: built, and the tree records the
# new commit. The parent is the commit that adds the gitlink, made with the pinned identity.
case_id="case 7"
fresh
add_sub
g -C "$A/sub" commit -q --allow-empty -m two
run build "$A"
parent=aebccb87d9e1aedcc385077ab8e7fb3c5fdd9d08
expect "case 7" 0 "$(lines 13b5b5dd7bf07019ded0131a259304b409569d13 b7ee471ca53a263fc37df0e2e28032e64495f193)\n" ''
parent=0c23936980b254c4abd489d3ecfd296f5e7bc0db
n=$(git -C "$A" ls-tree b7ee471ca53a263fc37df0e2e28032e64495f193 sub) || mismatch "case 7: ls-tree failed"
[ "$n" = "$(printf '160000 commit 3568a00fd681353143030ce4c197f52904eba9c0\tsub')" ] ||
	mismatch "case 7: the tree does not record the new commit: $n"

# 8. a failed git step: exit 2, the index unchanged, and nothing left in TMPDIR (checked by
# run). 8a: a copy whose HEAD tree object is gone. 8b: a CRLF file that `add -A` refuses
# under core.safecrlf=true with core.autocrlf=input.
case_id="case 8a"
fresh
t=$(git -C "$A" rev-parse 'HEAD^{tree}')
tf=$A/.git/objects/$(printf '%s' "$t" | cut -c 1-2)/$(printf '%s' "$t" | cut -c 3-)
chmod u+w "$tf" 2> /dev/null
rm -f "$tf"
i0=$(idx "$A")
run build "$A"
[ "$rc" = 2 ] || mismatch "case 8a: exit $rc, expected 2"
[ ! -s "$tmp/out" ] || mismatch "case 8a: stdout is not empty"
[ "$(idx "$A")" = "$i0" ] || mismatch "case 8a: the index changed"

case_id="case 8b"
fresh
git -C "$A" config core.autocrlf input
git -C "$A" config core.safecrlf true
printf 'one\r\ntwo\r\n' > "$A/notes/crlf.txt"
i0=$(idx "$A")
run build "$A"
[ "$rc" = 2 ] || mismatch "case 8b: exit $rc, expected 2"
[ ! -s "$tmp/out" ] || mismatch "case 8b: stdout is not empty"
[ "$(tail -n 1 "$tmp/err")" = "working-tree: git add failed" ] ||
	mismatch "case 8b: stderr ends with [$(tail -n 1 "$tmp/err")]"
[ "$(idx "$A")" = "$i0" ] || mismatch "case 8b: the index changed"

# 9. a path that is not a git work tree, and usage errors: exit 2, nothing on stdout.
usage="usage: working-tree.sh build <repo>\n       working-tree.sh check <repo>\n"
case_id="case 9"
mkdir "$root/plain"
run build "$root/plain"
expect "case 9, not a work tree" 2 '' "working-tree: not a git work tree: $root/plain\n"
run build "$root/missing"
expect "case 9, missing directory" 2 '' "working-tree: not a git work tree: $root/missing\n"
run
expect "case 9, no arguments" 2 '' "$usage"
run build
expect "case 9, no repo" 2 '' "$usage"
run build "$base" extra
expect "case 9, extra argument" 2 '' "$usage"
run snapshot "$base"
expect "case 9, unknown mode" 2 '' "$usage"

# 10. a file that matches an ignore rule but is staged (`git add -f`), not committed: the
# build starts from the repo's own index, so the file is in the built tree.
case_id="case 10"
fresh
mkdir -p "$A/.test-output"
printf 'staged\n' > "$A/.test-output/keep.txt"
git -C "$A" add -f .test-output/keep.txt
i0=$(idx "$A")
run build "$A"
expect "case 10" 0 "$(lines 38bd28c7b7222e6064df2e0e4a667ba31bc58f2b 5e0ec0a263096b090c7abdcfcd4c74cd27864dfe)\n" ''
[ "$(idx "$A")" = "$i0" ] || mismatch "case 10: the index changed"
n=$(git -C "$A" ls-tree -r --name-only 5e0ec0a263096b090c7abdcfcd4c74cd27864dfe | grep -c '^\.test-output/keep\.txt$')
[ "$n" = 1 ] || mismatch "case 10: the staged ignored file is not in the tree"

# 11. no index file: refused, with the path of the repository, before anything is
# written. A checked-out repository always has an index, so this state is not built from.
# 11b: the same for a checked-out submodule.
case_id="case 11"
fresh
rm "$A/.git/index"
n0=$(loose "$A")
for mode in check build; do
	run "$mode" "$A"
	expect "case 11, $mode" 1 '' "$r no index file in .
"
	[ "$(loose "$A")" = "$n0" ] || mismatch "case 11, $mode: the object count changed"
done
[ ! -e "$A/.git/index" ] || mismatch "case 11: an index file was written"
case_id="case 11b"
fresh
add_sub
rm "$A/sub/.git/index"
for mode in check build; do
	run "$mode" "$A"
	expect "case 11b, $mode" 1 '' "$r no index file in sub
"
done

# 12. `check`: the refusal checks only. Nothing is printed and nothing is written for a
# repo that would build; a refusal gives the lines `build` gives, no program runs, and the
# object count is unchanged.
case_id="case 12"
fresh
n0=$(loose "$A")
run check "$A"
expect "case 12, clean" 0 '' ''
[ "$(loose "$A")" = "$n0" ] || mismatch "case 12, clean: the object count changed"
printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' > "$A/.gitattributes"
printf 'binary\n' > "$A/a.bin"
n0=$(loose "$A")
run check "$A"
expect "case 12, lfs" 1 '' "$r Git LFS filter on a.bin\n"
[ "$(loose "$A")" = "$n0" ] || mismatch "case 12, lfs: the object count changed"
fresh
printf '*.dat filter=mark\n' > "$A/.gitattributes"
printf 'data\n' > "$A/x.dat"
git -C "$A" config filter.mark.clean "touch '$root/filter-ran12'; cat"
n0=$(loose "$A")
run check "$A"
expect "case 12, filter driver" 1 '' "$r filter 'mark' runs a program on x.dat\n"
[ "$(loose "$A")" = "$n0" ] || mismatch "case 12, filter driver: the object count changed"
[ ! -e "$root/filter-ran12" ] || mismatch "case 12: the filter ran"
run check "$root/plain"
expect "case 12, not a work tree" 2 '' "working-tree: not a git work tree: $root/plain\n"
run check
expect "case 12, no repo" 2 '' "$usage"
run check "$base" extra
expect "case 12, extra argument" 2 '' "$usage"

# 13. a submodule's own clean filter on a modified tracked file: `check` and `build` both
# refuse before any `git status` could run it, naming the path with the submodule prefix.
# The marker the filter would create stays absent, and no object is written in either repo.
case_id="case 13"
fresh
add_sub
printf '*.dat filter=mark\n' > "$A/sub/.gitattributes"
printf 'data\n' > "$A/sub/x.dat"
g -C "$A/sub" add .gitattributes x.dat
g -C "$A/sub" commit -q -m dat
git -C "$A/sub" config filter.mark.clean "touch '$root/filter-ran13'; cat"
# A same-size edit: git must hash the file to see the change, so a status in the
# submodule would run the clean filter.
printf 'atad\n' > "$A/sub/x.dat"
n0=$(loose "$A")
s0=$(loose "$A/sub")
for mode in check build; do
	run "$mode" "$A"
	expect "case 13, $mode" 1 '' "$r filter 'mark' runs a program on sub/x.dat\n"
	[ "$(loose "$A")" = "$n0" ] || mismatch "case 13, $mode: the object count changed"
	[ "$(loose "$A/sub")" = "$s0" ] || mismatch "case 13, $mode: the submodule's object count changed"
	[ ! -e "$root/filter-ran13" ] || mismatch "case 13, $mode: the filter ran"
done

# 14. a repo hook never runs: `check` and `build` leave the marker a `post-index-change`
# hook would create absent, and `build` still prints the case 1 lines.
case_id="case 14"
fresh
mkdir -p "$A/.git/hooks"
printf '#!/bin/sh\ntouch "%s"\n' "$root/hook-ran14" > "$A/.git/hooks/post-index-change"
chmod +x "$A/.git/hooks/post-index-change"
run check "$A"
expect "case 14, check" 0 '' ''
[ ! -e "$root/hook-ran14" ] || mismatch "case 14, check: the hook ran"
run build "$A"
expect "case 14, build" 0 "$(lines "$head1" "$tree1")\n" ''
[ ! -e "$root/hook-ran14" ] || mismatch "case 14, build: the hook ran"

# 15. a submodule renamed in the index, with a tracked file edited in it: git reports the
# rename as a type 2 status entry, which must be refused like any dirty submodule.
case_id="case 15"
fresh
add_sub
sha=$(g -C "$A/sub" rev-parse HEAD)
mv "$A/sub" "$A/sub2"
g -C "$A" update-index --force-remove sub
g -C "$A" update-index --add --cacheinfo "160000,$sha,sub2"
printf '%s\n' 'edit' >> "$A/sub2/s.txt"
for mode in check build; do
	run "$mode" "$A"
	expect "case 15, $mode" 1 '' "$r submodule sub2 has uncommitted changes or untracked files\n"
done

# 16. a driver named `set` (filter=set is a string, not the attribute state): refused when
# filter.set.clean is configured.
case_id="case 16"
fresh
printf '*.dat filter=set\n' > "$A/.gitattributes"
printf 'data\n' > "$A/x.dat"
git -C "$A" config filter.set.clean "touch '$root/filter-ran16'; cat"
for mode in check build; do
	run "$mode" "$A"
	expect "case 16, $mode" 1 '' "$r filter 'set' runs a program on x.dat\n"
	[ ! -e "$root/filter-ran16" ] || mismatch "case 16, $mode: the filter ran"
done

# 17. no index file, HEAD tracks an ignored file with a program filter and its
# .gitattributes is deleted from disk: refused for the missing index before anything runs.
case_id="case 17"
fresh
printf '*.dat
' >> "$A/.gitignore"
printf '*.dat filter=mark
' > "$A/.gitattributes"
printf 'data
' > "$A/x.dat"
g -C "$A" add -f .gitignore .gitattributes x.dat
g -C "$A" commit -q -m dat
git -C "$A" config filter.mark.clean "touch '$root/filter-ran17'; cat"
printf 'atad
' > "$A/x.dat"
rm "$A/.gitattributes" "$A/.git/index"
n0=$(loose "$A")
for mode in check build; do
	run "$mode" "$A"
	expect "case 17, $mode" 1 '' "$r no index file in .
"
	[ ! -e "$root/filter-ran17" ] || mismatch "case 17, $mode: the filter ran"
	[ "$(loose "$A")" = "$n0" ] || mismatch "case 17, $mode: the object count changed"
done

# 18. an assume-unchanged file edited in a submodule: refused, with the submodule prefix.
case_id="case 18"
fresh
add_sub
git -C "$A/sub" update-index --assume-unchanged s.txt
printf '%s\n' 'edit' >> "$A/sub/s.txt"
for mode in check build; do
	run "$mode" "$A"
	expect "case 18, $mode" 1 '' "$r 1 paths are skip-worktree or assume-unchanged, first sub/s.txt\n"
done

if [ "$bad" -gt 0 ]; then
	exit 1
fi
echo "working-tree test: ok"
