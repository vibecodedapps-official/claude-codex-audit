#!/bin/sh
# build.sh <name>: build the fixture <name> (solo, solo-dirty, full, or tokens) in a new
# temp directory and print the absolute path of its manifest on stdout, nothing else.
#
# Usage: sh tests/fixture/build.sh solo | solo-dirty | full | tokens
#
# Every expected outcome is listed as a literal in tests/fixture/expected.md. Git runs
# with fixed identity, fixed commit dates, no global or system config, no signing, and
# no line-ending conversion, so commit ids are the same on every machine. On Windows
# (Git Bash) the printed path is in C:/ form.
set -eu

name=${1:-}
case $name in
solo | solo-dirty | full | tokens) ;;
*)
	echo "build.sh: unknown fixture '$name'; expected solo, solo-dirty, full, or tokens" >&2
	exit 2
	;;
esac

lib=$(cd "$(dirname "$0")/lib" && pwd)
T=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then
	T=$(cygpath -m "$T")
fi

GIT_CONFIG_NOSYSTEM=1
GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL \
	GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

# Keep stdout for the manifest path only.
exec 3>&1 1>/dev/null

g() {
	git -c user.name=fixture -c user.email=fixture@example.invalid \
		-c commit.gpgsign=false -c tag.gpgsign=false -c core.autocrlf=false \
		-c core.safecrlf=false -c init.defaultBranch=main "$@"
}

# init <dir>: a new repo whose first branch is main.
init() {
	g init -q "$T/$1"
	g -C "$T/$1" symbolic-ref HEAD refs/heads/main
}

# commit_index <dir> <message>: commit the index with the next fixed date.
n=0
commit_index() {
	n=$((n + 1))
	GIT_AUTHOR_DATE="2026-09-01 10:$(printf '%02d' "$n"):00 +0000"
	GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
	export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
	g -C "$T/$1" commit -q -m "$2"
}

# commit <dir> <message>: stage everything, then commit.
commit() {
	g -C "$T/$1" add -A
	commit_index "$1" "$2"
}

# put <path>: write stdin to <path> under the fixture directory.
put() {
	mkdir -p "$(dirname "$T/$1")"
	cat > "$T/$1"
}

full=0
[ "$name" = full ] && full=1

# ---------------------------------------------------------------------------
# app: src/users.sh in parts, so each branch writes its own version.
# users_sh <count 0|1> <feature 0|1>
users_sh() {
	cat <<'EOF'
#!/bin/sh
# users.sh: manage the user records in data/users.csv.
set -eu

USERS_FILE=${USERS_FILE:-data/users.csv}

# list_users: print every user row, without the header.
list_users() {
    tail -n +2 "$USERS_FILE"
}
EOF
	if [ "$1" = 1 ]; then
		cat <<'EOF'

# count_users: print the number of users.
count_users() {
    tail -n +2 "$USERS_FILE" | wc -l | tr -d ' '
}
EOF
	fi
	if [ "$2" = 1 ]; then
		cat <<'EOF'

# add_user <id> <name> <email>: append one active user row.
add_user() {
    printf '%s,%s,%s,active\n' "$1" "$2" "$3" >> "$USERS_FILE"
}

# deactivate_user <id>: deactivate the user with this id.
deactivate_user() {
    id=$1
    tmp=$USERS_FILE.tmp
    grep -v "^$id," "$USERS_FILE" > "$tmp"
    mv "$tmp" "$USERS_FILE"
}
EOF
	else
		cat <<'EOF'

# add_user <id> <name> <email>: append one user row.
add_user() {
    printf '%s,%s,%s\n' "$1" "$2" "$3" >> "$USERS_FILE"
}
EOF
	fi
	cat <<'EOF'

case ${1:-} in
list) list_users ;;
EOF
	if [ "$1" = 1 ]; then
		echo 'count) count_users ;;'
	fi
	echo 'add) shift; add_user "$@" ;;'
	if [ "$2" = 1 ]; then
		echo 'deactivate) shift; deactivate_user "$@" ;;'
	fi
	cat <<'EOF'
*) echo "usage: users.sh <command> [args]" >&2; exit 2 ;;
esac
EOF
}

