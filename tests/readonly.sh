#!/bin/sh
# readonly.sh: test skills/cca/scripts/readonly.sh against the solo-dirty fixture.
#
# Usage: sh tests/readonly.sh
#
# Each case builds a fresh solo-dirty fixture (tests/fixture/build.sh), takes a baseline
# snapshot, makes one change, runs `readonly.sh check`, and compares stdout, stderr, and
# the exit status with literals. The run directory is outside the app repository, except
# in cases 10 and 19. The script under test runs under `sh`, or under $RO_SH when set, for
# example `RO_SH=dash sh tests/readonly.sh`. Cases 13 to 18 and 21 build their extra repos inline,
# with a pinned identity and commit date, so their shas are literals. Cases 26 and 27 add
# a linked worktree to the fixture's app repo, whose files are those committed at its head.
#
# The literal hashes are the blob ids of the fixture's README.md (the committed line
# plus `Local edit, not committed.`, then that plus `Second local edit.`). The sha in
# the ref cases is the head of `main` in the fixture (see tests/fixture/expected.md).
#
# Cases (see the comments below for each):
#  1 no change                         7 a new branch ref
#  2 tracked file edited               8 a new remote-tracking ref
#  3 tracked file restored             9 a local config key
#  4 ignored file appended            10 run directory inside an ignored directory
#  5 ignored file deleted             11 second check, ignored base moved
#  6 same-size rewrite, same second   12 usage and baseline errors
# 13 submodule: ignored file added    17 nested repo: HEAD moves
# 14 submodule: tracked file edited   18 upstream ref moves
# 15 dirty submodule edited again     19 run directory in other letters
# 16 nested repo: edit and new file   20 stat-only change, index kept
# 21 submodule not checked out: file added
# 22 out prefix is the baseline in other letters  23 run directory in other letters
# 24 out prefix on a UNC path, outside the run directory
# 25 out prefix with a .. component
# 26 a linked worktree as the repo
# 27 a linked worktree in an ignored directory of the repo
# 28 a configured core.fsmonitor hook is not run
# 29 touched b.txt next to a blocked `a b.txt`  30 one of two identical config lines removed
#
# Prints one line per mismatch, then `readonly test: ok` when there were none. Exit 0
# when every case matches, otherwise 1.

set -u

here=$(cd "$(dirname "$0")" && pwd)
ro=$here/../skills/cca/scripts/readonly.sh
sh_bin=${RO_SH:-sh}
# Every temporary path, the fixtures and run directories included, lives under one root,
# removed as one quoted path, so a temp path that holds a space cannot split the cleanup.
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
tmp=$root/work
mkdir "$tmp"
bad=0

sha=2b5e8f3511e25bc0225ffc4ef6957dcca51d9fcd
hash_orig=62bbbc5f8f323f1c372e43131e1d3ad8a214adeb
hash_edit=44e925490cf5a75b8514640ac89751f80066380f

mismatch() {
	echo "readonly test: $*"
	bad=$((bad + 1))
}

# fresh: build a new solo-dirty fixture; sets A (the app repo) and R (a run directory
# outside it).
fresh() {
	m=$(TMPDIR=$root sh "$here/fixture/build.sh" solo-dirty) || {
		mismatch "fixture build failed"
		exit 1
	}
	F=$(dirname "$m")
	A=$F/app
	R=$(mktemp -d "$root/run.XXXXXX")
	results=$A/.test-output/results.txt
}

# ro <args>: run the script; sets rc, and writes $tmp/out and $tmp/err.
ro() {
	"$sh_bin" "$ro" "$@" > "$tmp/out" 2> "$tmp/err"
	rc=$?
}

# snap <prefix>: baseline snapshot of $A into $R.
snap() {
	ro snapshot "$A" "$R" "$1"
	[ "$rc" = 0 ] || mismatch "$case_id: snapshot exit $rc: $(cat "$tmp/err")"
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

# frac <file>: print the fractional digits of the file's mtime.
frac() {
	v=$(stat -c '%.9Y' "$1" 2> /dev/null) || v=$(stat -f '%Fm' "$1" 2> /dev/null) || v=
	case $v in
	*.*) printf '%s\n' "${v#*.}" ;;
	*) printf 'none\n' ;;
	esac
}

