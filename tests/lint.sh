#!/bin/sh
# lint.sh: static checks for the cca plugin files.
#
# Usage: sh tests/lint.sh [root]
#
# root defaults to $LINT_ROOT, else the repository that holds this script. Use it to
# lint a copy, for example a copy of the tree with Edit added to an agent's tools,
# which must fail.
#
# File list: inside a git work tree whose top level is root, `git ls-files --cached
# --others --exclude-standard` (tracked files plus new files that are not ignored, so
# files a change adds count before they are staged), keeping only files that exist.
# Outside a git work tree, every file under root except .git/.
#
# Checks:
# - commands/audit.md, resume.md, act.md, handoff.md exist; every commands/*.md has
#   frontmatter keys description, argument-hint, allowed-tools.
# - agents/digester.md, mapper.md, auditor.md, adversary.md, merger.md exist; every
#   agents/*.md has frontmatter keys name (equal to the file name), description,
#   model, tools; every tools entry (YAML list, comma string, or [flow list]) is one
#   of Read, Grep, Glob, Bash, Write; and no Edit or NotebookEdit token appears
#   anywhere in the file.
# - skills/cca/SKILL.md has frontmatter keys name, description, and the line
#   `user-invocable: false`; it names each stage file below by path, and every
#   stages/*.md path it mentions exists under skills/cca/.
# - skills/cca/handoff.md, skills/cca/live.md, and skills/cca/work-items.md exist.
# - Every scripts/<name>.sh path that a file under skills/ or commands/ mentions
#   exists under skills/cca/scripts/.
# - .claude-plugin/plugin.json and marketplace.json parse as JSON (node, else
#   python3, else skipped with a note).
# - No file under .claude-plugin/, commands/, skills/, agents/, docs/, or README.md
#   mentions the three planning documents that preceded the implementation. The three
#   documents themselves are not scanned, so the check holds before and after they
#   are removed.
# - No file under agents/, skills/, commands/ mentions `advisor`, except a line that
#   forbids it: one matching (no|never|not)( use)?( the)? `?advisor, any case, such as
#   "no advisor", "never the `advisor`", or "do not use the advisor".
# - Every gh read in a file under agents/, skills/, or commands/ names its host. In a
#   backtick span, a `gh pr <sub>` or `gh issue <sub>` command with at least one
#   argument after <sub> must pass -R or --repo a <host>/<owner>/<repo> value, attached
#   or separated, or an argument that starts with https:// or http:// or is <url>; a
#   `gh api` command with at least one argument must pass --hostname. A command may
#   start anywhere in the span (after a blank, `;`, `|`, `&`, or `(`) and ends at the
#   next `;`, `|`, `&`, or `)`. A single-quoted argument with no blank, `;`, `|`, `&`,
#   or `)` in it counts without its quotes; other single-quoted text is ignored. Without
#   a host, gh uses its default host, which can differ from the bundle's. A span with no
#   argument, such as "`gh api` calls" or "`gh issue view` has no parent field", is
#   prose and does not count, nor does an argument that starts with `*`, as in an
#   allowed-tools pattern. Not checked: a span that runs across lines, and lines inside
#   ``` fenced code blocks. A self-test runs the check on fixed sample lines first and
#   fails when its result differs from the expected one; an awk failure also fails.
#
# Exit 0 when every check passes. Otherwise print one line per failure and exit 1.

set -u

