#!/bin/sh
# memory.sh: tests for skills/cca/scripts/memory.sh.
#
# Usage: sh tests/memory.sh
#
# Builds the solo fixture and runs `find` on its claims-verdicts.md against a temp memory
# directory, then on inline verdicts files that cover each key grammar, the boundary rule,
# the entries that print nothing, a 0.2.0 entry with no ticket: sub-line, lines over 8,192
# bytes, and usage errors. Expected output is literal; the memory files are written here.
#
# Prints one line per mismatch and `memory test: ok` on success; exits 1 on any mismatch.
set -u

root=$(cd "$(dirname "$0")/.." && pwd)
ms=$root/skills/cca/scripts/memory.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tab=$(printf '\t')
nl='
'

fails=0
fail() {
	echo "memory test: $*"
	fails=$((fails + 1))
}

pad() { head -c "$1" /dev/zero | tr '\000' a; }

# run <label> <expected exit> <expected stdout> <memory.sh args...>: stdout only is
# compared; a nonzero exit must leave stdout empty.
run() {
	label=$1
	want_st=$2
	want_out=$3
	shift 3
	if out=$(sh "$ms" "$@" 2> "$tmp/err"); then st=0; else st=$?; fi
	[ "$st" = "$want_st" ] || fail "$label: expected exit $want_st, got $st"
	[ "$out" = "$want_out" ] || fail "$label: expected output '$want_out', got '$out'"
}

# errmsg <label> <expected stderr>: the stderr of the last run.
errmsg() {
	got=$(cat "$tmp/err")
	[ "$got" = "$2" ] || fail "$1: expected stderr '$2', got '$got'"
}

# ---------------------------------------------------------------------------
# The fixture's claims-verdicts.md against a small memory directory.
if ! m=$(TMPDIR=$tmp sh "$root/tests/fixture/build.sh" solo); then
	echo "memory test: the solo fixture did not build"
	exit 1
fi
F=$(dirname "$m")

mem=$tmp/memory
mkdir -p "$mem/.git"
printf '# Memory\n\n- [App](project_app1.md): APP-1 is the deactivate ticket.\n' > "$mem/MEMORY.md"
printf 'The deactivate work is tracked as APP-1.\n' > "$mem/project_app1.md"
printf 'APP-10 is an unrelated ticket.\n' > "$mem/project_app10.md"
printf 'APP-1\000binary\n' > "$mem/blob.bin"
printf 'APP-1 in the git directory\n' > "$mem/.git/notes"

want="claim 1${tab}APP-1${tab}$mem/MEMORY.md${nl}claim 1${tab}APP-1${tab}$mem/project_app1.md${nl}claim 3${tab}APP-1${tab}$mem/MEMORY.md${nl}claim 3${tab}APP-1${tab}$mem/project_app1.md"
run "fixture verdicts" 0 "$want" find "$F/claims-verdicts.md" "$mem"
run "fixture verdicts, trailing slash" 0 "$want" find "$F/claims-verdicts.md" "$mem/"

# ---------------------------------------------------------------------------
# Inline verdicts: every key grammar, the boundary rule, and the entries that print nothing.
M=$tmp/m
mkdir -p "$M/sub" "$M/.git"
printf 'Issue owner/app#12 and sha 0c23936 are closed.\nThe load.users function; Soft Delete flag.\n' > "$M/a.md"
printf 'loadXusers soft delete 1040 11 x0c23936 deadbeefs\nrow count: 104\n' > "$M/b.md"
printf 'Merged deadbeef (AB#4567)\n1\n' > "$M/sub/c.md"
printf 'See APP-1.\n' > "$M/sub/d.md"
printf '1 104 deadbeef\000\n' > "$M/blob.bin"
printf '1 104 deadbeef AB#4567\n' > "$M/.git/notes"

v=$tmp/v.md
cat > "$v" <<'EOF'
# Claims verdicts: inline