# test_users_sh <migration 0|1> <deactivate 0|1>
test_users_sh() {
	cat <<'EOF'
#!/bin/sh
# Tests for src/users.sh. run-tests.sh runs this file from the repo root.
set -eu

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
USERS_FILE=$work/users.csv
export USERS_FILE

run() {
    cp data/users.csv "$USERS_FILE"
    "$1"
    echo "pass $1"
}

skip() {
    echo "skip $1: $2"
}

test_list_users() {
    [ "$(sh src/users.sh list | wc -l | tr -d ' ')" = 3 ]
}
EOF
	if [ "$1" = 1 ]; then
		cat <<'EOF'

test_migration_adds_status() {
    sh migrations/002_add_status.sh
    [ "$(head -n 1 "$USERS_FILE")" = "id,name,email,status" ]
    [ "$(sed -n 2p "$USERS_FILE")" = "1,Ada,ada@example.invalid,active" ]
}
EOF
	fi
	if [ "$2" = 1 ]; then
		cat <<'EOF'

test_deactivate_keeps_row() {
    sh migrations/002_add_status.sh
    sh src/users.sh deactivate 2
    grep -q '^2,Grace,grace@example.invalid,inactive$' "$USERS_FILE"
}
EOF
	fi
	echo
	echo 'run test_list_users'
	if [ "$1" = 1 ]; then
		echo 'run test_migration_adds_status'
	fi
	if [ "$2" = 1 ]; then
		echo 'skip test_deactivate_keeps_row "flaky on CI, fix after release"'
	fi
}

readme_md() {
	cat <<'EOF'
# users

A small tool that keeps user records in `data/users.csv`.

## Usage

    sh src/users.sh list
EOF
	if [ "$1" = 1 ]; then
		echo '    sh src/users.sh count'
	fi
	cat <<'EOF'
    sh src/users.sh add <id> <name> <email>

## Tests

Run the tests from the repository root:

    sh run-tests.sh

The runner writes its results to `.test-output/results.txt`, which git ignores.
EOF
}

# output_sh <app-3 0|1> <app-4 0|1> <app-5 0|1> (full only)
output_sh() {
	cat <<'EOF'
#!/bin/sh
# output.sh: helpers that print user rows. Source this file.
set -eu

# print_rows <file>: print every row after the header.
print_rows() {
    tail -n +2 "$1"
}
EOF
	if [ "$1" = 1 ]; then
		cat <<'EOF'

# print_page <file> <page> <size>: print one page of rows; pages start at 1.
print_page() {
    size=$3
    start=$((($2 - 1) * size + 2))
    # sed ranges are inclusive, so the page ends at start + size.
    end=$((start + size))
    sed -n "${start},${end}p" "$1"
}
EOF
	fi
	if [ "$2" = 1 ]; then
		cat <<'EOF'

# formatRow <id> <name> <email>: print one record as key=value pairs.
formatRow() {
    printf '%s=%s name=%s email=%s\n' "$KEY_ID" "$1" "$2" "$3"
}
EOF
	fi
	if [ "$3" = 1 ]; then
		cat <<'EOF'

# log_line <text>: print the text after a UTC timestamp.
log_line() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}
EOF
	fi
}

# settings_ini <app-3 0|1> <app-4 0|1>: CRLF line endings on purpose (full only).
settings_ini() {
	printf '[app]\r\nname=users\r\n'
	if [ "$1" = 1 ]; then printf 'page_size=500\r\n'; fi
	if [ "$2" = 1 ]; then printf 'export_keys=short\r\n'; fi
}

