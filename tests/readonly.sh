#!/bin/sh
# readonly.sh: test skills/cca/scripts/readonly.sh against the solo-dirty fixture.
#
# Usage: sh tests/readonly.sh
#
# Each case builds a fresh solo-dirty fixture (tests/fixture/build.sh), takes a baseline
# snapshot, makes one change, runs `readonly.sh check`, and compares stdout, stderr, and
# the exit status with literals. The run directory is outside the app repository, except
# in case 10. The script under test runs under `sh`, or under $RO_SH when set, for
# example `RO_SH=dash sh tests/readonly.sh`.
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
#
# Prints one line per mismatch, then `readonly test: ok` when there were none. Exit 0
# when every case matches, otherwise 1.

set -u

here=$(cd "$(dirname "$0")" && pwd)
ro=$here/../skills/cca/scripts/readonly.sh
sh_bin=${RO_SH:-sh}
tmp=$(mktemp -d)
dirs=$tmp
trap 'rm -rf $dirs' EXIT
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
	m=$(sh "$here/fixture/build.sh" solo-dirty) || {
		mismatch "fixture build failed"
		exit 1
	}
	F=$(dirname "$m")
	A=$F/app
	R=$(mktemp -d)
	dirs="$dirs $F $R"
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

if [ "$bad" -gt 0 ]; then
	exit 1
fi
echo "readonly test: ok"
