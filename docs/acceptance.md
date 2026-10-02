# Acceptance record: v0.1.0, v0.2.0, and v0.3.0

The v0.2.0 section follows "What a full acceptance run needs", and the v0.3.0 section is
at the end.

This file records the acceptance cases for cca 0.1.0 and their results, checked on
2026-09-30 and 2026-10-01 with Claude Code 2.1.284 on Windows 11 with Git Bash. The
cases come from the pre-implementation spec, architecture, and build plan documents, in
the repository history before this change. Static checks, plugin load probes, and
fixture builds were run, plus one audit run on `solo` with `--budget 0 --no-codex`,
which runs stage 1 and the report and launches no agent. Every other case that needs a
live multi-agent audit run (Opus agents over a fixture, optionally with Codex) was not
executed in this release build and is marked `not run`. No case is recorded as passed
without a run that shows it.

Results are `pass`, `fail`, `superseded: <reason>`, or `not run: <reason>`.

The budget-0 run: 2026-10-01T00:07Z to 00:09Z, Claude Code 2.1.284,
`claude -p "/cca:audit <solo manifest> --budget 0 --no-codex" --plugin-dir . --model opus`,
non-interactive with an allowed-tools list. Run id `2026-09-30-2007-app-app-1`. After the
run, the fixture app repo's `git status --porcelain` showed only the fixture's own
preexisting untracked `notes/` entry, and HEAD stayed on `feature`.

## M0: skeleton

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| M0-a | `claude --plugin-dir .` loads the plugin and the three commands appear | pass | `claude -p --plugin-dir .` listed exactly `/cca:act`, `/cca:audit`, `/cca:resume` |
| M0-b | `/cca:audit --bogus` is rejected in one line, and nothing is written | pass | Printed the single line `cca: unknown flag --bogus`; `git status --porcelain` was unchanged and no plugin data directory was created |
| M0-c | `/cca:audit <solo manifest>` reaches stage 1 and stops with "not implemented" | superseded: stage 1 is implemented | The "not implemented" stub no longer exists; M0-c' replaces it |
| M0-c' | `/cca:audit <solo manifest> --budget 0 --no-codex` reaches stage 1 and ends `partial` | pass | The budget-0 run: stage 1 ran, stage 8 wrote the report, the run ended `partial` with verdict `audit incomplete` and printed `/cca:resume 2026-09-30-2007-app-app-1`; `stages.json` has entries 1 and 8 `complete`, 2 and 3 not applicable, and entries for stages 4 to 7 marked as not run because the budget expired, in a free-text status the orchestrator improvised. The skill now standardizes this as status `failed` with the reason "not run: budget expired", so later runs differ in that detail |
| M0-d | A probe settles the five architecture decisions; answers go in the decisions record | pass | Settled by documentation probe and session observation; answers in `docs/decisions.md` |
| M0-e | `tests/lint.sh` passes, and fails when an agent file lists Edit | pass | `sh tests/lint.sh` printed `lint: ok`, exit 0; with `  - Edit` added as the first entry under `tools:` of `agents/auditor.md` in a copy of the tree, it printed two lines, `lint: agents/auditor.md: tool not allowed: Edit (allowed: Read, Grep, Glob, Bash, Write)` and `lint: agents/auditor.md:6: mentions Edit or NotebookEdit`, exit 1 |

## Fixture builds

These are builder checks, not acceptance cases. Each build ran on Windows with Git Bash
and on Ubuntu with dash, with identical commit ids on both.

| Fixture | Command | Result | Evidence |
|---|---|---|---|
| `solo` | `sh tests/fixture/build.sh solo` | pass | Exit 0; printed the path of a manifest that exists |
| `solo-dirty` | `sh tests/fixture/build.sh solo-dirty` | pass | Exit 0; printed the path of a manifest that exists |
| `full` | `sh tests/fixture/build.sh full` | pass | Exit 0; printed the path of a manifest that exists |