root=${1:-${LINT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}
cd "$root" 2>/dev/null || {
	echo "lint: cannot enter root $root"
	exit 1
}

fails=0
fail() {
	echo "lint: $*"
	fails=$((fails + 1))
}
note() {
	echo "note: $*"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
files=$tmp/files

cdup=$(git rev-parse --show-cdup 2>/dev/null) && in_git=1 || in_git=0
if [ "$in_git" = 1 ] && [ -z "$cdup" ]; then
	git ls-files --cached --others --exclude-standard |
		while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done |
		sort -u > "$files"
else
	[ -e .git ] && note "git cannot list files here; listing every file under $root instead"
	find . -type f ! -path './.git/*' | sed 's|^\./||' | sort -u > "$files"
fi

# The planning documents, assembled so this file does not name them itself.
doc_spec='SPEC''.md'
doc_arch='docs/''architecture.md'
doc_plan='docs/''build-plan'
doc_plan_file='docs/''build-plan-v0.1.0.md'

# frontmatter <file>: print the lines between the opening and closing --- lines.
frontmatter() {
	tr -d '\r' < "$1" | awk '
		NR == 1 { if ($0 ~ /^---[ \t]*$/) next; exit }
		/^---[ \t]*$/ { exit }
		{ print }'
}

# need_keys <file> <key>...: fail for each key missing from the frontmatter.
need_keys() {
	nk_file=$1
	shift
	frontmatter "$nk_file" > "$tmp/fm"
	if [ ! -s "$tmp/fm" ]; then
		fail "$nk_file: no frontmatter block"
		return
	fi
	for nk_key in "$@"; do
		grep -q "^$nk_key:" "$tmp/fm" || fail "$nk_file: frontmatter lacks $nk_key"
	done
}

# hits <file> <message>: read `grep -n` output from stdin and fail once per line,
# naming <file>, the line number, and <message>. Feed it by redirection, not by a
# pipe, so the failure count stays in this shell.
hits() {
	while IFS= read -r hit; do
		echo "lint: $1:${hit%%:*}: $2"
	done > "$tmp/hits"
	if [ -s "$tmp/hits" ]; then
		cat "$tmp/hits"
		fails=$((fails + $(wc -l < "$tmp/hits")))
	fi
}

# tools_of: print one entry per line of the tools key in the frontmatter on stdin,
# written as a YAML list, a comma string, or a [flow, list].
tools_of() {
	awk '
		function out(x) { gsub(/^[ \t"]+|[ \t"]+$/, "", x); if (x != "") print x }
		/^tools:/ {
			t = 1; v = $0; sub(/^tools:[ \t]*/, "", v); gsub(/[][]/, "", v)
			n = split(v, a, ","); for (i = 1; i <= n; i++) out(a[i]); next
		}
		t && /^[ \t]*-/ { v = $0; sub(/^[ \t]*-[ \t]*/, "", v); out(v); next }
		t && /^[ \t]*$/ { next }
		{ t = 0 }' | tr -d "'"
}

# listed <regex>: print the listed files that match an extended regex.
listed() {
	grep -E "$1" "$files" || true
}

# Commands.
for c in audit resume act handoff; do
	grep -qx "commands/$c.md" "$files" || fail "missing: commands/$c.md"
done
for f in $(listed '^commands/[^/]+\.md$'); do
	need_keys "$f" description argument-hint allowed-tools
done

# Agents.
for a in digester mapper auditor adversary merger; do
	grep -qx "agents/$a.md" "$files" || fail "missing: agents/$a.md"
done
for f in $(listed '^agents/[^/]+\.md$'); do
	need_keys "$f" name description model tools
	base=$(basename "$f" .md)
	if [ -s "$tmp/fm" ] && ! grep -qE "^name:[ \t]*['\"]?$base['\"]?[ \t]*$" "$tmp/fm"; then
		fail "$f: frontmatter name is not $base"
	fi
	tools_of < "$tmp/fm" > "$tmp/tools"
	if [ -s "$tmp/fm" ] && [ ! -s "$tmp/tools" ]; then
		fail "$f: tools list is empty"
	fi
	while IFS= read -r t; do
		case $t in
		Read | Grep | Glob | Bash | Write) ;;
		*) fail "$f: tool not allowed: $t (allowed: Read, Grep, Glob, Bash, Write)" ;;
		esac
	done < "$tmp/tools"
	tr -d '\r' < "$f" | grep -nwE 'Edit|NotebookEdit' > "$tmp/grep"
	hits "$f" "mentions Edit or NotebookEdit" < "$tmp/grep"
done