build_app() {
	init app

	# Base commit on main: this is the merge-base.
	users_sh 0 0 | put app/src/users.sh
	test_users_sh 0 0 | put app/tests/test_users.sh
	readme_md 0 | put app/README.md
	put app/.gitignore <<'EOF'
.test-output/
EOF
	put app/data/users.csv <<'EOF'
id,name,email
1,Ada,ada@example.invalid
2,Grace,grace@example.invalid
3,Linus,linus@example.invalid
EOF
	put app/run-tests.sh <<'EOF'
#!/bin/sh
# run-tests.sh: run every tests/test_*.sh from the repo root and write the results
# to .test-output/results.txt.
set -eu

mkdir -p .test-output
out=.test-output/results.txt
: > "$out"
fail=0
for t in tests/test_*.sh; do
    if sh "$t" >> "$out" 2>&1; then
        echo "ok $t" >> "$out"
    else
        echo "FAIL $t" >> "$out"
        fail=1
    fi
done
cat "$out"
exit "$fail"
EOF
	put app/migrations/001_create_users.sh <<'EOF'
#!/bin/sh
# 001_create_users.sh: create data/users.csv with its header when it is missing.
set -eu

f=${USERS_FILE:-data/users.csv}
if [ ! -f "$f" ]; then
    mkdir -p "$(dirname "$f")"
    echo "id,name,email" > "$f"
fi
EOF
	if [ "$full" = 1 ]; then
		output_sh 0 0 0 | put app/src/output.sh
		put app/src/export.sh <<'EOF'
#!/bin/sh
# export.sh: write user records in the key=value form the api repo imports:
# user_id=<id> name=<name> email=<email>
set -eu

USERS_FILE=${USERS_FILE:-data/users.csv}

tail -n +2 "$USERS_FILE" | while IFS=, read -r id name email _; do
    printf 'user_id=%s name=%s email=%s\n' "$id" "$name" "$email"
done
EOF
		settings_ini 0 0 | put app/config/settings.ini
		put app/.gitattributes <<'EOF'
config/settings.ini -text
EOF
	fi
	commit app "initial user records tool"

	# Feature branch: ticket APP-1.
	g -C "$T/app" checkout -q -b feature
	put app/migrations/002_add_status.sh <<'EOF'
#!/bin/sh
# 002_add_status.sh: add a status column to data/users.csv, "active" for every row.
set -eu

f=${USERS_FILE:-data/users.csv}

# Already migrated: the header ends in ",status". Rerunning must not add a second
# status column, so exiting 0 here without changes is correct.
if head -n 1 "$f" | grep -q ',status$'; then
    exit 0
fi

tmp=$f.tmp
awk 'NR == 1 { print $0 ",status"; next } { print $0 ",active" }' "$f" > "$tmp"
mv "$tmp" "$f"
EOF
	test_users_sh 1 0 | put app/tests/test_users.sh
	commit app "APP-1: add status column migration"

	users_sh 0 1 | put app/src/users.sh
	test_users_sh 1 1 | put app/tests/test_users.sh
	commit app "APP-1: add deactivate command"

	# The base moves on after the merge-base and touches src/users.sh too.
	g -C "$T/app" checkout -q main
	users_sh 1 0 | put app/src/users.sh
	readme_md 1 | put app/README.md
	commit app "add count command"
	g -C "$T/app" checkout -q feature

	if [ "$full" = 1 ]; then
		output_sh 1 0 0 | put app/src/output.sh
		settings_ini 1 0 | put app/config/settings.ini
		put app/tests/test_output.sh <<'EOF'
#!/bin/sh
# Tests for src/output.sh. run-tests.sh runs this file from the repo root.
set -eu

. src/output.sh

test_print_page() {
    [ "$(print_page data/users.csv 1 5 | wc -l | tr -d ' ')" = 3 ]
}

test_print_page
echo "pass test_print_page"
EOF
		commit app "APP-3: paginate the user list"

		output_sh 1 1 0 | put app/src/output.sh
		settings_ini 1 1 | put app/config/settings.ini
		put app/src/export.sh <<'EOF'
#!/bin/sh
# export.sh: write user records in the key=value form the api repo imports:
# user_id=<id> name=<name> email=<email>, or uid=<id> with export_keys=short.
set -eu

USERS_FILE=${USERS_FILE:-data/users.csv}
. "$(dirname "$0")/output.sh"

keys=$(sed -n 's/^export_keys=//p' config/settings.ini | tr -d '\r')
KEY_ID=user_id
if [ "$keys" = short ]; then
    KEY_ID=uid
fi

tail -n +2 "$USERS_FILE" | while IFS=, read -r id name email _; do
    formatRow "$id" "$name" "$email"
done
EOF
		commit app "APP-4: short export keys as an option"

		output_sh 1 1 1 | put app/src/output.sh
		put app/src/audit-log.sh <<'EOF'
#!/bin/sh
# audit-log.sh <command...>: append one timestamped line to logs/audit.log.
mkdir -p logs
printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> logs/audit.log
EOF
		commit app "APP-5: audit log for commands"
	fi

	# Untracked, not ignored: a draft holding the drift defect's string.
	put app/notes/deactivate-draft.txt <<'EOF'
draft for deactivate, not used:
    grep -v "^$id," "$USERS_FILE" > "$tmp"
EOF
}