# set_mtime <file> <YYYY-MM-DDThh:mm:SS.frac> <expected frac digits>: set the time and
# check with stat that the fractional part took effect. Returns 1 when it did not.
set_mtime() {
	touch -d "$2" "$1" || return 1
	[ "$(frac "$1")" = "$3" ]
}

# 1. no change: nothing printed, exit 0.
case_id="case 1"
fresh
snap "$R/b"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 1" 0 '' ''

# 2. a line appended to a tracked, already modified file: the old and new hash lines.
case_id="case 2"
fresh
snap "$R/b"
printf '%s\n' 'Second local edit.' >> "$A/README.md"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 2" 1 "blocked hashes + $hash_edit README.md\nblocked hashes - $hash_orig README.md\n" ''

# 3. the same file restored byte for byte after the baseline: no difference, but the
# file is newer than the marker, so it is listed as touched. Its mtime is set far ahead
# so the case does not depend on the clock's granularity.
case_id="case 3"
fresh
cp "$A/README.md" "$tmp/README.orig"
snap "$R/b"
printf '%s\n' 'Second local edit.' >> "$A/README.md"
cp "$tmp/README.orig" "$A/README.md"
touch -d '2037-01-01T00:00:00' "$A/README.md"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 3" 0 'touched README.md\n' ''

# 4. an ignored file appended to.
case_id="case 4"
fresh
snap "$R/b"
printf '%s\n' 'ok tests/test_extra.sh' >> "$results"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 4" 3 'ignored changed .test-output/results.txt\n' ''

# 5. an ignored file deleted.
case_id="case 5"
fresh
snap "$R/b"
rm "$results"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 5" 3 'ignored deleted .test-output/results.txt\n' ''

# 6. a same-size rewrite within the same second: only the sub-second mtime differs. The
# times are set with touch -d, and checked with stat before the case is judged.
case_id="case 6"
fresh
if ! set_mtime "$results" '2026-09-01T10:00:00.100000000' 100000000; then
	mismatch "case 6: the file system did not keep the fractional mtime .100000000"
else
	snap "$R/b"
	printf '%s\n' 'ok tests/test_users.xx' > "$results"
	if ! set_mtime "$results" '2026-09-01T10:00:00.600000000' 600000000; then
		mismatch "case 6: the file system did not keep the fractional mtime .600000000"
	elif [ "$(wc -c < "$results" | tr -d ' ')" != 23 ]; then
		mismatch "case 6: the rewrite changed the size"
	else
		ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
		expect "case 6" 3 'ignored changed .test-output/results.txt\n' ''
	fi
fi

# 7. a new branch ref.
case_id="case 7"
fresh
snap "$R/b"
git -C "$A" update-ref refs/heads/x "$sha"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 7" 1 "blocked refs + $sha commit\trefs/heads/x\n" ''

# 8. a new remote-tracking ref.
case_id="case 8"
fresh
snap "$R/b"
git -C "$A" update-ref refs/remotes/origin/y "$sha"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 8" 3 "remote-ref + $sha commit\trefs/remotes/origin/y\n" ''

# 9. a new local config key.
case_id="case 9"
fresh
snap "$R/b"
git -C "$A" config --local cca.test 1
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 9" 1 'blocked config + cca.test=1\n' ''

# 10. a run directory inside an ignored directory of the repo: files written into it
# are neither ignored-file differences nor touched files.
case_id="case 10"
fresh
RD=$A/.test-output/cca-run
mkdir -p "$RD"
ro snapshot "$A" "$RD" "$RD/baseline/app"
[ "$rc" = 0 ] || mismatch "case 10: snapshot exit $rc: $(cat "$tmp/err")"
mkdir -p "$RD/deep"
printf '%s\n' 'note' > "$RD/note.txt"
printf '%s\n' 'note' > "$RD/deep/more.txt"
ro check "$A" "$RD" "$RD/baseline/app" "$RD/baseline/app" "$RD/stage/app"
expect "case 10" 0 '' ''