# Skill and stage files.
skill=skills/cca/SKILL.md
if grep -qx "$skill" "$files"; then
	need_keys "$skill" name description
	grep -qE '^user-invocable:[ \t]*false[ \t]*$' "$tmp/fm" ||
		fail "$skill: frontmatter lacks user-invocable: false"
	tr -d '\r' < "$skill" > "$tmp/skill"
	for s in 1-orient 2-digest 3-domain 4-pass-one 5-pass-two 6-second-opinion \
		7-converge 8-report 9-act resume; do
		grep -q "stages/$s\.md" "$tmp/skill" || fail "$skill: does not name stages/$s.md"
	done
	for p in $(grep -oE 'stages/[A-Za-z0-9._-]+\.md' "$tmp/skill" | sort -u); do
		[ -f "skills/cca/$p" ] || fail "missing: skills/cca/$p (named in $skill)"
	done
else
	fail "missing: $skill"
fi

# The handoff and work-item formats, and the scripts the plugin files name.
for f in skills/cca/handoff.md skills/cca/live.md skills/cca/work-items.md; do
	grep -qx "$f" "$files" || fail "missing: $f"
done
for f in $(listed '^(skills|commands)/'); do
	for p in $(tr -d '\r' < "$f" | grep -oE 'scripts/[A-Za-z0-9._-]+\.sh' | sort -u); do
		[ -f "skills/cca/$p" ] || fail "$f: names skills/cca/$p, which does not exist"
	done
done

# Plugin manifests.
if command -v node >/dev/null 2>&1; then
	json_check() { node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$1" 2>/dev/null; }
elif command -v python3 >/dev/null 2>&1; then
	json_check() { python3 -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$1" 2>/dev/null; }
else
	json_check() { return 0; }
	note "neither node nor python3 found; JSON parse check skipped"
fi
for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
	if grep -qx "$j" "$files"; then
		json_check "$j" || fail "$j: does not parse as JSON"
	else
		fail "missing: $j"
	fi
done

# No references to the planning documents.
for f in $(listed '^(\.claude-plugin/|commands/|skills/|agents/|docs/|README\.md$)'); do
	case $f in "$doc_spec" | "$doc_arch" | "$doc_plan_file") continue ;; esac
	tr -d '\r' < "$f" | grep -nF -e "$doc_spec" -e "$doc_arch" -e "$doc_plan" > "$tmp/grep"
	hits "$f" "names a removed planning document" < "$tmp/grep"
done

# No advisor, except a line that forbids it.
for f in $(listed '^(agents|skills|commands)/'); do
	tr -d '\r' < "$f" | grep -ni 'advisor' |
		grep -viE '(no|never|not)( use)?( the)? `?advisor' > "$tmp/grep"
	hits "$f" "mentions advisor" < "$tmp/grep"
done

# gh_spans <kind>: read a file on stdin and print `<line>:` once per line that holds a
# backtick span with a gh command of that kind naming no host. Only spans opened and
# closed on the same line are read, and lines inside ``` fenced code blocks are skipped.
# In a span, a single-quoted argument that holds no blank, `;`, `|`, `&`, or `)` loses
# its quotes; other single-quoted text is blanked. Each command starts at `gh` (at the
# span's start or after a blank, `;`, `|`, `&`, or `(`) and runs to the next `;`, `|`,
# `&`, or `)`. Kind repo: `gh pr <sub>` or `gh issue <sub>` with at least one argument
# after <sub> passes neither -R nor --repo a <host>/<owner>/<repo> value (attached or
# separated) nor an argument that starts with https:// or http:// or is <url>. Kind api:
# `gh api` with at least one argument lacks --hostname. An argument that starts with `*`
# (as in an allowed-tools pattern) does not count. The patterns are string regexes,
# since BSD awk ends a regex literal at a slash inside a bracket.
gh_spans() {
	awk -v kind="$1" '
		BEGIN {
			quoted = "\047[^\047]*\047"
			start = "(^|[ \t;|&(])gh[ \t]"
			sub_arg = "^gh[ \t]+(pr|issue)[ \t]+[A-Za-z-]+[ \t]+[^ \t*]"
			api_arg = "^gh[ \t]+api[ \t]+[^ \t*]"
			repo3 = "[ \t](-R|--repo)[ \t=]*[^ \t/]+/[^ \t/]+/[^ \t/]+"
			url = "[ \t](https://|http://|<url>([ \t]|$))"
		}
		/^[ \t]*```/ { fence = !fence; next }
		fence { next }
		{
			n = split($0, a, "`")
			bad = 0
			for (i = 2; i < n; i += 2) {
				s = a[i]
				out = ""
				while (match(s, quoted)) {
					q = substr(s, RSTART + 1, RLENGTH - 2)
					if (q == "" || q ~ "[ \t;|&)]") q = "Q"
					out = out substr(s, 1, RSTART - 1) q
					s = substr(s, RSTART + RLENGTH)
				}
				s = out s
				while (match(s, start)) {
					s = substr(s, RSTART)
					if (substr(s, 1, 2) != "gh") s = substr(s, 2)
					c = s
					if (match(c, "[;|&)]")) c = substr(c, 1, RSTART - 1)
					if (kind == "repo" && c ~ sub_arg && c !~ repo3 && c !~ url) bad = 1
					if (kind == "api" && c ~ api_arg && !index(c, "--hostname")) bad = 1
					s = substr(s, 3)
				}
			}
			if (bad) print NR ":"
		}'
}