## M1: orient and report

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| M1-a | `solo`: the brief lists the merge-base, the base's later commit, and the file changed on both sides; the diff excludes the base's later change; every claim sentence is in `claims.md`; one ticket group and no `cross-cutting`; tier `low` | pass | Verified by inspection of the run directory after the budget-0 run: the brief lists merge-base `bd5d5e1e`, the base's later commit `2b5e8f3` ("add count command"), and `src/users.sh` as changed on both sides; `diffs/app.diff` has no occurrence of `count_users`; `claims.md` numbers every sentence of the claims file, 1 to 4 (three `claim`, one `other`); `groups.md` has one ticket group, `app-app-1`, with three files, and empty `unticketed` and `cross-cutting` sections; tier `low` |
| M1-b | `solo --budget 0`: the run ends `partial` with verdict `audit incomplete` | pass | The budget-0 run (see M0-c') |
| M1-c | `solo-dirty`: the app is read from an export under `trees/`, the dirty checkout is unchanged, `export-ignore`, `export-subst`, and the filter do not apply, and the symlink is a placeholder listed in the brief | not run | needs a live multi-agent audit run |
| M1-d | `solo-dirty`: a change to the modified, untracked, or ignored file between stages ends the run `blocked` and names it | not run | needs a live multi-agent audit run |
| M1-e | Two runs on `solo` in the same minute get different run ids, both in `runs.json` | not run | needs a live multi-agent audit run |
| M1-f | A manifest whose branch disagrees with its PR's head branch stops before stage 1 and shows both | not run | needs a live multi-agent audit run |
| M1-g | `solo-dirty`: after a clean stage, `baseline/1-check.md` exists and lists no ignored-file differences | pass on `solo` only | The budget-0 run on `solo`: `baseline/1-check.md` and `baseline/8-check.md` exist, each with result pass and ignored-file differences none. Not run on `solo-dirty`, which the case names |
| M1-h | `solo`: the export with no `acceptance_criteria` runs and is listed as "not in export"; the export with no `title` stops the run with `export <path>: missing title` | not run | needs a live multi-agent audit run |

## M2: low tier, no Codex

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| M2-a | `solo`: verdict `not ready`; the drift defect is `agreed` and `counts`; the false and true claims are judged with evidence; the skipped test is found; no "deleted feature" finding; `alternatives` names one recommendation; section 3 items are `not challenged` | not run | needs a live multi-agent audit run |
| M2-b | The decoy is `dismissed` with a reason, or absent, and never counts | not run | needs a live multi-agent audit run |
| M2-c | A pass-two addition with no late adversary is `provisional` and does not change the counts | not run | needs a live multi-agent audit run |
| M2-d | `_test` fails an auditor scope once: one relaunch on the same model, no swap | not run | needs a live multi-agent audit run |
| M2-e | `_test` fails an auditor scope twice: relaunch on Fable, recorded as a swap | not run | needs a live multi-agent audit run |
| M2-f | `_test` fails an auditor scope three times: the scope fails, and the run ends `partial` with `audit incomplete` | not run | needs a live multi-agent audit run |
| M2-g | `_test` fails the merger once: the orchestrator merges, recorded as a swap | not run | needs a live multi-agent audit run |
| M2-h | The claim "every existing row was migrated" yields an `unverified assumption` finding with a `live check`, listed in section 9, counted at most `medium` | not run | needs a live multi-agent audit run |
| M2-i | The auditor runs the fixture's test command, which writes an ignored file; the run ends `reported` and `baseline/4-check.md` attributes the file to that run | not run | needs a live multi-agent audit run |
| M2-j | No finding cites the untracked file holding the string that matches the drift defect | not run | needs a live multi-agent audit run |

## M3: Codex

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| M3-a | `codex/response.md` holds the verbatim answer, and every Codex disposition is in the ledger | not run | needs a live multi-agent audit run |
| M3-b | `--no-codex`: the fallback fills the role and the report names the swap | not run | needs a live multi-agent audit run |
| M3-c | Session started outside any git repo: codex-lite refuses, the run swaps and ends `reported` | not run | needs a live multi-agent audit run |
| M3-d | Run directory outside the session's repo: the request is in inline form and names no run-directory file | superseded: every request now names absolute paths, and the first request has no inline form (see V2-n) | |
| M3-e | `_test` drops one acknowledgment twice: stage 6 fails, and the run ends `partial` with `audit incomplete` | not run | needs a live multi-agent audit run |
| M3-f | `_test` fails the fallback twice, with `--no-codex`: Fable fails, Opus fails, and stage 6 fails | not run | needs a live multi-agent audit run |
| M3-g | `--codex-timeout 0` is rejected in one line; the stage 6 entry records timeout `1200` at low, and `3600` with `--codex-timeout 3600` | not run | needs a live multi-agent audit run |
| M3-h | `_test` sets the inline cap to 1,000 bytes, run directory outside the session's repo: stage 6 first drops only the diffs of bundles whose repo is the session's repository and re-measures (the stage 6 entry records `inline_reduced: true`; a diff of any other repo is never dropped, and with none droppable it swaps directly), then, still over the cap, swaps with the reason "request too large for inline form", and the run ends `reported` | superseded: the first request has no inline form, so it has no cap and no diff dropping (see V2-p for the follow-up cap) | |
| M3-i | A run with more than 60 mandatory ids: Codex gets the first batch in the request and at most 60 positions in its one follow-up (missing first-batch ids first), and every id neither carries goes to the fallback in batches of at most 60, one launch per batch (`second-opinion-<k>`), recorded as a partial swap with the reason "mandatory ids beyond the Codex request and follow-up"; with `--no-codex`, one fallback launch per batch (`second-opinion-<k>`); the stage 6 entry records `batched: true` and no mandatory id is left without a request | not run | needs a live multi-agent audit run |

## M4: sources and scale

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| M4-a | `full`: the broken `MUST` rule is found and cites the guideline file at its pinned sha, not the digest | not run | needs a live multi-agent audit run |
| M4-b | The legacy repo is read from an export at its pinned sha, not its checkout | not run | needs a live multi-agent audit run |
| M4-c | The cross-repo API break is found by the interaction auditor | not run | needs a live multi-agent audit run |
| M4-d | `_test` holds the digest chunk with the `MUST` rule until pass one finishes: a top-up auditor runs, lists the digest's hash, and first reports the `MUST` finding | not run | needs a live multi-agent audit run |
| M4-e | `_test` fails one digester scope three times: stage 2 fails, the barrier clears, and the run ends `partial` | not run | needs a live multi-agent audit run |
| M4-f | `--max-agents 2`: `stages.json` never shows more than two agents running, and every token number in `usage.md` has a source and scope label | not run | needs a live multi-agent audit run |
| M4-g | A Codex addition cleared by the late adversary `counts`; a finding the late adversary raises is `provisional`; with `--effort high` the stage 6 entry records timeout `3600` | not run | needs a live multi-agent audit run |
| M4-h | The `convention` contested finding is `contested` and counted at its lower severity | not run | needs a live multi-agent audit run |
| M4-i | `_test` expires the budget when stage 3 completes: no stage from 4 on launches new agents, stage 8 runs, and the run ends `partial` | not run | needs a live multi-agent audit run |
| M4-j | The file touched by three tickets is in `cross-cutting` and noted in each former group; a manifest `groups` key of two entries yields exactly those two plus `unticketed` | not run | needs a live multi-agent audit run |
| M4-k | `_test` plants a wrong line in the legacy map: `domain/legacy-source-map.r2.md` has a corrections header, a top-up writes `pass2/<group>-topup.md` with `origin: topup`, the `pass1/` file is unchanged, and the finding is `provisional` until the late adversary clears it | not run | needs a live multi-agent audit run |
| M4-l | `_test` sets the ledger split threshold to 1,000 bytes: `converged/` has one file per group, or one per part `<group>-<k>` for a group whose slice exceeds the threshold, `ledger/slices/` holds the matching slices, and `converged.md` maps every ledger id | not run | needs a live multi-agent audit run |
| M4-m | The `verified fact` contested finding is counted at its higher severity | not run | needs a live multi-agent audit run |

## M5: resume

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| M5-a | `full`, after a complete run: editing the claims file and resuming reruns stages 1 to 8 and marks the old outputs superseded | not run | needs a live multi-agent audit run |
| M5-b | `--from 5` reruns stages 5 to 8, reuses stages 1 to 4, and marks `ledger/5.md`, `ledger/6.md`, and `ledger/7.md` superseded | not run | needs a live multi-agent audit run |
| M5-c | Moving the app's branch head, or its base branch, makes resume stop and ask whether to restart from stage 1; answering no changes nothing | not run | needs a live multi-agent audit run |
| M5-d | `--from 6` reruns stages 6 to 8, reuses `ledger/5.md` unchanged, and marks `ledger/6.md` and `ledger/7.md` superseded | not run | needs a live multi-agent audit run |

## M6: act

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| M6-a | `solo`, after a complete run: approving the drift item makes one local commit after one confirmation, with no push | not run | needs a live multi-agent audit run |
| M6-b | A second `/cca:act` on the same run does not call the first commit drift | not run | needs a live multi-agent audit run |
| M6-c | A hand-made commit on the branch is reported as drift | not run | needs a live multi-agent audit run |
| M6-d | A dirty checkout stops act with nothing stashed | not run | needs a live multi-agent audit run |
| M6-e | A check failing at baseline is reported as preexisting; a check the change breaks is reported as introduced and no commit is offered | not run | needs a live multi-agent audit run |
| M6-f | Editing the report after approval stops act | not run | needs a live multi-agent audit run |
| M6-g | `full`: two approved items on two tickets that share the CRLF file give two commits, each passing its checks, with the file's line endings unchanged | not run | needs a live multi-agent audit run |

## M7: release

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| M7-a | `tests/lint.sh` passes | pass | `sh tests/lint.sh` printed `lint: ok`, exit 0 (see M0-e) |
| M7-b | Every case in this record passed on the release candidate | fail | Apart from M1-a, M1-b, and M1-g on `solo`, the run-based cases M1 to M6 were not run and are listed above as `not run` |
| M7-c | A fresh install from the marketplace loads the plugin | not run | The marketplace is this repository and the release is not tagged; loading with `--plugin-dir` passed as M0-a |

## Spec coverage

| Spec section | Milestone | Cases | Status |
|---|---|---|---|
| Hard rules 1 and 2, read-only boundary and detection | M1, M2 | M1-c, M1-d, M1-g, M2-i | partly covered: M1-g passed on `solo` only; the rest not run |
| Hard rules 3 and 4, external names and forbidden tools | M0, M6 | inspection of agent and stage files; M6-a checks the commit message | inspection done (`skills/cca/common.md` hard rules 3 and 4, the commit message rule in `skills/cca/stages/9-act.md`, and the lint's forbidden-tool check passing); M6-a not run |
| Hard rule 5, live data | M2 | M2-h | not run |
| Evidence | M2, M4 | M2-a, M2-j, M4-a | not run |
| Inputs, manifest, conflicts, ids, exported forge files | M1 | M1-a, M1-f, M1-h | partly covered: M1-a passed; M1-f and M1-h not run |
| Grouping and hub files | M1, M4 | M1-a, M4-j | partly covered: M1-a passed; M4-j not run |
| Sources of truth, pinned | M1, M4 | M1-c, M4-a, M4-b | not run |
| Effort tiers | M1, M4 | M1-a, M4-c | partly covered: M1-a passed (tier `low`); M4-c not run |
| Run directory, run ids, `runs.json` | M1 | M1-e | not run |
| Stage 1 | M1 | M1-a to M1-d | partly covered: M1-a and M1-b passed; M1-c and M1-d not run |
| Stages 2 and 3, applicability | M1, M4 | M4-a, M4-e | not run |
| Stage 4 and the barrier | M2, M4 | M2-a, M4-d | not run |
| Stage 5 and the ledger | M2 | M2-a, M2-b | not run |
| Map corrections and top-ups | M4 | M4-k | not run |
| Stage 6 and the call contract | M3 | M3-a to M3-f, M3-i | not run |
| Codex request shape and timeout | M3 | M3-g | not run |
| Merger size and inline cap | M3, M4 | M3-h, M4-l | not run; M3-h is superseded, so the inline-cap half now rests on V2-p |
| Stage 7, late adversary, review gate | M2, M4 | M2-c, M4-g, M4-h, M4-m | not run |
| Stage 8, verdict, revision | M2 | M2-a, M2-f, M1-b | partly covered: M1-b passed; M2-a and M2-f not run |
| Stage 9 | M6 | M6-a to M6-f | not run |
| Act commits per ticket | M6 | M6-g | not run |
| Roles and fallbacks | M2, M3 | M2-d to M2-g, M3-b, M3-f | not run |
| Resume | M5 | M5-a to M5-c | not run |
| Per-stage ledger files | M5 | M5-b, M5-d | not run |
| Compaction recovery | M0 | inspection of the preamble | inspection done (`skills/cca/SKILL.md`, "Compaction recovery") |
| Atomic state | M1 | inspection | inspection done (`skills/cca/SKILL.md`, "State files": a temporary file and a rename for `stages.json` and `runs.json`) |
| Budget and usage | M1, M4 | M1-b, M4-f, M4-i | partly covered: M1-b passed; M4-f and M4-i not run |
| Terminal states | M1 to M3 | M1-b, M1-d, M3-c | partly covered: M1-b passed; M1-d and M3-c not run |

No row is fully covered by passed cases. The rows marked partly covered rest on the one
budget-0 run on `solo`, which launches no agent; every row that needs agents is not run.

## What a full acceptance run needs

A full run builds the `solo`, `solo-dirty`, and `full` fixtures with
`tests/fixture/build.sh`, then runs each M1 to M6 case against them in a Claude Code
session with the plugin loaded: role agents on Opus, the merger on Sonnet, and, for the
M3 cases that exercise Codex, the Codex CLI with codex-lite installed (the other cases
can pass `--no-codex`). Each case is judged against the run directory, `stages.json`,
and the report, using the literals in `tests/fixture/expected.md`. A single audit run is
expected to take up to hours of wall clock, and the set covers dozens of runs; the
actual time is not measured.

The first medium-tier run on a real bundle is the acceptance run. It judges the cases
that need a live audit, for 0.1.0 and 0.2.0 alike.

# Acceptance record: v0.2.0

This section records the acceptance cases for cca 0.2.0. Results are `pass`, `fail`,
`superseded: <reason>`, `not run`, or `not run: <reason>`. The cases that run in the
release build (the lint, the three script tests, the fixture builds and verifies, and the
CI matrix) are `not run` until the release checks run; the evidence cell is then filled
in from that run. No case is recorded as passed without a run that shows it. The v0.1.0
record above is unchanged except M3-d and M3-h, superseded in 0.2.0 when every Codex request began naming absolute paths.

## Release checks

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| V2-a | `sh tests/lint.sh` passes | pass | 2026-10-01, Windows 11, Git Bash: printed `lint: ok`, exit 0 |
| V2-b | `sh tests/readonly.sh` passes on its twenty-seven cases, including nested repositories (cases 13 to 17 and 21), an upstream move (18), a run directory in other letters (19, which runs only where `core.ignorecase` is true), an unchanged index (20), prefixes compared by file identity (22 and 23, which run only on a case-insensitive file system), an out prefix on a UNC path (24, which runs only where `//localhost/c$` is reachable), an out prefix with a `..` component (25), a linked worktree as the repo (26), and a repository in an ignored directory (27) | pass | 2026-10-01, Windows 11, Git Bash, after cases 26 and 27 were added: printed `readonly test: ok`, exit 0; `RO_SH=dash dash tests/readonly.sh`, which runs the script itself under dash, printed the same, exit 0 |
| V2-c | `sh tests/handoff.sh` passes, including a byte order mark in every mode, a raised ticket that reuses a ticket id, `none` under `## Bundles`, one commit at two sha lengths, a bundle named twice, an empty `## Decisions`, a file that ends right after `## Raised tickets`, one commit under two tickets, and a claim line over and at the 8,000-byte cap, including one pushed over by a long decision id | pass | 2026-10-01, Windows 11, Git Bash (gawk), after those cases were added: `sh tests/handoff.sh` and `dash tests/handoff.sh` each printed `handoff test: ok`, exit 0. mawk and BSD awk ran in CI (V2-f) |
| V2-d | `sh tests/work-items.sh` passes, including a `set_pr_description` that targets a placeholder | pass | 2026-10-01, Windows 11, Git Bash, jq 1.8.2: `sh tests/work-items.sh` and `dash tests/work-items.sh` each printed `work-items test: ok`, exit 0 |
| V2-e | `sh tests/fixture/build.sh` then `sh tests/fixture/verify.sh` pass for `solo`, `solo-dirty`, and `full` | pass | 2026-10-01, Windows 11, Git Bash: each build exited 0 and printed its manifest path; the three verifies printed `verify solo: ok`, `verify solo-dirty: ok`, and `verify full: ok`, exit 0 |
| V2-f | The CI `scripts` job passes on Linux, macOS, and Windows, and the existing job still passes | pass | 2026-10-01, GitHub Actions run 36829701310 on commit `bab6657`: `checks` and `scripts` on ubuntu-latest, macos-latest, and windows-latest all passed. On Linux the default `awk` was `/usr/bin/gawk`, and the mawk step (`mawk 1.3.4 20240123`) printed `handoff test: ok` and `readonly test: ok`. macOS ran the tests with its BSD awk and `stat`. Rerun on commit `ac39578`, with the nested-repository and handoff cases (V2-b, V2-c): GitHub Actions run 36847008331, every job passed; on Linux the mawk step (`mawk 1.3.4 20240123`) again printed `handoff test: ok` and `readonly test: ok`, and macOS ran `/usr/bin/awk`. Rerun on commit `fdb567d`, with the file-identity, UNC-path, and claim-cap cases: GitHub Actions run 36884209398, every job passed, and the mawk step again printed `handoff test: ok` and `readonly test: ok`. Rerun on commit `445e453`, with the `..` prefix and whole-line claim cap cases: run 36891780551, every job passed, including the mawk step. Rerun on commit `6d43101`, with the linked-worktree cases 26 and 27: run 36902706045, every job passed, and the mawk step again printed `handoff test: ok` and `readonly test: ok`. Rerun on commit `fc52e2c`, with the empty-section and PR-description cases: run 36909259616, every job passed, and the mawk step again printed `handoff test: ok` and `readonly test: ok` |

## Agent-driven cases

Each is judged against the run directory and the report, and each expected outcome holds
only when the stage that judges it completes.

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| V2-g | A verification claim the fixture cannot reproduce is never reported `true`, and appears in `claims-verdicts.md` as a recheck request | not run: needs a live multi-agent audit run | |
| V2-h | A decision with status `deferred` and no owner is a `stale deferral` | not run: needs a live multi-agent audit run | |
| V2-i | A raised ticket ranked `include` whose behavior predates the merge-base has `facts disagree with the handoff: yes` | not run: needs a live multi-agent audit run | |
| V2-j | `claims-verdicts.md` names the handoff line of every `false` | not run: needs a live multi-agent audit run | |
| V2-k | `/cca:handoff` writes a handoff that passes `handoff.sh check` | not run: needs a live multi-agent audit run | |
| V2-l | The manifest `scratch` key puts the run directory under `app/.test-output/cca/` | not run: needs a live multi-agent audit run | |
| V2-m | `work-items.jsonl` passes `work-items.sh check` | not run: needs a live multi-agent audit run | |
| V2-n | Run directory outside the session's repository: the request names absolute paths and every input is acknowledged | not run: needs a live multi-agent audit run | |
| V2-o | `_test.drop_ack` on one input: the follow-up carries it inline and it is acknowledged | not run: needs a live multi-agent audit run | |
| V2-p | `_test.inline_cap_bytes` of 1,000 with `_test.drop_ack` on `ledger/5.md`: the follow-up exceeds the cap (the copy of `ledger/5.md` is over 1,000 bytes), is not sent, and stage 6 fails | not run: needs a live multi-agent audit run | |
| V2-q | A follow-up when the answer carried no thread id goes as a fresh call naming `common.md`, `audit-brief.md`, and `ledger/5.md` by absolute path | not run: needs a live multi-agent audit run | |
| V2-r | An input copy made unreadable to Codex is reported `not read` and goes inline in the follow-up | not run: needs a live multi-agent audit run | |
| V2-s | `solo`, in a session whose repository is `$F/app`: `/cca:handoff $F/manifest-handoff.json --verdicts $F/claims-verdicts.md --out $F/handoff-verdicts.md` (the file must not exist yet) writes that file and applies only the matching `false` line (claim 1), lists the text mismatch (claim 3) and the `contested` line (claim 5) as reconciliation work without applying them, keeps the recheck request (claim 6) under `verified`, and does nothing for the `true` line (claim 7), per `tests/fixture/expected.md` "Verdicts" | not run: needs a live session with the plugin loaded | |
| V2-t | `solo`: the same with `--verdicts $F/claims-verdicts-stale.md`, whose heading hash matches no file, and `--out $F/handoff-verdicts-stale.md`: the output file is written, no correction is applied, and all five lines are reconciliation work with the hash mismatch as the reason | not run: needs a live session with the plugin loaded | |
| V2-u | A bundle repo with a stat-only change to a tracked file, read directly: after `/cca:audit` and then `/cca:resume`, `git hash-object --no-filters .git/index` is the same as before the audit | not run: needs a live multi-agent audit run | |
| V2-v | An adversary report with no `## Decisions challenged` line for one entry: the scope does not fail, the stage 5 entry records the entry `not challenged`, and report section 8 shows that mark | not run: needs a live multi-agent audit run | |
| V2-w | A pass-one report with no `## Decisions` entry for an assigned `decision` claim: the scope is not relaunched, the stage 4 entry records the claim `not assessed`, the report's coverage lists it, and `claims-verdicts.md` gives it `not verified` with the reason "not assessed" | not run: needs a live multi-agent audit run | |
| V2-x | An adversary report with no `## Claims challenged` line for a `verification` claim marked true still fails the scope through the ladder | not run: needs a live multi-agent audit run | |
| V2-y | A `verification` claim whose check needs an environment variable the audit's environment lacks: the auditor's run fails, and the claim is `not verified, not reproduced` with the reason naming the missing variable, never `false` | not run: needs a live multi-agent audit run | |

# Acceptance record: v0.3.0

This section records the acceptance cases for cca 0.3.0. Results are `pass`, `fail`,
`superseded: <reason>`, `not run`, or `not run: <reason>`. The release checks ran locally;
V3-i is filled in from the final CI run. No case is recorded as passed without a run that
shows it. The v0.1.0 and v0.2.0 records above are unchanged.

## Release checks

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| V3-a | `sh tests/lint.sh` passes | pass | 2026-10-01, Windows 11, Git Bash: printed `lint: ok`, exit 0 |
| V3-b | `sh tests/readonly.sh` and `RO_SH=dash dash tests/readonly.sh` pass, unchanged cases | pass | 2026-10-01, Windows 11, Git Bash: each printed `readonly test: ok`, exit 0 |
| V3-c | `sh tests/handoff.sh` and `dash tests/handoff.sh` pass, with the env and parent/links cases | pass | 2026-10-01, Windows 11, Git Bash: each printed `handoff test: ok`, exit 0 |
| V3-d | `sh tests/work-items.sh` and `dash tests/work-items.sh` pass, with the new ops and checks | pass | 2026-10-01, Windows 11, Git Bash, jq 1.8.2: each printed `work-items test: ok`, exit 0 |
| V3-e | `sh tests/working-tree.sh` and `dash tests/working-tree.sh` pass | pass | 2026-10-02, Windows 11, Git Bash, with case 19 (a quoted submodule path): each printed `working-tree test: ok`, exit 0, and so did `WT_SH=dash dash tests/working-tree.sh`; cases 6j and 6k printed their skip |
| V3-f | `sh tests/live.sh` and `dash tests/live.sh` pass | pass | 2026-10-02, Windows 11, Git Bash, with the import-without-jq case, which ran (jq sits in its own PATH directory here): each printed `live test: ok`, exit 0 |
| V3-g | `sh tests/memory.sh` and `dash tests/memory.sh` pass | pass | 2026-10-01, Windows 11, Git Bash: each printed `memory test: ok`, exit 0 |
| V3-h | the four fixtures build and verify | pass | 2026-10-01, Windows 11, Git Bash: each build of `solo`, `solo-dirty`, `full`, and `tokens` exited 0 and printed its manifest path; the four verifies printed `verify <name>: ok`, exit 0 |
| V3-i | CI `checks` and `scripts` pass on Linux, macOS, and Windows, with the mawk step running the awk tests; run id recorded | pass | 2026-10-02 (UTC), GitHub Actions run 36969145720 on commit `7b0fcc4`: `checks` printed `verify <name>: ok` for `solo`, `solo-dirty`, `full`, and `tokens`, and `scripts` passed on ubuntu-latest, macos-latest, and windows-latest, each with jq present (1.7, 1.8.2, 1.8.1). The mawk step (`mawk 1.3.4 20240123`) printed `handoff test: ok`, `readonly test: ok`, `live test: ok`, `memory test: ok`, and `working-tree test: ok`; macOS ran its BSD awk. Windows skipped working-tree cases 6j and 6k (its file system keeps no tab or backslash in a name); Linux and macOS ran them. Working-tree case 19 ran on all three. The live import-without-jq case ran on Windows and printed its skip on Linux and macOS, where jq shares a PATH directory with the tools. Run 36961322491 on `edcd6f1` passed before the PR review fixes. The first branch run, 36937502825, failed on macOS (BSD awk ended a regex at `/`, in `memory.sh`), fixed in `ec416a9`; runs 36938137338, 36949285614, 36952285197, 36955214185, and 36958205393 passed on the commits between |

## Agent-driven cases

Each is judged against the run directory and the report, and each expected outcome holds
only when the stage that judges it completes.

| Case | Description | Result | Evidence or reason |
|---|---|---|---|
| V3-j | `solo` with `manifest-working-tree.json`: the head is the literal sha in `expected.md`, the brief lists `notes/deactivate-draft.txt` as untracked at audit time, the app is read directly, `.git/index` is unchanged, Coverage discloses the object writes and the unreferenced head | not run: needs a live multi-agent audit run | |
| V3-k | `solo-dirty` with `manifest-working-tree.json`: stops before stage 1, `feature` not checked out | not run: needs a live multi-agent audit run | |
| V3-l | After V3-j, `git gc --prune=now` in the app, then `/cca:resume`: the same head sha, no restart asked | not run: needs a live multi-agent audit run | |
| V3-m | After V3-j: act before committing shows drift (the committed tree lacks the untracked `notes/deactivate-draft.txt`); commit the working tree as is, then act: no drift; amend that commit's message, then act: no drift; commit a different tree: drift shown | not run: needs a live multi-agent audit run | |
| V3-n | A handoff verified entry `...; check: env: staging; sh run-tests.sh`: the claim is `not verified, not reproduced` naming env staging, section 9 has a `#### live claim <n>` block, `claims-verdicts.md` says `not reproducible here` | not run: needs a live multi-agent audit run | |
| V3-o | `solo`, a `--live` file for the "Every existing row was migrated" finding: stages 6 to 8 rerun, the finding is provisional until both reviews, the report has a new revision, section 9 logs the access with its approver, and `stages.json` has the `live` approval | not run: needs a live multi-agent audit run | |
| V3-p | A `--live` result making an env claim `true, reproduced`: only stages 7 and 8 rerun, `live/findings.md` stays absent, and the late adversary challenges the claim, at low tier too | not run: needs a live multi-agent audit run | |
| V3-q | `--live` naming another revision, or another query, stops with the `live.sh` line; `--live` with `--from 3` is rejected in one line; `--live` on a run whose head moved stops without asking to restart | not run: needs a live multi-agent audit run | |
| V3-r | A result matching no stated outcome: the finding stays at its label and severity, goes to both reviews, and the report says `unchanged: no stated outcome matches` | not run: needs a live multi-agent audit run | |
| V3-s | A second `--live` file with a new result for the same finding: the derived entry is replaced and lists `earlier:`; a claim-only second file leaves `live/findings.md` byte for byte and reruns from stage 7; a plain `/cca:resume` afterwards with nothing changed says the run is current | not run: needs a live multi-agent audit run | |
| V3-t | `_test` fails the late adversary three times on a live rerun: the live finding stays provisional and a live true claim is `not verified, not reproduced`, reason "live result not challenged" | not run: needs a live multi-agent audit run | |
| V3-u | A merged item absorbing two findings, one with a live result: with the late adversary failed, the item's severity and label ignore both the derivation and stage 6's position on that finding, and the report marks them `pending review` | not run: needs a live multi-agent audit run | |
| V3-v | Interruptions: a `.pending` copy left by a stopped import is never read and is removed by the next import or retirement, records no approval, and no committed import's `<k>` is reused; an import stopped after its rename and before reconciliation is reconciled once by the next resume (one approval per entry, no `earlier:` naming its own source); `live/findings.md` deleted by hand after a live rerun is rebuilt from the imports, and stages 6 to 8 rerun | not run: needs a live multi-agent audit run | |
| V3-w | A later `/cca:resume --from 4` on a run with live results retires every active import, moves the derived files and `live/carried/` under `superseded/`, keeps the results files, and a later `--live` import takes the next `<k>`; the same holds when resume restarts from stage 1 after a moved head, for an import never reconciled | not run: needs a live multi-agent audit run | |
| V3-x | Two successive `--live` files with results for `X1` and for `L1`: `live/carried/X1.md` and `L1.md` are written once, from the first import, and the second rerun reviews the same findings | not run: needs a live multi-agent audit run | |
| V3-y | `_test` fails the merger twice on a live rerun with carried `X1` and `L1`: stage 8's fallback reports both carried findings as items, gated by the live rule | not run: needs a live multi-agent audit run | |
| V3-z | `_test.ledger_split_bytes` set so the three ledger files fit under it but the ledger files plus `live/findings.md` and the carried files do not: stage 7 uses split mode, and the carried finding's slice holds its carried file | not run: needs a live multi-agent audit run | |
| V3-aa | `_test.drop_ack` twice on `live/findings.md` in a live rerun: stage 6 fails and the live finding stays provisional | not run: needs a live multi-agent audit run | |
| V3-ab | A live result for an `X<n>` with a Codex rerun that adds new findings: the carried finding keeps its id, the new additions number after it, and the merge check accounts for every id | not run: needs a live multi-agent audit run | |
| V3-ac | At low tier, a live result for a `P<n>` finding: the late adversary runs for it alone, and after both reviews the finding counts | not run: needs a live multi-agent audit run | |
| V3-ad | `/cca:handoff` with an export that has links writes `links:` entries and passes `handoff.sh check`; the hygiene scope judges the status claim against the export | not run: needs a live session with the plugin loaded | |
| V3-ae | `/cca:handoff` for a GitHub issue closed by a PR writes a `closed by` link; stage 1's `<ticket>.json` holds `closed_by`, and the hygiene scope judges the link against it | not run: needs a live session with the plugin loaded | |
| V3-af | `tokens` with `manifest.json`: the bare ids also match `build 4567 passed` and `migrated 4567 rows`; with `manifest-token.json`: `fix(#4567 #4568)` belongs to both tickets and their groups merge into `app-4567+app-4568`, `[4569]` and `AB#4570` go to theirs, and the build and migration commits' files go to `unticketed`, as `expected.md` lists; with `manifest-bad-token.json`: stops before stage 1 with the `ticket_token` line | not run: needs a live multi-agent audit run | |
| V3-ag | `/cca:handoff --verdicts $F/claims-verdicts.md --memory <dir>` lists the files holding `APP-1` for claims 1 and 3, and changes no file in `<dir>` | not run: needs a live session with the plugin loaded | |
| V3-ah | A real run's `work-items.jsonl` with `W<n>` items passes `work-items.sh check` | not run: needs a live multi-agent audit run | |
| V3-ai | A GitHub issue with a parent: `/cca:handoff` writes `parent: github:<repo>#<number>`, stage 1's `<ticket>.parent.json` holds that parent and is in `forge_hashes`, `<ticket>.md` lists it, and the hygiene scope finds the `status` claim's parent matching; for an issue with none, the file holds `{"parent":null}` and the handoff has no `parent` key | not run: needs a live session with the plugin loaded | |