# 11. after case 4's change, a second check whose ignored base is the first check's
# prefix reports nothing: the accepted change is not reported again.
case_id="case 11"
fresh
snap "$R/b"
printf '%s\n' 'ok tests/test_extra.sh' >> "$results"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c1"
expect "case 11, first check" 3 'ignored changed .test-output/results.txt\n' ''
ro check "$A" "$R" "$R/b" "$R/c1" "$R/c2"
expect "case 11, second check" 0 '' ''

# 12. errors, all exit 2 with nothing on stdout: a missing baseline file, and an out
# prefix equal to the baseline prefix.
case_id="case 12"
fresh
snap "$R/b"
rm "$R/b.refs"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 12, missing baseline file" 2 '' "readonly: baseline file missing: $R/b.refs\n"
fresh
snap "$R/b"
ro check "$A" "$R" "$R/b" "$R/b" "$R/b"
expect "case 12, out prefix equals the baseline" 2 '' "readonly: out prefix equals the baseline prefix: $R/b\n"

# Nested repository, upstream, case, and index cases (13 to 20). The extra repos are built
# inline under $root, with a pinned identity and one fixed commit date, so every sha in an
# expected line is the same on every machine.

# g <git args>: git with a pinned identity and a fixed commit date.
g() {
	GIT_AUTHOR_DATE='2026-09-02 10:00:00 +0000'
	GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
	git -c user.name=fixture -c user.email=fixture@example.invalid \
		-c commit.gpgsign=false -c core.autocrlf=false -c init.defaultBranch=main "$@"
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

# add_sub: check out a copy of $root/subsrc as the submodule `sub` of $A.
add_sub() {
	g -c protocol.file.allow=always -C "$A" submodule add -q "$root/subsrc" sub > /dev/null 2>&1 || {
		mismatch "$case_id: submodule add failed"
		exit 1
	}
}

sha2=bd5d5e1e67a1fc55adeaa1452920245b1d368f7f
case_id="setup"
mkrepo "$root/subsrc"

# 13. an ignored file written inside a checked-out submodule: listed as ignored, no error.
case_id="case 13"
fresh
add_sub
snap "$R/b"
mkdir "$A/sub/out"
printf '%s\n' 'built' > "$A/sub/out/o.txt"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 13" 3 'ignored added sub/out/o.txt\n' ''

# 14. a tracked file of a submodule edited: blocked.
case_id="case 14"
fresh
add_sub
snap "$R/b"
printf '%s\n' 'edit' >> "$A/sub/s.txt"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 14" 1 'blocked hashes + f9d46ff33ebc777fef8c92782244c46f6a8fdb47 sub/s.txt
blocked status + 1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 sub/s.txt
blocked status + 1 AM S.M. 000000 160000 160000 0000000000000000000000000000000000000000 9ab67a52d32684221ae03164802c45aa847ef148 sub
blocked status - 1 A. S... 000000 160000 160000 0000000000000000000000000000000000000000 9ab67a52d32684221ae03164802c45aa847ef148 sub
' ''

# 15. a submodule already dirty at the baseline, edited again: blocked.
case_id="case 15"
fresh
add_sub
printf '%s\n' 'edit' >> "$A/sub/s.txt"
snap "$R/b"
printf '%s\n' 'edit again' >> "$A/sub/s.txt"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 15" 1 'blocked hashes + 72f088f38fb8aa6e08454dee9aab8e86872ddd82 sub/s.txt
blocked hashes - f9d46ff33ebc777fef8c92782244c46f6a8fdb47 sub/s.txt
' ''

# 16. an untracked nested repo: a file edited and a file added: blocked.
case_id="case 16"
fresh
mkrepo "$A/vendor"
snap "$R/b"
printf '%s\n' 'two' > "$A/vendor/s.txt"
printf '%s\n' 'new' > "$A/vendor/new.txt"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 16" 1 'blocked hashes + 3e757656cf36eca53338e520d134963a44f793f8 vendor/new.txt
blocked hashes + f719efd430d52bcfc8566a43b2eb655688d38871 vendor/s.txt
blocked status + 1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 vendor/s.txt
blocked status + ? vendor/new.txt
' ''

# 17. an untracked nested repo whose HEAD moves (a new, empty commit): blocked.
case_id="case 17"
fresh
mkrepo "$A/vendor"
snap "$R/b"
g -C "$A/vendor" commit -q --allow-empty -m two
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 17" 1 'blocked status + # branch.oid 3568a00fd681353143030ce4c197f52904eba9c0 in vendor
blocked status - # branch.oid 9ab67a52d32684221ae03164802c45aa847ef148 in vendor
' ''

# 18. the upstream of the checked-out branch moves: only remote-ref lines, no
# `# branch.ab` difference. scratch-branch has no upstream in the fixture, so give it one.
case_id="case 18"
fresh
git -C "$A" update-ref refs/remotes/origin/main "$sha"
git -C "$A" config remote.origin.url "$root/none"
git -C "$A" config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
git -C "$A" config branch.scratch-branch.remote origin
git -C "$A" config branch.scratch-branch.merge refs/heads/main
snap "$R/b"
git -C "$A" update-ref refs/remotes/origin/main "$sha2"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 18" 3 "remote-ref + $sha2 commit\trefs/remotes/origin/main\nremote-ref - $sha commit\trefs/remotes/origin/main\n" ''

# 19. a run directory inside the ignored .test-output/, passed in other letters than the
# directory has: its own files are not reported. Only a repository with core.ignorecase
# true has a case-insensitive file system, so any other (Linux) skips the case.
case_id="case 19"
fresh
if [ "$(git -C "$A" config --bool core.ignorecase)" = true ]; then
	RD=$A/.test-output/cca-run
	RU=$A/.test-output/CCA-RUN
	mkdir -p "$RD"
	ro snapshot "$A" "$RD" "$RD/baseline/app"
	[ "$rc" = 0 ] || mismatch "case 19: snapshot exit $rc: $(cat "$tmp/err")"
	printf '%s\n' 'note' > "$RD/note.txt"
	ro check "$A" "$RU" "$RD/baseline/app" "$RD/baseline/app" "$RU/stage/app"
	expect "case 19" 0 '' ''
fi

# 20. a stat-only change to a tracked file: a snapshot and a check leave the index of the
# repository and the index of its submodule byte for byte as they were.
case_id="case 20"
fresh
add_sub
subidx=$(git -C "$A/sub" rev-parse --absolute-git-dir)/index
touch -d '2037-01-01T00:00:00' "$A/src/users.sh" "$A/sub/s.txt"
top0=$(git hash-object --no-filters "$A/.git/index")
sub0=$(git hash-object --no-filters "$subidx")
snap "$R/b"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 20" 0 'touched src/users.sh\ntouched sub/s.txt\n' ''
[ "$(git hash-object --no-filters "$A/.git/index")" = "$top0" ] || mismatch "case 20: the repository index changed"
[ "$(git hash-object --no-filters "$subidx")" = "$sub0" ] || mismatch "case 20: the submodule index changed"

# 21. a submodule that is not checked out (deinitialized): its directory is empty and its
# gitlink stays in the index. A file written into the directory is untracked content.
case_id="case 21"
fresh
add_sub
g -C "$A" submodule deinit -q -f sub > /dev/null 2>&1 || mismatch "case 21: submodule deinit failed"
snap "$R/b"
printf '%s\n' 'new' > "$A/sub/new.txt"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 21" 1 'blocked hashes + 3e757656cf36eca53338e520d134963a44f793f8 sub/new.txt\n' ''

# 22 and 23 only mean something on a case-insensitive file system, where $R/BASE names the
# same files as $R/base. The test probes for it (the script itself does not): after the
# baseline to $R/base, $R/BASE.marker exists there. Elsewhere (Linux) both are skipped.

# 22. an out prefix that is the baseline in other letters: refused, baseline untouched.
case_id="case 22"
fresh
snap "$R/base"
if [ -e "$R/BASE.marker" ]; then
	printf '%s\n' 'Second local edit.' >> "$A/README.md"
	h0=$(git hash-object --no-filters "$R/base.hashes")
	ro check "$A" "$R" "$R/base" "$R/base" "$R/BASE"
	expect "case 22" 2 '' "readonly: out prefix equals the baseline prefix: $R/BASE\n"
	[ "$(git hash-object --no-filters "$R/base.hashes")" = "$h0" ] || mismatch "case 22: the baseline was overwritten"
fi

# 23. the run directory passed in other letters than the out prefix's directory: the
# normal result.
case_id="case 23"
fresh
snap "$R/base"
if [ -e "$R/BASE.marker" ]; then
	RU=$(dirname "$R")/$(basename "$R" | tr 'a-z' 'A-Z')
	printf '%s\n' 'Second local edit.' >> "$A/README.md"
	ro check "$A" "$RU" "$R/base" "$R/base" "$R/c"
	expect "case 23" 1 "blocked hashes + $hash_edit README.md\nblocked hashes - $hash_orig README.md\n" ''
fi

# 24. an out prefix on a UNC path, outside the run directory: refused at once. The walk up
# from it reaches //, whose dirname is // again, so it must stop there rather than loop.
# Only a system that reaches the local C: drive as a UNC share runs it (Windows); a
# regression would hang, so the call is bounded with `timeout` where it exists.
case_id="case 24"
if [ -d '//localhost/c$' ]; then
	fresh
	snap "$R/base"
	unc='//localhost/c$/cca-readonly-test-unc/out'
	if command -v timeout > /dev/null 2>&1; then
		timeout 60 "$sh_bin" "$ro" check "$A" "$R" "$R/base" "$R/base" "$unc" > "$tmp/out" 2> "$tmp/err"
		rc=$?
	else
		ro check "$A" "$R" "$R/base" "$R/base" "$unc"
	fi
	expect "case 24" 2 '' "readonly: out prefix is not inside the run directory: $unc\n"
fi

# 25. an out prefix with a .. component that resolves to the baseline once the missing
# directory is created: refused before anything is written. Runs on every platform.
case_id="case 25"
fresh
snap "$R/base"
printf '%s\n' 'Second local edit.' >> "$A/README.md"
h0=$(git hash-object --no-filters "$R/base.hashes")
ro check "$A" "$R" "$R/base" "$R/base" "$R/missing/../base"
expect "case 25" 2 '' "readonly: out prefix has a .. component: $R/missing/../base\n"
[ "$(git hash-object --no-filters "$R/base.hashes")" = "$h0" ] || mismatch "case 25: the baseline was overwritten"
[ ! -e "$R/missing" ] || mismatch "case 25: a directory was created"
# A . component stays allowed, since it never changes the directory: the same edit through
# $R/./c gives the ordinary result.
ro check "$A" "$R" "$R/base" "$R/base" "$R/./c"
expect "case 25, . component" 1 "blocked hashes + 44e925490cf5a75b8514640ac89751f80066380f README.md\nblocked hashes - 62bbbc5f8f323f1c372e43131e1d3ad8a214adeb README.md\n" ''

# 26. a linked worktree as the audited repo: no change is quiet, and a line appended to a
# tracked file is blocked. The worktree is at the committed head, so its README.md is not
# the fixture's edited one.
case_id="case 26"
fresh
W=$root/wt26
g -C "$A" worktree add -q --detach "$W" || mismatch "case 26: worktree add failed"
ro snapshot "$W" "$R" "$R/base"
[ "$rc" = 0 ] || mismatch "case 26: snapshot exit $rc: $(cat "$tmp/err")"
ro check "$W" "$R" "$R/base" "$R/base" "$R/c"
expect "case 26, no change" 0 '' ''
printf '%s\n' 'Worktree edit.' >> "$W/README.md"
ro check "$W" "$R" "$R/base" "$R/base" "$R/d"
expect "case 26, edit" 1 "blocked hashes + 72ae0280a46747d20df228459aca358c42928b22 README.md\nblocked status + 1 .M N... 100644 100644 100644 36d7b792e8bbd0d467c1d17382cd9c2e4b5dbc24 36d7b792e8bbd0d467c1d17382cd9c2e4b5dbc24 README.md\n" ''

# 27. a linked worktree inside an ignored directory of the audited repo. Git lists it as
# one ignored directory, so .ignored holds one line for it. A change below its top level
# is not detected, and an entry added at its top level shows as one ignored change. The
# directory's mtime is set to an old time first, so that entry always changes it.
case_id="case 27"
fresh
g -C "$A" worktree add -q --detach "$A/.test-output/wt" || mismatch "case 27: worktree add failed"
touch -t 200001010000 "$A/.test-output/wt"
snap "$R/base"
[ "$(grep -c ' \.test-output/wt/$' "$R/base.ignored")" = 1 ] ||
	mismatch "case 27: .ignored does not hold exactly one line for the worktree"
[ "$(grep -c ' \.test-output/wt/.' "$R/base.ignored")" = 0 ] ||
	mismatch "case 27: .ignored holds a line below the worktree"
printf '%s\n' 'Worktree edit.' >> "$A/.test-output/wt/README.md"
printf '%s\n' 'new' > "$A/.test-output/wt/src/new.txt"
ro check "$A" "$R" "$R/base" "$R/base" "$R/c"
expect "case 27, below the top level" 0 '' ''
printf '%s\n' 'new' > "$A/.test-output/wt/new.txt"
ro check "$A" "$R" "$R/base" "$R/base" "$R/d"
expect "case 27, at the top level" 3 'ignored changed .test-output/wt/\n' ''

# 28. a configured core.fsmonitor hook never runs during a snapshot or a check: the
# marker the hook would create stays absent.
case_id="case 28"
fresh
printf '%s\n' "touch '$root/fsmonitor-ran'" 'exit 1' > "$root/fsmonitor.sh"
git -C "$A" config core.fsmonitor "sh '$root/fsmonitor.sh'"
snap "$R/b"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 28" 0 '' ''
[ ! -e "$root/fsmonitor-ran" ] || mismatch "case 28: the fsmonitor hook ran"

# 29. a blocked line for `a b.txt` does not hide a touched b.txt: the touched filter compares
# whole paths, not the end of the blocked line.
case_id="case 29"
fresh
printf 'one\n' > "$A/a b.txt"
printf 'one\n' > "$A/b.txt"
g -C "$A" add "a b.txt" b.txt || mismatch "case 29: add failed"
g -C "$A" commit -q -m two-files || mismatch "case 29: commit failed"
snap "$R/b"
printf 'two\n' > "$A/a b.txt"
touch -d '2037-01-01T00:00:00' "$A/a b.txt" "$A/b.txt"
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 29" 1 'blocked hashes + f719efd430d52bcfc8566a43b2eb655688d38871 a b.txt\nblocked status + 1 .M N... 100644 100644 100644 5626abf0f72e58d7a153368ba57db4c673c0e171 5626abf0f72e58d7a153368ba57db4c673c0e171 a b.txt\ntouched b.txt\n' ''

# 30. one of two identical config lines removed: still reported, as the sorted compare did.
case_id="case 30"
fresh
git -C "$A" config --add test.dup v
git -C "$A" config --add test.dup v
snap "$R/b"
git -C "$A" config --unset-all test.dup
git -C "$A" config --add test.dup v
ro check "$A" "$R" "$R/b" "$R/b" "$R/c"
expect "case 30" 1 'blocked config - test.dup=v\n' ''

# 31. a relative prefix that awk would take for an assignment (k=v/...): the check still
# compares the files.
case_id="case 31"
fresh
cwd0=$(pwd)
cd "$R" || exit 1
ro snapshot "$A" "$R" k=v/b
[ "$rc" = 0 ] || mismatch "case 31: snapshot exit $rc: $(cat "$tmp/err")"
printf '%s\n' 'Second local edit.' >> "$A/README.md"
ro check "$A" "$R" k=v/b k=v/b k=v/c
cd "$cwd0" || exit 1
expect "case 31" 1 "blocked hashes + $hash_edit README.md\nblocked hashes - $hash_orig README.md\n" ''

if [ "$bad" -gt 0 ]; then
	exit 1
fi
echo "readonly test: ok"