# Self-test of gh_spans on fixed lines, against fixed expected line numbers.
cat > "$tmp/gh-sample" <<'SAMPLE'
`gh api` GET calls and `gh issue view` has no parent field
`gh pr view <n> -R <host>/<owner>/<repo> --json x`
`gh api --hostname <host> --paginate repos/o/r/pulls/1/comments`
`gh api --hostname <host> graphql -f query='x y'`
`gh pr view <id> --json baseRefName`
`gh pr view 1 -R o/r --json x` and `gh api repos/o/r`
`gh issue view 1 --repo=o/r`
`gh api graphql -f a=b`
`Bash(gh pr view *)` and `Bash(gh api *)`
`gh issue view <n> --json title`
`gh pr diff 5 -R o/r`
`gh pr view 5 -Ro/r`
`gh api search/issues -f q=x`
`set -o pipefail; gh api repos/o/r/pulls`
`gh pr view <url> --json baseRefName`
`gh pr view https://github.com/o/r/pull/1`
`gh pr view 5 -Rh/o/r` and `gh issue view 5 --repo=h/o/r`
`jq . | gh api --hostname h repos/x`
`gh api --jq '.[] | gh api repos/x' --hostname h repos/o`
`gh pr` commands
`x=$(gh api repos/o/r)`
`ghost api x`
`gh pr view 7 -R 'github.com/o/r'`
`gh pr view 'https://github.com/o/r/pull/1' --json url`
`x` then `gh pr view 5 --json a`
`gh pr view 5 --jq '.url | test("https://x")'`
`gh pr view 5 --body x-https://y`
```sh
`gh api repos/o/r`
```
`gh issue view 5 -R h/o/r`
SAMPLE
gh_got=$(gh_spans repo < "$tmp/gh-sample" | tr '\n' ' ')
[ "$gh_got" = "5: 6: 7: 10: 11: 12: 25: 26: 27: " ] ||
	fail "tests/lint.sh: gh host self-test, kind repo: got lines $gh_got"
gh_got=$(gh_spans api < "$tmp/gh-sample" | tr '\n' ' ')
[ "$gh_got" = "6: 8: 13: 14: 21: " ] ||
	fail "tests/lint.sh: gh host self-test, kind api: got lines $gh_got"

# Every gh read names its host.
for f in $(listed '^(agents|skills|commands)/'); do
	tr -d '\r' < "$f" | gh_spans repo > "$tmp/grep" ||
		fail "$f: gh host check (repo) did not run"
	hits "$f" "gh pr or gh issue names no host; pass -R <host>/<owner>/<repo> or a URL" < "$tmp/grep"
	tr -d '\r' < "$f" | gh_spans api > "$tmp/grep" ||
		fail "$f: gh host check (api) did not run"
	hits "$f" "gh api names no host; add --hostname <host>" < "$tmp/grep"
done

if [ "$fails" -gt 0 ]; then
	exit 1
fi
echo "lint: ok"
