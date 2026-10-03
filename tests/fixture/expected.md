# Fixture expected outcomes

`sh tests/fixture/build.sh <name>` builds `solo`, `solo-dirty`, `full`, `tokens`, or
`patterns` in a new temp directory and prints the absolute path of its manifest, nothing else. Below, `$F`
is that directory (the manifest's directory). Every value here is a literal. A value
changes only with a recorded reason: change `build.sh` and this file in the same commit,
and say why in the commit body.

`sh tests/fixture/verify.sh <manifest path> [name]` checks the key literals below against
a built fixture with git commands (commit ids, the two-dot and three-dot diffs, the
skipped test, the solo-dirty symlink, branch, and `filter-ran`, the `MUST` rule, the
legacy ids, the CRLF bytes, the three tickets on `src/output.sh`, and, for `solo` and
`solo-dirty`, that the five handoff files and `manifest-working-tree.json` exist, the
handoff's hash and each verdicts file's heading hash below, and that `handoff.sh claims`
gives the claim count per kind below; for `tokens`, its commit ids and messages, files,
exports, and the `ticket_token` lines of its manifests; and, for `patterns`, its commit
ids, files, exports, and `run_once` line, plus four behavior checks run in temp copies)
and prints one line per mismatch. CI runs it after each build. Its expected values are copies of the literals
here, so a change to one changes the other.

The builder fixes the git identity (`fixture <fixture@example.invalid>`), the commit
dates (`2026-09-01 10:<n>:00 +0000`, one minute per commit in build order), and turns off
global and system config, signing, and line-ending conversion. Commit ids are therefore
the same on every machine and are listed as literals (checked on Git Bash for Windows and
on Ubuntu with dash, gawk, and mawk).

## solo

### Layout

| Path | What it is |
|---|---|
| `$F/manifest.json` | One bundle: `./app`, branch `feature`, base `main`, ticket `file:./exports/APP-1.md`, claims `./session-summary.md` |
| `$F/manifest-missing-title.json` | The same bundle with tickets `file:./exports/APP-1.md` and `file:./exports/APP-2.md` |
| `$F/exports/APP-1.md` | Ticket export with id, url, title, state, description, source, exported_by, exported_at; no `acceptance_criteria` |
| `$F/exports/APP-2.md` | Ticket export with no `title` |
| `$F/session-summary.md` | The claims file |
| `$F/manifest-handoff.json` | `manifest.json` with `"claims": ["./handoff.md"]` |
| `$F/manifest-scratch.json` | `manifest.json` with `"scratch": "./app/.test-output"` added |
| `$F/manifest-working-tree.json` | `manifest.json` with `"head": "working-tree"` in the bundle; outside every repo, so no commit id changes |
| `$F/handoff.md` | The handoff, in the format of `skills/cca/handoff.md` (see "Handoff" below) |
| `$F/claims-verdicts.md` | A return-trip file for `$F/handoff.md`, its heading carrying the handoff's hash (see "Verdicts" below) |
| `$F/claims-verdicts-stale.md` | The same lines, its heading carrying a stale hash |
| `$F/app` | The app repo, checked out on `feature`, no tracked changes |

### Commits

| Commit | Id | Branch | Files |
|---|---|---|---|
| `initial user records tool` | `bd5d5e1e67a1fc55adeaa1452920245b1d368f7f` | merge-base | `.gitignore`, `README.md`, `data/users.csv`, `migrations/001_create_users.sh`, `run-tests.sh`, `src/users.sh`, `tests/test_users.sh` |
| `APP-1: add status column migration` | `9c5f77ce3ab9e36fff5bc6b12a230c26688316bf` | feature | `migrations/002_add_status.sh`, `tests/test_users.sh` |
| `APP-1: add deactivate command` | `0c23936980b254c4abd489d3ecfd296f5e7bc0db` | feature head | `src/users.sh`, `tests/test_users.sh` |
| `add count command` | `2b5e8f3511e25bc0225ffc4ef6957dcca51d9fcd` | main head, the base's later commit | `README.md`, `src/users.sh` |

- Merge-base: `bd5d5e1e67a1fc55adeaa1452920245b1d368f7f`.
- Commits on the base since the merge-base: `2b5e8f3511e25bc0225ffc4ef6957dcca51d9fcd`
  (`add count command`).
- File changed on both sides since the merge-base: `src/users.sh`.
- Changed files (three-dot): `migrations/002_add_status.sh`, `src/users.sh`,
  `tests/test_users.sh`; 3 files changed, 40 insertions(+), 2 deletions(-).

### Expected outcomes

- Ticket ids: `APP-1` (in the main manifest), `APP-2` (only in
  `manifest-missing-title.json`).
- Groups: one ticket group for `APP-1` holding all three changed files; no
  `cross-cutting` group. Tier `low`.
- Drift defect, high, against `APP-1`: the ticket asks for a soft delete (the row stays,
  status set to `inactive`); `deactivate_user` in `src/users.sh` line 21 deletes the row.
  Drift string: `grep -v "^$id," "$USERS_FILE"` (full line
  `    grep -v "^$id," "$USERS_FILE" > "$tmp"`).
- Skipped test: `test_deactivate_keeps_row` in `tests/test_users.sh`, skipped at line 38
  with reason `flaky on CI, fix after release`. It is the test that would catch the drift.
- Decoy: `migrations/002_add_status.sh` line 10, `    exit 0`. It looks like the
  migration quits without migrating; it is correct, because it runs only when the header
  already ends in `,status`, which makes a rerun safe. The comment on lines 7 and 8 says so.
  Expected: `dismissed` with a reason, or absent; it never counts.
- Claims file `session-summary.md`, three sentences after the heading:
  - True claim: `The migration adds a status column whose value is active for every existing row.`
  - False claim: `The full test suite passes with no skipped tests.` (one test is skipped)
  - Claim only production data can settle: `Every existing row was migrated.` Expected:
    `unverified assumption` with a `live check` field, listed in Live checks, counted no
    higher than `medium`.
- Test command: `sh run-tests.sh` (named in `README.md`). It exits 0 and writes the
  ignored file `.test-output/results.txt` (`.gitignore` line 1: `.test-output/`). Its
  output:

  ```
  pass test_list_users
  pass test_migration_adds_status
  skip test_deactivate_keeps_row: flaky on CI, fix after release
  ok tests/test_users.sh
  ```

- Untracked, not ignored: `notes/deactivate-draft.txt`, line 2 holds the drift string.
- `manifest-missing-title.json` stops before stage 1 with `export <path>: missing title`,
  where `<path>` names `exports/APP-2.md`.
- The main manifest runs, and the brief lists `acceptance_criteria` for `APP-1` as
  "not in export".

### Handoff

The five handoff files sit outside every repo, so no commit id above changes. `solo-dirty`
builds on `solo` and has the same five files. `full` has none of them, because its app
commit ids differ.

`handoff.md` holds one bundle `app` (repo `./app`, pr `none`, branch `feature`, base
`main`), the ticket `APP-1` (bundle `app`), decisions `D1` and `D2`, and the raised ticket
`R1`. The commits it lists are the `solo` commits `9c5f77c` and `0c23936`. It passes
`handoff.sh check`. The lines that matter:

| Item | Content | Truth in the fixture |
|---|---|---|
| `APP-1` state | `Active` | False: the export says `In Progress` |
| `APP-1` decision | keeps the row and sets its status to inactive | False: `deactivate_user` deletes the row |
| commit `0c23936` | says it keeps the row | False, for the same reason |
| verified 1 | `Deactivate was checked by hand against a copy of production data; check: not recorded` | Cannot be reproduced |
| verified 2 | `The test suite runs with one test skipped; check: sh run-tests.sh` | True when run |
| `D1` | deactivate removes the row; rejected: keep the row; `decided_by: checkpoint (recommended option taken)`; `recorded_at: checkpoint: plan review`; `status: default taken` | Describes the code |
| `D2` | whether a deactivated user can be reactivated is left for later; `options: none recorded`; `decided_by: not recorded`; `recorded_at: not recorded`; `status: deferred` | An open deferral with no owner |
| `R1` | ticket `APP-6`, bundle `app`, "add accepts a second row with an id that already exists", rank 1, `include`, reason "the bundle introduced it when it changed add_user" | Predates the bundle |

`sh skills/cca/scripts/handoff.sh claims $F/handoff.md` prints these 11 claims, 4 `code`,
2 `verification`, 2 `decision`, 1 `scope`, 2 `status`. Fields are separated by one tab,
written `<TAB>` here:

```
status<TAB>tickets/APP-1/fields<TAB>app<TAB>APP-1<TAB>14<TAB>APP-1: type Story; state Active; iteration none; owner Developer
code<TAB>tickets/APP-1/problem<TAB>app<TAB>APP-1<TAB>14<TAB>Removing a user deletes the record, so its history is lost.
code<TAB>tickets/APP-1/decision<TAB>app<TAB>APP-1<TAB>14<TAB>Add a deactivate command that keeps the row and sets its status to inactive.
code<TAB>tickets/APP-1/commit/app/9c5f77c<TAB>app<TAB>APP-1<TAB>23<TAB>app 9c5f77c: add the status column migration so every row has a status.
code<TAB>tickets/APP-1/commit/app/0c23936<TAB>app<TAB>APP-1<TAB>24<TAB>app 0c23936: add the deactivate command, which keeps the row and sets its status to inactive.
verification<TAB>tickets/APP-1/verified/1<TAB>app<TAB>APP-1<TAB>26<TAB>Deactivate was checked by hand against a copy of production data; check: not recorded
verification<TAB>tickets/APP-1/verified/2<TAB>app<TAB>APP-1<TAB>27<TAB>The test suite runs with one test skipped; check: sh run-tests.sh
decision<TAB>decisions/D1<TAB>app<TAB>APP-1<TAB>31<TAB>Deactivate removes the row instead of setting a status. | rationale: A removed row needs no change to the reads. | options: chosen: remove the row; rejected: keep the row and set a status; why: every read would need a status filter | decided_by: checkpoint (recommended option taken) | recorded_at: checkpoint: plan review | status: default taken
decision<TAB>decisions/D2<TAB>app<TAB>APP-1<TAB>42<TAB>Whether a deactivated user can be reactivated is left for later. | rationale: not recorded | options: none recorded | decided_by: not recorded | recorded_at: not recorded | status: deferred
scope<TAB>raised/R1<TAB>app<TAB>APP-6<TAB>53<TAB>APP-6: Add accepts a second row with an id that already exists. | rank 1, include: The bundle introduced it when it changed add_user.
status<TAB>raised/R1/fields<TAB>app<TAB>APP-6<TAB>53<TAB>APP-6: type Bug; state New; iteration none; owner none
```

`sh skills/cca/scripts/handoff.sh commits $F/handoff.md` prints
`app<TAB>9c5f77c<TAB>APP-1<TAB>23` and `app<TAB>0c23936<TAB>APP-1<TAB>24`.

Expected audit outcomes, each only when the stage that judges it completes:

- The `APP-1` state claim, the `APP-1` decision claim, and the `0c23936` commit claim are
  judged false, with the export and `src/users.sh` as the evidence.
- Verified 1 is never `true`. It is `not verified, not reproduced`, and appears in
  `claims-verdicts.md` as a recheck request, not a correction.
- Verified 2 is `true, reproduced` when the auditor ran `sh run-tests.sh` in the
  direct-read `solo` tree; it is `not verified, not reproduced` when that run was not made.
- `D1` is classed `needs owner (not recorded)`: deleting rows is hard to reverse, and no
  person decided.
- `D2` is classed `stale deferral`.
- `R1` is judged `introduced by the bundle: no`, because `add_user` at the merge-base
  `bd5d5e1e67a1fc55adeaa1452920245b1d368f7f` already appends without an id check, and
  `facts disagree with the handoff: yes`. The recommendation itself is not asserted.
- With `manifest-scratch.json`, the run directory lands under `app/.test-output/cca/`.
- With `manifest-working-tree.json`, stage 1 builds the head from the working tree
  (`working-tree.sh build $F/app`, with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`):
  head `1fcf8c53acc3f6e064fcb29ec0a05963b4949f2a`, parent
  `0c23936980b254c4abd489d3ecfd296f5e7bc0db`, tree
  `44cdf018ff3489bd74ad79d5cd4e74b76ff56773`, and one untracked file,
  `notes/deactivate-draft.txt`. The brief lists that file as untracked at audit time and
  maps the app as `direct (working tree)`; `.git/index` is unchanged at the end, and
  Coverage discloses the object writes, that the head has no ref, and the untracked
  file. The file is part of the head, so citing it at the head sha is valid evidence
  here, unlike in an audit of `manifest.json`.

### Verdicts

`git hash-object --no-filters $F/handoff.md` is `36b30bd89b131ec1eed669ab0a0c58bbc9c5aaa8`.
`claims-verdicts.md` holds one claims file heading,
`## $F/handoff.md (handoff), hash 36b30bd89b131ec1eed669ab0a0c58bbc9c5aaa8`, and five
entries, each a main line with `ticket:`, `text:`, and `correction:` sub-lines (`ticket:` is
`APP-1` in all five, the ticket field `handoff.sh claims` prints for each claim):

| Claim | Ref | Verdict | Its `text:` | Expected handling |
|---|---|---|---|---|
| 1 | `tickets/APP-1/fields` | `false` | matches the handoff | applied: the correction (state `In Progress`) is used |
| 3 | `tickets/APP-1/decision` | `false` | does not match the handoff (`Add a deactivate command that keeps the row.`) | reconciliation work, not applied |
| 5 | `tickets/APP-1/commit/app/0c23936` | `contested` | matches | reconciliation work, not applied |
| 6 | `tickets/APP-1/verified/1` | `not verified` | matches | a recheck request: the entry stays under `verified`, its `check:` unchanged unless the session rechecked it |
| 7 | `tickets/APP-1/verified/2` | `true` | matches | nothing to apply |

`claims-verdicts-stale.md` holds the same entries under the heading hash
`0000000000000000000000000000000000000000`, which matches no file, so every entry is
reconciliation work and none is applied.

Expected outcomes of
`/cca:handoff $F/manifest-handoff.json --verdicts <file> --out <output>`, run in a
session whose repository is `$F/app`, each only when the command completes. Paths are
absolute because relative ones resolve against `$F/app`, and `--out` is given because the
fixture app has no scratch directory. `<output>` is a file under `$F` that does not exist
yet, such as `$F/handoff-verdicts.md`; the command writes it:

- With `$F/claims-verdicts.md`: the corrections applied list claim 1 and nothing else; the
  reconciliation list holds claims 3 and 5; the new handoff keeps the verified 1 entry;
  claim 7 is in neither list.
- With `$F/claims-verdicts-stale.md`: no correction is applied, and the reconciliation list
  holds all five claims, each with the hash mismatch as the reason.

### Traps that must not appear

- A finding that the feature deleted or removed `count_users`, the `count` command, or
  the README `count` line. Those come from the base's later commit and show only in a
  two-dot diff.
- A citation of `notes/deactivate-draft.txt` (untracked; invalid evidence).
- The decoy counted as a defect.

### Verify

```sh
A="git -C $F/app"
$A merge-base main feature                  # bd5d5e1e67a1fc55adeaa1452920245b1d368f7f
$A log --format='%H %s' bd5d5e1..main       # 2b5e8f3... add count command
$A diff --name-only bd5d5e1 main            # README.md, src/users.sh
$A diff --name-only main...feature          # migrations/002_add_status.sh, src/users.sh, tests/test_users.sh
$A diff main...feature --stat               # 3 files changed, 40 insertions(+), 2 deletions(-)
$A diff main..feature | grep count_users    # three lines starting with '-': the fake reversal
$A diff main...feature | grep -c count_users   # 0
$A rev-parse --abbrev-ref HEAD              # feature
$A status --porcelain                       # ?? notes/
$A check-ignore .test-output/results.txt    # .test-output/results.txt
grep -n 'grep -v' $F/app/src/users.sh $F/app/notes/deactivate-draft.txt
grep -n 'exit 0' $F/app/migrations/002_add_status.sh     # 10:    exit 0
grep -n '^skip ' $F/app/tests/test_users.sh              # 38:skip test_deactivate_keeps_row ...
grep -c '^title:' $F/exports/APP-2.md                    # 0
grep -c '^acceptance_criteria:' $F/exports/APP-1.md      # 0
```

## solo-dirty

Everything in `solo`, then the changes below. Commits from `solo` keep their ids.

### Head commit of `feature`

`add export probes`, id `6d2c9a58b52f0cd66760feefd29b1d1915d92045`, parent
`0c23936980b254c4abd489d3ecfd296f5e7bc0db`. It adds:

| Path | Content |
|---|---|
| `.gitattributes` | `tests/test_users.sh export-ignore`, `VERSION export-subst`, `probe.txt filter=probe` |
| `VERSION` | `version $Format:%H$` |
| `probe.txt` | one line of text, attribute `filter=probe` |
| `links/outside` | mode `120000` (symlink), target `/etc/hosts` |

### Checkout state

- Checked out on `scratch-branch`, which points at main
  (`2b5e8f3511e25bc0225ffc4ef6957dcca51d9fcd`), not at `feature`.
- Modified tracked file: `README.md`, last line `Local edit, not committed.`
- Untracked file: `notes/deactivate-draft.txt` (the one from `solo`; no second one).
- Ignored file present: `.test-output/results.txt`, content `ok tests/test_users.sh`.
- Local config: `filter.probe.smudge` = `sh -c 'touch "$F/filter-ran"; cat'` and
  `filter.probe.process` = `sh -c 'touch "$F/filter-ran"'`, with `$F` written as an
  absolute path. The build sets them last, and no build command runs them, so
  `$F/filter-ran` does not exist after the build. A checkout of `feature` in a copy of
  the repo creates it, which shows the probe is live.

### Expected outcomes

- The app is read from an export under `trees/`; the dirty checkout is unchanged at the end.
- In the export: `tests/test_users.sh` is present (export-ignore not honored), `VERSION`
  still reads `version $Format:%H$`, and `links/outside` is a regular file whose
  content is `/etc/hosts`; the brief lists `links/outside`.
- `$F/filter-ran` does not exist after the run.
- Appending a line to `README.md`, to `notes/deactivate-draft.txt`, or to
  `.test-output/results.txt`, or deleting `.test-output/results.txt`, between two
  stages ends the run `blocked` and names the path.
- After a clean stage, `baseline/1-check.md` lists no ignored-file differences.
- With `manifest-working-tree.json`, the run stops before stage 1 with
  `bundle app: head working-tree needs feature checked out, found scratch-branch`,
  since the checkout is on `scratch-branch`, not `feature`.

### Traps that must not appear

- `$F/filter-ran` existing after a run.
- `VERSION` in the export holding a commit id instead of `$Format:%H$`.
- `tests/test_users.sh` missing from the export.
- The content of `/etc/hosts` anywhere in the run directory.

### Verify

```sh
A="git -C $F/app"
$A rev-parse --abbrev-ref HEAD           # scratch-branch
$A status --porcelain                    # " M README.md" and "?? notes/"
$A status --porcelain --ignored | grep '^!!'   # !! .test-output/
ls -la $F/app/.test-output               # results.txt
$A rev-parse feature                     # 6d2c9a58b52f0cd66760feefd29b1d1915d92045
$A ls-tree feature links/outside         # 120000 blob ... links/outside
$A cat-file -p feature:links/outside     # /etc/hosts
$A show feature:VERSION                  # version $Format:%H$
$A show feature:.gitattributes
$A config --local --get filter.probe.smudge
ls $F/filter-ran                         # No such file or directory
```

## full

Everything in `solo` (app with extra files and commits, ticket exports, claims file),
plus the repos `api`, `legacy`, and `guidelines`. There is no
`manifest-missing-title.json`. The app's commit ids differ from `solo`, because its base
commit has more files.

### Layout

| Path | What it is |
|---|---|
| `$F/manifest.json` | Bundles `./app` (tickets `APP-1`, `APP-3`, `APP-4`, `APP-5`) and `./api` (ticket `API-1`), each branch `feature`, base `main`; reference `legacy` (`./legacy`, ref `main`); sources of truth rank 1 `legacy source` (`./legacy`, ref `main`), rank 2 `guidelines` (`./guidelines`, ref `main`); claims `./session-summary.md` |
| `$F/manifest-groups.json` | The same plus a `groups` key with two entries: `accounts` and `output` |
| `$F/exports/` | `APP-1.md`, `APP-2.md`, `APP-3.md`, `APP-4.md`, `APP-5.md`, `API-1.md` |
| `$F/app` | On `feature`, no tracked changes, untracked `notes/deactivate-draft.txt` |
| `$F/api` | On `feature`, clean |
| `$F/legacy` | Detached at an older commit than `main` |
| `$F/guidelines` | On `main`, clean, about 1 MB of markdown |

### app commits

| Commit | Id | Files |
|---|---|---|
| `initial user records tool` (merge-base) | `6b27db42e063b1881b90f0b4c277d0a8ce2f3ab3` | solo's files plus `.gitattributes`, `config/settings.ini`, `src/export.sh`, `src/output.sh` |
| `APP-1: add status column migration` | `909a5186760b952463e561b7b8ffa254fe9774fe` | `migrations/002_add_status.sh`, `tests/test_users.sh` |
| `APP-1: add deactivate command` | `b56d1014729f12dc419e848564d5a908c93a4c67` | `src/users.sh`, `tests/test_users.sh` |
| `add count command` (main head) | `5a6d60c0a485e6a069f04e0f73f8dfedcb498ff2` | `README.md`, `src/users.sh` |
| `APP-3: paginate the user list` | `f543701150a8c73173285750243dec598fe9c998` | `config/settings.ini`, `src/output.sh`, `tests/test_output.sh` |
| `APP-4: short export keys as an option` | `262fad8c7cc3f312ecf6a119259882a86bb0dd00` | `config/settings.ini`, `src/export.sh`, `src/output.sh` |
| `APP-5: audit log for commands` (feature head) | `191e0ad183ea7509077bff3fd3b462d57d4b70e1` | `src/audit-log.sh`, `src/output.sh` |

Changed files (three-dot): `config/settings.ini`, `migrations/002_add_status.sh`,
`src/audit-log.sh`, `src/export.sh`, `src/output.sh`, `src/users.sh`,
`tests/test_output.sh`, `tests/test_users.sh`.

### Other repos

- api: main `9b9c1d5ed3a4b4c2cfa14b2f7175c8907656242e` (`initial importer`, the
  merge-base), feature head `a3e9b3223c3c82385d1d9f197d5f02323efdd116`
  (`API-1: log skipped import lines`, changes `bin/import-users.sh`, 3 insertions).
- legacy: `main` is `b3b208f6b760091e46d601739e93d43ee9f0bce7`
  (`legacy: deactivate keeps the row`); the checkout is detached at
  `2f21951b0c72eba8ccf5b3db9b4481ade113f8bd` (`legacy: list users`), which has no
  `deactivate`. Pinned ref `main`.
- guidelines: 57 tracked files, 1,116,252 bytes of markdown in all, in `style/`,
  `testing/`, `security/`, `operations/`, `data/`, `reviews/`, plus `README.md`; one
  commit, `guidelines corpus`, id `cfda47bf5fddf8bd2e82d8da1892391aabc68580`.

### Expected outcomes

Everything listed for `solo` about `APP-1` holds (drift, skipped test, decoy, claims),
with the line numbers given there. In addition:

- Ticket ids: `APP-1`, `APP-3`, `APP-4`, `APP-5` (app), `API-1` (api).
- The `MUST` rule, the only line with `MUST` in the corpus:
  `` Every shell script MUST run `set -eu` before its first command. ``, at
  `style/shell-scripts.md` line 5. The app breaks it in `src/audit-log.sh` (added by
  `APP-5`), which has no `set -eu`; every other `.sh` file in the app has it. The
  finding cites `style/shell-scripts.md` at the guidelines' pinned sha, not a digest.
- API break, found by the interaction auditor: `config/settings.ini` sets
  `export_keys=short` (line 4, `APP-4`), so `src/export.sh` writes `uid=<id>` (line 12,
  `KEY_ID=uid`) instead of `user_id=<id>`; api `bin/import-users.sh` reads only
  `user_id=` lines (line 8), so it imports nothing and, on `feature`, logs every record
  as `skip:`. `APP-4` also asked for the default `long`, so it is drift too.
- Legacy is read from an export at `b3b208f6b760091e46d601739e93d43ee9f0bce7`, not its
  checkout; its `deactivate` keeps the row and sets status `inactive`, which supports the
  `APP-1` drift finding.
- File touched by three tickets: `src/output.sh` (`APP-3`, `APP-4`, `APP-5`). It goes to
  `cross-cutting` and is listed in each former group with a note. Expected derived
  groups: `APP-1` (`migrations/002_add_status.sh`, `src/users.sh`,
  `tests/test_users.sh`), `APP-3` (`config/settings.ini`, `tests/test_output.sh`),
  `APP-4` (`config/settings.ini`, `src/export.sh`), `APP-5` (`src/audit-log.sh`),
  `cross-cutting` (`src/output.sh`), and the api's ticket group `API-1`
  (`bin/import-users.sh`). No merge: `APP-3` and `APP-4` each have exactly half their
  files in the other.
- With `manifest-groups.json`: exactly the groups `accounts`, `output`, and
  `unticketed` (`unticketed` holds the api's `bin/import-users.sh`, which no entry
  matches).
- Contested finding, `convention`: `formatRow` in `src/output.sh` line 20 (`APP-4`)
  breaks `` Function names SHOULD use snake_case, for example `print_rows`, not `printRows`. ``
  at `style/naming.md` line 5. Pass two downgrades it and Codex disputes it; it ends
  `contested` and counts at its lower severity.
- Contested finding, `verified fact`: `print_page` in `src/output.sh` (`APP-3`) sets
  `end=$((start + size))` (line 15), so a page prints `size + 1` rows: page 1 with size 2
  prints 3 rows. The comment on line 14 (`# sed ranges are inclusive, so the page ends at
  start + size.`) and the passing `tests/test_output.sh` (3 rows, page size 5) read the
  other way. It counts at its higher severity.
- CRLF file touched by two tickets: `config/settings.ini` (`APP-3`, `APP-4`), marked
  `-text` in `.gitattributes`. Feature content, every line ending `\r\n`: `[app]`,
  `name=users`, `page_size=500` (line 3, `APP-3`; the ticket says default 50),
  `export_keys=short` (line 4, `APP-4`; the ticket says default `long`). Act commits on
  it keep `\r\n` endings.

### Traps that must not appear

- solo's traps.
- A `MUST` finding citing a digest instead of `style/shell-scripts.md`.
- A legacy finding citing the detached checkout's `bin/users.sh` (no `deactivate`).
- `config/settings.ini` rewritten with `\n` line endings by act.

### Verify

```sh
cd $F
git -C app merge-base main feature                 # 6b27db42e063b1881b90f0b4c277d0a8ce2f3ab3
git -C app log --format=%s --name-only main..feature -- src/output.sh    # APP-3, APP-4, APP-5
git -C app show feature:config/settings.ini | od -c | head   # \r \n after each line
git -C app ls-files --eol config/settings.ini      # i/crlf ... attr/-text
git -C guidelines grep -n MUST main                # exactly one line: style/shell-scripts.md:5
git -C guidelines grep -n SHOULD main              # exactly one line: style/naming.md:5
git -C guidelines ls-files | wc -l                 # 57
(cd guidelines && git ls-files -z | xargs -0 cat | wc -c)   # 1116252 (du -sk varies with block size)
git -C legacy rev-parse HEAD                       # 2f21951b0c72eba8ccf5b3db9b4481ade113f8bd
git -C legacy rev-parse main                       # b3b208f6b760091e46d601739e93d43ee9f0bce7
git -C api diff --stat main...feature              # bin/import-users.sh | 3 +++
grep -L 'set -eu' $(git -C app ls-files '*.sh' | sed 's|^|app/|')   # app/src/audit-log.sh
```

## tokens

One repo, `app`, and four exported tickets with bare-number ids. It shares nothing with
`solo`: its commit ids are its own. It checks the `ticket_token` bundle key.

### Layout

| Path | What it is |
|---|---|
| `$F/manifest.json` | One bundle: `./app`, branch `feature`, base `main`, tickets `file:./exports/4567.md` to `4570.md`; no `ticket_token` |
| `$F/manifest-token.json` | The same bundle with `"ticket_token": ["#{n}", "[{n}]", "AB#{n}"]` |
| `$F/manifest-bad-token.json` | The same bundle with `"ticket_token": "#n"` |
| `$F/exports/4567.md` to `4570.md` | Ticket exports with ids `4567`, `4568`, `4569`, `4570`; no text names a file |
| `$F/app` | The app repo, checked out on `feature` |

### Commits

| Commit | Id | Branch | Files |
|---|---|---|---|
| `initial app` | `253d888eaa67c7c99b5f3d33a808835db8b6db39` | merge-base, main head | `README.md`, `src/app.sh` |
| `fix(#4567 #4568): reject empty input` | `2c91be9d37d6d3ba48068a20da316c7e6e70a245` | feature | `src/input.sh` |
| `build 4567 passed` | `e38ebff437050f6ce3653d0908515336d83bcfc3` | feature | `ci/status.txt` |
| `[4569] add the report command` | `04ccf504e5efa62a444f69a2edcd40d5d42e9180` | feature | `src/report.sh` |
| `AB#4570 rename the config key` | `dcae97565a63bbd4f6a52b6f9e1647530a32dd6f` | feature | `config/app.conf` |
| `migrated 4567 rows` | `b12b94c3072b10e1b5b5f4eace49e598e5ef093c` | feature head | `data/migration.txt` |

Changed files (three-dot): `ci/status.txt`, `config/app.conf`, `data/migration.txt`,
`src/input.sh`, `src/report.sh`. The tier is `medium` (1 bundle, 4 tickets, under 5,000
changed lines).

### Expected outcomes

Groups, worked out from Stage 1, "Groups", step 8 (rule 1, then extraction and merge; no
ticket text or commit message names a file, so rule 2 adds nothing):

- `manifest.json` (no token, so the bare id matches under the boundary rule alone):
  - `4567` matches `fix(#4567 #4568)`, `build 4567 passed`, and `migrated 4567 rows`;
  - `4568` matches `fix(#4567 #4568)`;
  - `4569` matches `[4569]`;
  - `4570` matches `AB#4570`.

  Groups: `app-4567` (`ci/status.txt`, `data/migration.txt`, `src/input.sh`), `app-4568`
  (`src/input.sh`), `app-4569` (`src/report.sh`), `app-4570` (`config/app.conf`). No file
  is in more than two groups, so nothing moves to `cross-cutting`. No merge: `app-4567`
  has one of its three files in `app-4568`, which is not more than half. No `unticketed`
  group.
- `manifest-token.json` (`#{n}`, `[{n}]`, `AB#{n}`):
  - `#4567` and `#4568` match only `fix(#4567 #4568)`; `build 4567 passed` and
    `migrated 4567 rows` hold no `#4567`, `[4567]`, or `AB#4567`;
  - `[4569]` matches `[4569] add the report command`;
  - `#4570` does not match `AB#4570` (a letter comes right before `#`), and `AB#4570`
    does.

  `ci/status.txt` and `data/migration.txt` are touched only by the build and migration
  commits, which name no ticket, so both go to `unticketed`. `app-4567` and `app-4568` each
  hold only `src/input.sh`, so each has all its files in the other and they merge into
  `app-4567+app-4568`. Groups: `app-4567+app-4568` (`src/input.sh`), `app-4569`
  (`src/report.sh`), `app-4570` (`config/app.conf`), `unticketed` (`ci/status.txt`,
  `data/migration.txt`).
- `manifest-bad-token.json` stops before stage 1 with
  `bundle app: ticket_token must hold {n} once`.

### Verify

```sh
A="git -C $F/app"
$A rev-parse main                          # 253d888eaa67c7c99b5f3d33a808835db8b6db39
$A log --reverse --format='%H %s' main..feature
$A diff --name-only main...feature         # ci/status.txt config/app.conf data/migration.txt src/input.sh src/report.sh
grep -c ticket_token $F/manifest.json      # 0
```

## patterns

One repo, `app`, and three exported tickets, with a planted case for each of four
patterns and a decoy for each. It shares nothing with `solo`: its commit ids are its own.
The manifest carries the bundle key `run_once`; it has no claims file. No comment, name,
commit message, or ticket text says that anything is wrong. Whether an audit finds a case
is not decided here: `docs/acceptance.md` records it per audit run, as observed, not
assumed.

### Layout

| Path | What it is |
|---|---|
| `$F/manifest.json` | One bundle: `./app`, branch `feature`, base `main`, tickets `file:./exports/PAT-1.md` to `PAT-3.md`, `"run_once": ["migrations/*.sh"]`; no `claims` |
| `$F/exports/PAT-1.md` to `PAT-3.md` | Ticket exports with ids `PAT-1`, `PAT-2`, `PAT-3`, in the format of `APP-1`; no `acceptance_criteria` |
| `$F/app` | The app repo, checked out on `feature`, not rebased onto `main`, no tracked changes |

### Commits

| Commit | Id | Branch | Files |
|---|---|---|---|
| `initial user records tool` | `72ca6912e7a55ef653f72a0667089e4d5b7c2a69` | merge-base | `.gitignore`, `data/users.csv`, `migrate.sh`, `migrations/001_create_users.sh`, `run-tests.sh`, `src/log.sh`, `src/reactivate.sh`, `src/users.sh`, `tests/test_users.sh` |
| `PAT-1: reject non-numeric ids in deactivate` | `e110cb26a794a40b733341d9ca397425c9b55bc1` | feature | `src/users.sh`, `tests/test_users.sh` |
| `PAT-2: add the warning count command` | `0c71299be23374e60d05f77fc1a0c292a945e9e6` | feature | `src/warnings.sh`, `tests/test_log.sh` |
| `PAT-3: add the email and last_login columns` | `7bdaa0e61667de685db3a70f204a3918fb53413f` | feature head | `migrations/001_create_users.sh`, `migrations/002_add_last_login.sh`, `tests/test_users.sh` |
| `log: lowercase the warning prefix` | `d84a2ec3bcdc1282bf12524ae08e24bf7928a7c8` | main head, the base's later commit | `src/log.sh` |

- Merge-base: `72ca6912e7a55ef653f72a0667089e4d5b7c2a69`.
- Commits on the base since the merge-base: `d84a2ec3bcdc1282bf12524ae08e24bf7928a7c8`
  (`log: lowercase the warning prefix`). It changes `src/log.sh` only, which no feature
  commit touches, so `main` merges into `feature` without a conflict.
- Changed files (three-dot): `migrations/001_create_users.sh`,
  `migrations/002_add_last_login.sh`, `src/users.sh`, `src/warnings.sh`,
  `tests/test_log.sh`, `tests/test_users.sh`; 6 files changed, 71 insertions(+).
- The test command is `sh run-tests.sh`. At the head it exits 0 and prints `pass` for
  every test, 6 in all, and `ok` for both test files; at the merge-base it runs 2 tests.
- `migrate.sh` writes its journal to `data/applied.txt`, which `.gitignore` lists.

### Expected outcomes

The ticket ids are `PAT-1`, `PAT-2`, `PAT-3`. Each case below gives where the defect is,
the finding that describes it, and the decoys that must not count. A decoy that counts is
a trap, and `docs/acceptance.md` records it as one.

**P17: a sibling that lacks the check (`PAT-1`).**

- Location: `src/reactivate.sh` lines 8 to 13, `reactivate_user`. It handles `id=$1`
  the way `deactivate_user` did before the change, with no check, and the file is not in
  the diff. The feature adds the check to `deactivate_user` in `src/users.sh` lines 25
  to 30.
- Expected finding: `reactivate_user` accepts a non-numeric id (`sh src/reactivate.sh abc`
  exits 0 and prints nothing), although `deactivate_user` now rejects it with
  `invalid id`. The ticket names only `deactivate`, so the finding is about the sibling
  that has the same id handling, not about a ticket requirement.
- Decoys: `list_users` (`src/users.sh` line 8) takes no id and correctly has no check.
  `add_user` (lines 13 to 21) already rejects a bad id.

**P18: a test that passes without the change (`PAT-1`).**

- Location: `tests/test_users.sh` lines 25 to 27, `test_deactivate_rejects_bad_id`. It
  runs `grep -q "invalid id" src/users.sh`. The string exists at the merge-base, in
  `add_user` (`src/users.sh` line 16), so the test passes with the feature's change to
  `src/users.sh` reverted, and nothing runs `deactivate` with a bad id.
- Expected finding: the test would not catch a regression in what the ticket asks, that
  `deactivate` rejects a non-numeric id. The finding quotes the test and names the
  regression it misses: `deactivate` accepting `abc`.
- Decoy: `test_deactivate_keeps_row` (lines 29 to 32) runs `deactivate 2` and asserts that
  the row is still there with status `inactive`. It covers a different behavior and
  passes at the merge-base too, but it does not claim to test the rejection, so it does
  not count as a weak test of `PAT-1`.

**P19: a base change to what a fix matches on (`PAT-2`).**

- Location: `src/warnings.sh` line 7, `grep -c '^WARN:' "$1"`. The producer is `log_warn`
  in `src/log.sh` line 6, `printf 'WARN: %s\n' "$*"`, at the merge-base and at the head.
  Commit `d84a2ec3bcdc1282bf12524ae08e24bf7928a7c8` on `main` changes it to
  `printf 'warning: %s\n' "$*"`. The feature does not change `src/log.sh`.
- Expected finding: after the merge, `log_warn` writes lines that start `warning: `, and
  `count_warnings` counts 0 for them. The command that `PAT-2` asks for reports no
  warnings. The finding names the base commit.
- Decoys: `tests/test_log.sh` passes after the merge, because it writes its own `WARN:`
  lines; it does not show the defect and is not a defect itself. The count at the head,
  2 for two `log_warn` lines, is right.

**P20: an edit to a run-once script that may already be applied (`PAT-3`).**

- Location: `migrations/001_create_users.sh` lines 11 to 15, the block that appends
  `,email` to the header and an empty field to each row. The file exists at the
  merge-base and matches `run_once` (`migrations/*.sh`). The block works on a fresh
  install: `sh migrate.sh` over the tracked seed gives `email` and `last_login`.
- Expected finding: an install where `001_create_users.sh` is in the journal
  (`data/applied.txt`) never runs the edited file again, because `migrate.sh` skips a
  name it has recorded, so that install gets `last_login` and no `email` column. That
  001 is not yet applied in every target environment is an `unverified assumption`, with
  a `live check`: whether `001_create_users.sh` is in the journal of each target.
  Severity no higher than `medium`.
- Decoy: `migrations/002_add_last_login.sh` is a new file, and a rerun is a no-op because
  of its guard on lines 7 to 9. It must not count, as a defect or as an edited run-once
  file. The guard in the edited 001 (line 11) makes a rerun of 001 a no-op too; that is
  not the finding.

### Behavior checks

`verify.sh` runs these in temp copies made with `git archive` or a temp clone, so the
fixture repo never changes. Each failed check prints one line that starts with the case.

- P17: at the head, `sh src/users.sh deactivate abc` exits non-zero with `invalid id`;
  `sh src/reactivate.sh abc` exits 0 with no output and leaves `data/users.csv` as it was.
- P18: with `src/users.sh` from the merge-base and the head's `tests/test_users.sh`,
  `sh tests/test_users.sh` exits 0, prints `pass test_deactivate_rejects_bad_id` and
  `pass test_deactivate_keeps_row`, and `sh src/users.sh deactivate abc` exits 0 with no
  output.
- P19: at the head, two `log_warn` lines give a count of 2. In a clone of `feature` after
  `git merge origin/main` (no conflict), two `log_warn` lines are `warning: ` lines and
  the count is 0.
- P20: install at the merge-base (run `migrate.sh` over the tracked seed, so the journal
  holds `001_create_users.sh`), copy `data/` into the head tree, run the head's
  `migrate.sh`. It prints only `applied 002_add_last_login.sh`, the header is
  `id,name,status,last_login` with no `email`, a second run prints nothing, and a direct
  rerun of 002 leaves the file as it was. A fresh install at the head (empty journal)
  prints `applied 001_create_users.sh` and `applied 002_add_last_login.sh`, the header is
  `id,name,status,email,last_login`, and a direct rerun of 001 and 002 leaves the file as
  it was.

### Verify

```sh
A="git -C $F/app"
$A merge-base main feature                  # 72ca6912e7a55ef653f72a0667089e4d5b7c2a69
$A log --format='%H %s' 72ca691..main       # d84a2ec... log: lowercase the warning prefix
$A diff --name-only 72ca691 main            # src/log.sh
$A diff --name-only main...feature          # migrations/001_create_users.sh migrations/002_add_last_login.sh src/users.sh src/warnings.sh tests/test_log.sh tests/test_users.sh
$A diff --shortstat main...feature          # 6 files changed, 71 insertions(+)
$A rev-parse --abbrev-ref HEAD              # feature
$A status --porcelain                       # no output
grep -n 'invalid id' $F/app/src/users.sh    # 16 and 27
grep -n 'WARN:' $F/app/src/log.sh $F/app/src/warnings.sh   # log.sh:6, warnings.sh:5 and 7
grep -c claims $F/manifest.json             # 0
sh tests/fixture/verify.sh $F/manifest.json patterns        # verify patterns: ok
```