write_exports() {
	put exports/APP-1.md <<'EOF'
---
id: APP-1
url: https://tickets.example.invalid/browse/APP-1
title: Deactivate users without deleting them
state: In Progress
description: |
  Add a `deactivate <id>` command to src/users.sh. Deactivation is a soft delete:
  the user's row stays in data/users.csv and its status column is set to
  `inactive`. Add a migration that adds the status column, with the value
  `active` for every existing row.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
	put exports/APP-2.md <<'EOF'
---
id: APP-2
url: https://tickets.example.invalid/browse/APP-2
state: Open
description: Show the number of users above the list output.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
	put session-summary.md <<'EOF'
# Session summary for APP-1

The migration adds a status column whose value is active for every existing row.
The full test suite passes with no skipped tests.
Every existing row was migrated.
EOF
}

write_solo_manifests() {
	put manifest.json <<'EOF'
{
  "bundles": [
    { "repo": "./app", "branch": "feature", "base": "main",
      "tickets": ["file:./exports/APP-1.md"] }
  ],
  "claims": ["./session-summary.md"]
}
EOF
	put manifest-missing-title.json <<'EOF'
{
  "bundles": [
    { "repo": "./app", "branch": "feature", "base": "main",
      "tickets": ["file:./exports/APP-1.md", "file:./exports/APP-2.md"] }
  ],
  "claims": ["./session-summary.md"]
}
EOF
	# Outside every repo, so no commit id changes: a manifest that reads the handoff, a
	# manifest with the scratch key, and the handoff itself.
	put manifest-handoff.json <<'EOF'
{
  "bundles": [
    { "repo": "./app", "branch": "feature", "base": "main",
      "tickets": ["file:./exports/APP-1.md"] }
  ],
  "claims": ["./handoff.md"]
}
EOF
	put manifest-scratch.json <<'EOF'
{
  "bundles": [
    { "repo": "./app", "branch": "feature", "base": "main",
      "tickets": ["file:./exports/APP-1.md"] }
  ],
  "claims": ["./session-summary.md"],
  "scratch": "./app/.test-output"
}
EOF
	put handoff.md <<'EOF'
---
cca-handoff: 1
generated: 2026-09-01T11:00:00Z
---

# Handoff: deactivate users

## Bundles

- app: repo ./app; pr none; branch feature; base main

## Tickets

### APP-1
- type: Story
- state: Active
- iteration: none
- owner: Developer
- bundles: app
- problem: Removing a user deletes the record, so its history is lost.
- decision: Add a deactivate command that keeps the row and sets its status to inactive.
- commits:
  - app 9c5f77c: add the status column migration so every row has a status.
  - app 0c23936: add the deactivate command, which keeps the row and sets its status to inactive.
- verified:
  - Deactivate was checked by hand against a copy of production data; check: not recorded
  - The test suite runs with one test skipped; check: sh run-tests.sh

## Decisions

### D1
- ticket: APP-1
- decision: Deactivate removes the row instead of setting a status.
- rationale: A removed row needs no change to the reads.
- options:
  - chosen: remove the row
  - rejected: keep the row and set a status; why: every read would need a status filter
- decided_by: checkpoint (recommended option taken)
- recorded_at: checkpoint: plan review
- status: default taken

### D2
- ticket: APP-1
- decision: Whether a deactivated user can be reactivated is left for later.
- rationale: not recorded
- options: none recorded
- decided_by: not recorded
- recorded_at: not recorded
- status: deferred

## Raised tickets

### R1
- ticket: APP-6
- type: Bug
- state: New
- iteration: none
- owner: none
- bundles: app
- summary: Add accepts a second row with an id that already exists.
- rank: 1
- in_bundle_confidence: include
- reason: The bundle introduced it when it changed add_user.
EOF
	# Two return-trip files for /cca:handoff --verdicts: one whose heading carries the
	# handoff's own hash, one whose heading carries a stale hash.
	h=$(git hash-object --no-filters "$T/handoff.md")
	verdicts_md "$h" | put claims-verdicts.md
	verdicts_md 0000000000000000000000000000000000000000 | put claims-verdicts-stale.md
}