report revision: sha256:0000000000000000000000000000000000000000000000000000000000000000

## /x/claims.md (handoff), hash 0000

- claim 1 [code] /x/h.md:1 tickets/A/commit/app/0c23936: false; finding: C1; evidence: report item C1
  ticket: github:owner/app#12
  text: Commit 0c23936 and deadbeef changed `load.users` and "Soft Delete" for 104 rows, 1 row; sha256 stays Active in AB#4567.
  correction: none
- claim 2 [code] /x/h.md:2 -: true; finding: none; evidence: ok
  ticket: APP-1
  text: APP-1 is fine, 104 rows.
  correction: none
- claim 3 [verification] /x/h.md:3 -: not reproducible here; finding: none; evidence: env: staging
  ticket: APP-1
  text: Checked 104 rows on staging.
  correction: none
- claim 4 [code] /x/h.md:4 -: false; finding: C2; evidence: report item C2
  ticket: none
  text: Nothing here is a key, v2 or Active or sha256.
  correction: none
- claim 5 [code] /x/h.md:5 -: false; finding: C3; evidence: report item C3
  ticket: APP-77
  text: The row is gone.
  correction: none
- claim 6 [code] /x/h.md:6 -: false; finding: none; evidence: the cited file
  text: Wrong id APP-1 with 12 retries (see APP-1, APP-1).
  correction: none
- claim 7 [code] /x/h.md:7 -: false; finding: none; evidence: the cited file
  ticket: github:APP-10
  text: Keeps "unclosed and `also unclosed but 7 rows.
  correction: none
EOF

want="claim 1${tab}owner/app#12${tab}$M/a.md"
want="$want${nl}claim 1${tab}load.users${tab}$M/a.md"
want="$want${nl}claim 1${tab}Soft Delete${tab}$M/a.md"
want="$want${nl}claim 1${tab}0c23936${tab}$M/a.md"
want="$want${nl}claim 1${tab}deadbeef${tab}$M/sub/c.md"
want="$want${nl}claim 1${tab}104${tab}$M/b.md"
want="$want${nl}claim 1${tab}1${tab}$M/sub/c.md"
want="$want${nl}claim 1${tab}1${tab}$M/sub/d.md"
want="$want${nl}claim 1${tab}AB#4567${tab}$M/sub/c.md"
want="$want${nl}claim 4${tab}-${tab}no key"
want="$want${nl}claim 5${tab}APP-77${tab}none"
want="$want${nl}claim 6${tab}APP-1${tab}$M/sub/d.md"
want="$want${nl}claim 6${tab}12${tab}$M/a.md"
want="$want${nl}claim 7${tab}APP-10${tab}none"
want="$want${nl}claim 7${tab}7${tab}none"
run "inline verdicts" 0 "$want" find "$v" "$M"

# A false entry names no key when only words that are not keys remain.
cat > "$tmp/nokey.md" <<'EOF'
- claim 1 [code] /x/h.md:1 -: false; finding: none; evidence: e
  ticket: none
  text: Active v2 sha256 abc 12ab 1.x
EOF
run "no key" 0 "claim 1${tab}-${tab}no key" find "$tmp/nokey.md" "$M"

# A file with no entries, and an empty memory directory.
printf '# Claims verdicts: empty\n' > "$tmp/empty.md"
run "no entries" 0 "" find "$tmp/empty.md" "$M"
mkdir "$tmp/emptydir"
cat > "$tmp/one.md" <<'EOF'
- claim 1 [code] /x/h.md:1 -: false; finding: none; evidence: e
  ticket: APP-1
  text: 104 rows.
EOF
run "empty memory directory" 0 "claim 1${tab}APP-1${tab}none${nl}claim 1${tab}104${tab}none" find "$tmp/one.md" "$tmp/emptydir"

