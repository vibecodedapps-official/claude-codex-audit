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
# - skills/cca/handoff.md and skills/cca/work-items.md exist.
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
for f in skills/cca/handoff.md skills/cca/work-items.md; do
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

if [ "$fails" -gt 0 ]; then
	exit 1
fi
echo "lint: ok"