# verdicts_md <hash>: a claims-verdicts.md for $T/handoff.md, its heading carrying <hash>.
# Claim 1 is a correction whose text matches; claim 3 a correction whose text does not;
# claim 5 contested; claim 6 a recheck request; claim 7 true.
verdicts_md() {
	cat <<EOF
# Claims verdicts: fixture-verdicts

report revision: sha256:0000000000000000000000000000000000000000000000000000000000000000
generated: 2026-09-01T12:00:00Z

Apply a line only when its file hash and claim text match what you hold. \`false\` lines
are corrections: the statement is contradicted by the cited evidence. \`not verified\` lines
on verification claims are recheck requests: the audit could not reproduce the check, which
is not evidence the statement is wrong. \`contested\` lines need a person to decide.

## $T/handoff.md (handoff), hash $1

- claim 1 [status] $T/handoff.md:14 tickets/APP-1/fields: false; finding: none; evidence: exports/APP-1.md gives state In Progress
  text: APP-1: type Story; state Active; iteration none; owner Developer
  correction: APP-1: type Story; state In Progress; iteration none; owner Developer
- claim 3 [code] $T/handoff.md:14 tickets/APP-1/decision: false; finding: C1; evidence: report item C1
  text: Add a deactivate command that keeps the row.
  correction: Add a deactivate command; it deletes the user's row, though the ticket asks for a soft delete.
- claim 5 [code] $T/handoff.md:24 tickets/APP-1/commit/app/0c23936: contested; finding: C1; evidence: report section 10
  text: app 0c23936: add the deactivate command, which keeps the row and sets its status to inactive.
  correction: none
- claim 6 [verification] $T/handoff.md:26 tickets/APP-1/verified/1: not verified; finding: none; evidence: not reproduced, needs a copy of production data
  text: Deactivate was checked by hand against a copy of production data; check: not recorded
  correction: none
- claim 7 [verification] $T/handoff.md:27 tickets/APP-1/verified/2: true; finding: none; evidence: sh run-tests.sh printed the skip line
  text: The test suite runs with one test skipped; check: sh run-tests.sh
  correction: none
EOF
}

# ---------------------------------------------------------------------------
dirty_app() {
	a=$T/app
	# Head commit of feature: attribute probes and a symlink outside the fixture.
	put app/.gitattributes <<'EOF'
tests/test_users.sh export-ignore
VERSION export-subst
probe.txt filter=probe
EOF
	printf '%s\n' 'version $Format:%H$' | put app/VERSION
	put app/probe.txt <<'EOF'
The probe filter must never run on this file.
EOF
	g -C "$a" add .gitattributes VERSION probe.txt
	blob=$(printf '%s' /etc/hosts | g -C "$a" hash-object -w --stdin)
	g -C "$a" update-index --add --cacheinfo "120000,$blob,links/outside"
	commit_index app "add export probes"

	# Leave the checkout on another branch, with local changes.
	g -C "$a" checkout -q -b scratch-branch main
	printf '%s\n' 'Local edit, not committed.' >> "$a/README.md"
	mkdir -p "$a/.test-output"
	printf '%s\n' 'ok tests/test_users.sh' > "$a/.test-output/results.txt"

	# Filter config last, so no command of this build runs it.
	g -C "$a" config filter.probe.smudge "sh -c 'touch \"$T/filter-ran\"; cat'"
	g -C "$a" config filter.probe.process "sh -c 'touch \"$T/filter-ran\"'"
}

# ---------------------------------------------------------------------------
build_api() {
	init api
	put api/README.md <<'EOF'
# api

Imports the user records the app writes with its `src/export.sh`. The contract is
one record per line: `user_id=<id> name=<name> email=<email>`.
EOF
	put api/bin/import-users.sh <<'EOF'
#!/bin/sh
# import-users.sh <file>: import records written by the app's src/export.sh.
# Each record line starts with user_id=.
set -eu

while IFS= read -r line; do
    case $line in
    user_id=*)
        id=${line#user_id=}
        id=${id%% *}
        echo "import $id"
        ;;
    esac
done < "$1"
EOF
	commit api "initial importer"
	g -C "$T/api" checkout -q -b feature
	put api/bin/import-users.sh <<'EOF'
#!/bin/sh
# import-users.sh <file>: import records written by the app's src/export.sh.
# Each record line starts with user_id=.
set -eu

while IFS= read -r line; do
    case $line in
    user_id=*)
        id=${line#user_id=}
        id=${id%% *}
        echo "import $id"
        ;;
    *)
        echo "skip: $line" >&2
        ;;
    esac
done < "$1"
EOF
	commit api "API-1: log skipped import lines"
}

build_legacy() {
	init legacy
	put legacy/bin/users.sh <<'EOF'
#!/bin/sh
# Legacy user tool. Rows: id,name,email,status.
set -eu

USERS_FILE=${USERS_FILE:-users.csv}

case ${1:-} in
list)
    tail -n +2 "$USERS_FILE"
    ;;
esac
EOF
	commit legacy "legacy: list users"
	old=$(g -C "$T/legacy" rev-parse HEAD)
	put legacy/bin/users.sh <<'EOF'
#!/bin/sh
# Legacy user tool. Rows: id,name,email,status.
set -eu

USERS_FILE=${USERS_FILE:-users.csv}

case ${1:-} in
list)
    tail -n +2 "$USERS_FILE"
    ;;
deactivate)
    # Soft delete: the row stays and its status becomes inactive.
    sed "s/^\($2,.*\),active\$/\1,inactive/" "$USERS_FILE" > "$USERS_FILE.tmp"
    mv "$USERS_FILE.tmp" "$USERS_FILE"
    ;;
esac
EOF
	commit legacy "legacy: deactivate keeps the row"
	g -C "$T/legacy" checkout -q --detach "$old"
}

build_guidelines() {
	init guidelines
	for d in style testing security operations data reviews; do
		mkdir -p "$T/guidelines/$d"
	done
	awk -v root="$T/guidelines" -f "$lib/corpus.awk"
	put guidelines/README.md <<'EOF'
# Engineering guidelines

Each directory holds the guidelines for one area. Rule keywords are written in
capitals.
EOF
	put guidelines/style/shell-scripts.md <<'EOF'
# Shell scripts

## Strict mode

Every shell script MUST run `set -eu` before its first command.
EOF
	put guidelines/style/naming.md <<'EOF'
# Naming

## Functions

Function names SHOULD use snake_case, for example `print_rows`, not `printRows`.
EOF
	commit guidelines "guidelines corpus"
}

write_full_exports() {
	put exports/APP-3.md <<'EOF'
---
id: APP-3
url: https://tickets.example.invalid/browse/APP-3
title: Paginate the user list
state: In Progress
description: |
  Add paging to the list output in src/output.sh. The page size comes from
  config/settings.ini, key page_size, default 50. A page shows exactly page_size
  rows.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
	put exports/APP-4.md <<'EOF'
---
id: APP-4
url: https://tickets.example.invalid/browse/APP-4
title: Short export keys as an option
state: In Progress
description: |
  Add a setting export_keys to config/settings.ini. With `short`, src/export.sh
  writes `uid=` instead of `user_id=`. The default is `long`, so the api repo's
  importer keeps working without changes.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
	put exports/APP-5.md <<'EOF'
---
id: APP-5
url: https://tickets.example.invalid/browse/APP-5
title: Audit log for commands
state: In Progress
description: |
  Add src/audit-log.sh, which appends one timestamped line per command to
  logs/audit.log, and a log_line helper in src/output.sh.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
	put exports/API-1.md <<'EOF'
---
id: API-1
url: https://tickets.example.invalid/browse/API-1
title: Log skipped import lines
state: In Progress
description: bin/import-users.sh prints each line it skips to stderr.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
}

write_full_manifests() {
	# $1: extra manifest text (the groups key), or empty.
	cat <<'EOF'
{
  "bundles": [
    { "repo": "./app", "branch": "feature", "base": "main",
      "tickets": ["file:./exports/APP-1.md", "file:./exports/APP-3.md",
                  "file:./exports/APP-4.md", "file:./exports/APP-5.md"] },
    { "repo": "./api", "branch": "feature", "base": "main",
      "tickets": ["file:./exports/API-1.md"] }
  ],
  "references": [
    { "name": "legacy", "path": "./legacy", "ref": "main" }
  ],
  "sources_of_truth": [
    { "rank": 1, "name": "legacy source", "path": "./legacy", "ref": "main" },
    { "rank": 2, "name": "guidelines", "path": "./guidelines", "ref": "main" }
  ],
EOF
	if [ -n "$1" ]; then
		printf '%s\n' "$1"
	fi
	cat <<'EOF'
  "claims": ["./session-summary.md"]
}
EOF
}

# ---------------------------------------------------------------------------
# tokens: one repo whose exported tickets have bare-number ids, and commits that write
# those numbers as ticket references (#4567, [4569], AB#4570) and as other numbers
# (a build number, a row count). Each feature commit touches its own file.
build_tokens() {
	init app
	put app/README.md <<'EOF'
# app

A small tool.
EOF
	put app/src/app.sh <<'EOF'
#!/bin/sh
set -eu
echo app
EOF
	commit app "initial app"

	g -C "$T/app" checkout -q -b feature
	put app/src/input.sh <<'EOF'
#!/bin/sh
# input.sh: reject empty input.
set -eu
[ -n "${1:-}" ] || { echo "empty input" >&2; exit 1; }
EOF
	commit app "fix(#4567 #4568): reject empty input"
	put app/ci/status.txt <<'EOF'
build 4567: passed
EOF
	commit app "build 4567 passed"
	put app/src/report.sh <<'EOF'
#!/bin/sh
# report.sh: print a one-line report.
set -eu
echo "report"
EOF
	commit app "[4569] add the report command"
	put app/config/app.conf <<'EOF'
mode=fast
EOF
	commit app "AB#4570 rename the config key"
	put app/data/migration.txt <<'EOF'
rows: 4567
EOF
	commit app "migrated 4567 rows"

	put exports/4567.md <<'EOF'
---
id: 4567
url: https://tickets.example.invalid/items/4567
title: Reject empty input
state: In Progress
description: The tool must stop with an error when it gets empty input.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
	put exports/4568.md <<'EOF'
---
id: 4568
url: https://tickets.example.invalid/items/4568
title: Name the empty input error
state: In Progress
description: The error for empty input must say that the input is empty.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
	put exports/4569.md <<'EOF'
---
id: 4569
url: https://tickets.example.invalid/items/4569
title: Add a report command
state: In Progress
description: Add a command that prints a one-line report.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
	put exports/4570.md <<'EOF'
---
id: 4570
url: https://tickets.example.invalid/items/4570
title: Rename the mode key
state: In Progress
description: Rename the mode key in the settings.
source: file export
exported_by: fixture
exported_at: 2026-09-29
---
EOF
}

# tokens_manifest <ticket_token JSON value, or empty for no key>
tokens_manifest() {
	cat <<'EOF'
{
  "bundles": [
    { "repo": "./app", "branch": "feature", "base": "main",
EOF
	if [ -n "$1" ]; then
		printf '      "ticket_token": %s,\n' "$1"
	fi
	cat <<'EOF'
      "tickets": ["file:./exports/4567.md", "file:./exports/4568.md",
                  "file:./exports/4569.md", "file:./exports/4570.md"] }
  ]
}
EOF
}

# ---------------------------------------------------------------------------
case $name in
tokens) build_tokens ;;
*)
	build_app
	write_exports
	;;
esac
case $name in
tokens)
	tokens_manifest '' | put manifest.json
	tokens_manifest '["#{n}", "[{n}]", "AB#{n}"]' | put manifest-token.json
	tokens_manifest '"#n"' | put manifest-bad-token.json
	;;
solo)
	write_solo_manifests
	;;
solo-dirty)
	write_solo_manifests
	dirty_app
	;;
full)
	build_api
	build_legacy
	build_guidelines
	write_full_exports
	write_full_manifests '' | put manifest.json
	write_full_manifests '  "groups": [
    { "name": "accounts", "repo": "./app",
      "files": ["src/users.sh", "migrations/**", "tests/test_users.sh"] },
    { "name": "output", "repo": "./app",
      "files": ["src/output.sh", "src/export.sh", "src/audit-log.sh",
                "config/**", "tests/test_output.sh"] }
  ],' | put manifest-groups.json
	;;
esac

printf '%s\n' "$T/manifest.json" >&3