# The same entry with CRLF line endings gives the same output.
cr=$(printf '\r')
while IFS= read -r l; do printf '%s%s\n' "$l" "$cr"; done < "$tmp/one.md" > "$tmp/crlf.md"
run "CRLF verdicts" 0 "claim 1${tab}APP-1${tab}none${nl}claim 1${tab}104${tab}none" find "$tmp/crlf.md" "$tmp/emptydir"

# A quoted span that holds a tab is not a key; the words around it still are.
{
	printf -- '- claim 1 [code] /x/h.md:1 -: false; finding: none; evidence: e\n'
	printf '  ticket: none\n'
	printf '  text: Split `a%sb` stays at 104 rows.\n' "$tab"
} > "$tmp/tabspan.md"
run "tab in a span" 0 "claim 1${tab}104${tab}none" find "$tmp/tabspan.md" "$tmp/emptydir"

# A key holding regex characters matches only itself.
printf 'owner/app#12 a+b\nownerXappX12\n' > "$tmp/emptydir/re.md"
cat > "$tmp/re.md" <<'EOF'
- claim 1 [code] /x/h.md:1 -: false; finding: none; evidence: e
  ticket: none
  text: See `a+b` and `owner.app#12` and "x/y".
EOF
run "regex characters" 0 "claim 1${tab}a+b${tab}$tmp/emptydir/re.md${nl}claim 1${tab}owner.app#12${tab}none${nl}claim 1${tab}x/y${tab}none" find "$tmp/re.md" "$tmp/emptydir"

# A 0.2.0 entry has no ticket: sub-line; the text's literals are the only keys.
cat > "$tmp/old.md" <<'EOF'
- claim 1 [code] /x/h.md:1 -: false; finding: C1; evidence: e
  text: APP-1: type Story; state Active; owner Developer
  correction: none
EOF
run "0.2.0 entry" 0 "claim 1${tab}APP-1${tab}$M/sub/d.md" find "$tmp/old.md" "$M"

# ---------------------------------------------------------------------------
# Lines over 8,192 bytes: a text line and a memory file line that holds a key.
long=$(pad 9000)
LM=$tmp/longmem
mkdir "$LM"
printf '%s APP-9 %s\n' "$long" "$long" > "$LM/long.md"
printf '%s APP-91\n' "$long" > "$LM/other.md"
cat > "$tmp/long.md" <<EOF
- claim 1 [code] /x/h.md:1 -: false; finding: none; evidence: e
  ticket: none
  text: $long APP-9
  correction: none
EOF
run "long lines" 0 "claim 1${tab}APP-9${tab}$LM/long.md" find "$tmp/long.md" "$LM"

# ---------------------------------------------------------------------------
# Usage errors and unreadable input: exit 2, nothing on stdout.
usage_msg="usage: memory.sh find <claims-verdicts.md> <dir>"
run "no arguments" 2 ""
errmsg "no arguments" "$usage_msg"
run "unknown mode" 2 "" check "$v" "$M"
errmsg "unknown mode" "$usage_msg"
run "one argument" 2 "" find "$v"
errmsg "one argument" "$usage_msg"
run "four arguments" 2 "" find "$v" "$M" extra
errmsg "four arguments" "$usage_msg"
run "missing verdicts" 2 "" find "$tmp/none.md" "$M"
errmsg "missing verdicts" "memory: cannot read $tmp/none.md"
run "missing directory" 2 "" find "$v" "$tmp/nodir"
errmsg "missing directory" "memory: cannot read directory $tmp/nodir"
run "directory is a file" 2 "" find "$v" "$M/a.md"
errmsg "directory is a file" "memory: cannot read directory $M/a.md"

# The command never changes a memory file.
before=$(cd "$M" && find . -type f | sort | xargs cat | cksum)
sh "$ms" find "$v" "$M" > /dev/null
after=$(cd "$M" && find . -type f | sort | xargs cat | cksum)
[ "$before" = "$after" ] || fail "memory files changed"

if [ "$fails" -gt 0 ]; then
	exit 1
fi
echo "memory test: ok"
