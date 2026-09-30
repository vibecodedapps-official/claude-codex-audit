# Build plan: v0.1.0

Pre-implementation plan for the first release of `cca`, drafted 2026-09-30 from
`SPEC.md` and `docs/architecture.md`, revised the same day after review, and revised
2026-09-30 after the audit feedback round. Each
milestone adds one capability to a run that already works end to end and ends with
named acceptance cases. `SPEC.md`, this file, and `docs/architecture.md` are tracked
and updated in the milestone that changes them.

## Order of work

The smallest useful audit is orient, one auditor, one adversary, a second opinion,
and a report, on a single-bundle fixture with no document or code sources. That path
works first; Codex, sources, scale, resume, and act come after it.

| # | Milestone | Adds | Depends on |
|---|---|---|---|
| M0 | Skeleton | Manifests, three commands, skill and stage stubs, five agent stubs, lint check, fixture builder, README stub | nothing |
| M1 | Orient and report | Stage 1 in full, run directory, `runs.json`, `stages.json`, read-only check, stage applicability, low-tier selection, stage 8 from what is on disk, `--budget 0` | M0 |
| M2 | Low tier, no Codex | Stages 4, 5, 7 (merger, review gate), verdict rules, second opinion by fallback only, per-role failure handling, `_test` fault injection | M1 |
| M3 | Codex | Stage 6 through codex-lite, the call contract, sentinels, inline form | M2 |
| M4 | Sources and scale | Stages 2 and 3, the barrier, medium and high tiers, specialists, late adversary, the queue, the soft budget, usage | M3 |
| M5 | Resume | Input hashing, invalidation, `--from` | M4 |
| M6 | Act | Stage 9 | M2 |
| M7 | Release | Acceptance record, README, decisions doc, changelog, version 0.1.0, marketplace entry | M0 to M6 |

M6 depends only on M2 and can be built beside M3 to M5. M6-g needs `full` and runs after
M4.

## Fixtures

`tests/fixture/build.sh <name>` builds one fixture in a new temp directory and prints
its manifest path. Every expected outcome is written as a literal in
`tests/fixture/expected.md` in M0 and changes only with a recorded reason. Scripts are
POSIX sh, run under Git Bash on Windows. Fixture content over a few KB lives in files
under `tests/fixture/`, not in heredocs.

| Fixture | Contents | First used |
|---|---|---|
| `solo` | One app repo. The base moves after the merge-base and touches a file the feature also changed. One ticket file. The feature has: one high defect against the ticket (drift), one skipped test, one decoy that looks wrong but is correct, and a claims file with one false claim and one true claim. It also has a test command that writes an ignored file, an untracked file containing a string that matches the drift defect, and a claim only production data can settle ("every existing row was migrated"). Its one ticket file is an export with no `acceptance_criteria`. A second export with no `title` sits beside it and is named only by the manifest M1-h uses. | M1 |
| `solo-dirty` | `solo`, with the checkout left on another branch, one modified tracked file, one untracked file, and one ignored file. The head commit has one symlink to an absolute path outside the fixture, a `.gitattributes` marking one test file `export-ignore`, one file `export-subst` containing `$Format:%H$`, and one file `filter=probe`; the repo's local config defines `filter.probe.smudge` and `filter.probe.process` as commands that create `<fixture dir>/filter-ran`. | M1 |
| `full` | `solo` plus a second repo whose API the app's change breaks, a guidelines corpus of about 1 MB with one `MUST` rule the app breaks, and a legacy repo whose checkout is on a different commit from its pinned ref. It also has one file touched by three tickets, two contested findings (one `convention`, one `verified fact`), and a CRLF file touched by two tickets. | M4 |

## M0: skeleton

Files:

- `.claude-plugin/plugin.json`: name `cca`, version `0.1.0`, description, license
  `Apache-2.0`, author `vibecodedapps.net`, repository
  `https://github.com/vibecodedapps-official/claude-codex-audit`.
- `.claude-plugin/marketplace.json`: marketplace `vibecodedapps-claude-codex-audit`,
  owner `vibecodedapps.net`, one plugin entry.
- `commands/audit.md`, `commands/resume.md`, `commands/act.md`, per the architecture.
- `skills/cca/SKILL.md` with the preamble and one heading per stage, each pointing to
  a stage file that says "not implemented" and stops the run. The preamble states the
  compaction recovery rule: re-read the invocation block, `audit-brief.md`, `common.md`,
  `stages.json`, and the current stage file before any action.
- `agents/digester.md`, `mapper.md`, `auditor.md`, `adversary.md`, `merger.md` with
  frontmatter (name, description, model, tools) and a one-line body.
- `tests/lint.sh`, `tests/fixture/build.sh`, `tests/fixture/expected.md`.
- `README.md` stub, `CHANGELOG.md` with an unreleased section. `LICENSE` and `NOTICE`
  exist.

Cases:

- `M0-a`: `claude --plugin-dir .` loads the plugin and the three commands appear.
- `M0-b`: `/cca:audit --bogus` is rejected in one line, and nothing is written.
- `M0-c`: `/cca:audit <solo manifest>` reaches stage 1 and stops with "not
  implemented".
- `M0-d`: a probe settles architecture decisions 1 to 5; answers go in the decisions
  draft.
- `M0-e`: `tests/lint.sh` passes, and fails when an agent file lists Edit.

## M1: orient and report

- Stage 1 steps 1 to 10, including exports of every bundle, reference, and source at
  its pinned sha when the checkout is not at it.
- Exported forge file parsing, with a stop before stage 1 when a required key is
  missing.
- Run directory selection, run ids, `runs.json`.
- `stages.json`, with entries written last, and its `approvals` list.
- The read-only check after each stage, with `baseline/<stage>-check.md`.
- Stage applicability and effort tier selection. Only the low tier runs stages past
  1 in this milestone; medium and high stop with "not implemented".
- Stage 8 writing a report from what is on disk; `--budget 0`; the soft budget when set.

Cases:

- `M1-a` (`solo`): the brief lists the merge-base, the base's later commit, and the
  file changed on both sides; `diffs/app.diff` does not contain the base's later
  change; every sentence of the claims file is in `claims.md`; every changed file is in
  `groups.md`, which has one ticket group and no `cross-cutting` group; the tier is
  `low`.
- `M1-b` (`solo --budget 0`): the run ends `partial` with verdict `audit incomplete`.
- `M1-c` (`solo-dirty`): the app is read from an export under `trees/`, and the dirty
  checkout is unchanged at the end. The `export-ignore` test file is present in the
  export, the `export-subst` file still contains the literal `$Format:%H$`, and
  `<fixture dir>/filter-ran` does not exist. The symlink is in the export as a regular
  file whose content is its absolute target path, and the brief lists it.
- `M1-d` (`solo-dirty`): between two stages, append a line to the already modified
  file; the run ends `blocked` and names it. Repeat with the untracked file, the
  modification of the ignored file, and the deletion of the ignored file. M1 runs no
  agents, so nothing logs a run and every ignored-file change blocks.
- `M1-f`: a manifest whose branch disagrees with its PR's head branch stops before
  stage 1 and shows both.
- `M1-e`: two runs on `solo` in the same minute get different run ids, and both are
  in `runs.json`.
- `M1-g` (`solo-dirty`): after a clean stage, `baseline/1-check.md` exists and lists no
  ignored-file differences.
- `M1-h` (`solo`): the ticket export with no `acceptance_criteria` runs, and the brief
  lists it as "not in export"; the manifest that adds the export with no `title` stops
  the run before stage 1 with `export <path>: missing title`.

## M2: low tier, no Codex

- `auditor` and `adversary` bodies: finding schema, Evidence rules, Verified OK and
  Claims lists, verdicts, coverage gaps, `origin: pass2`, the `live check` and
  `alternatives` fields. Agents log each run under `runs:`. Direct-read searches use
  `git grep` at the pinned sha or `rg` over `git ls-files`.
- `ledger/5.md` from pass one and pass two.
- Stage 6 filled by the fallback `adversary`, recorded as a swap.
- Stage 7: review gate, `merger` body, `C<n>` ids, the orchestrator's check against the
  ledger. No late adversary at low.
- Stage 8 in full: all twelve sections, including Live checks, verdict rules, revision
  line.
- Per-role failure handling and `_test` fault injection.

Cases, all on `solo`:

- `M2-a`: verdict `not ready`; the drift defect is `agreed` and `counts`; the false
  claim is `false` and the true claim is `true`, each with evidence; the skipped test
  is found; no finding says a feature was deleted; the drift finding's `alternatives`
  field names one recommendation; the report has sections 3 and 4, and every item in
  section 3 is marked `not challenged`, the low tier's pass two rule.
- `M2-b`: the decoy is `dismissed` with a reason, or absent, and never counts.
- `M2-c`: a pass-two addition with no late adversary is `provisional` and does not
  change the verdict counts.
- `M2-d` (`_test` fails auditor scope once): one relaunch on the same model, no swap.
- `M2-e` (`_test` fails auditor scope twice): relaunch on Fable, recorded as a swap.
- `M2-f` (`_test` fails auditor scope three times): the scope fails, and the run ends
  `partial` with verdict `audit incomplete`.
- `M2-g` (`_test` fails the merger once): the orchestrator merges, recorded as a swap.
- `M2-h`: the claim "every existing row was migrated" has a finding that is
  `unverified assumption` with a `live check` field, appears in section 9, and the
  verdict counts do not exceed `medium` for it.
- `M2-i` (`solo`, read directly): the auditor runs the fixture's test command, which
  writes an ignored file; the run ends `reported`, and `baseline/4-check.md` names the
  file as attributed to that run.
- `M2-j` (`solo`, read directly): no finding cites the untracked file that contains the
  string matching the drift defect.

## M3: Codex

- `skills/cca/codex-request.md`, request building from the ledger including dismissed
  findings and the template order, the 3,000-word answer cap, sentinels on generated
  files only, the inline form and its 450,000-byte cap.
- The call contract: full model id, timeout by tier, the `--codex-timeout` flag and its
  validation, explicit `--resume`, status handling, swaps, the `codex --version` probe.
- Review gate rules for Codex additions. The late adversary that clears them arrives
  in M4, so at low tier they stay provisional.

Cases, all on `solo`:

- `M3-a`: `codex/response.md` holds the verbatim answer, and every Codex disposition
  is in the ledger.
- `M3-b` (`--no-codex`): the fallback fills the role and the report names the swap.
- `M3-c` (session started outside any git repo): codex-lite refuses, the run swaps and
  finishes `reported`.
- `M3-d` (run directory forced outside the session's repo): the request is in inline
  form and names no run-directory file.
- `M3-e` (`_test` drops one acknowledgment twice): stage 6 fails and the run ends
  `partial` with verdict `audit incomplete`.
- `M3-f` (`_test` fails the fallback twice, with `--no-codex`): Fable fails, Opus
  fails, and stage 6 fails.
- `M3-g`: `--codex-timeout 0` is rejected in one line; the stage 6 entry in
  `stages.json` records timeout `1200` at low, and `3600` with `--codex-timeout 3600`.
- `M3-h` (`_test` sets the inline cap to 1,000 bytes, run directory forced outside the
  session's repo): stage 6 is swapped to the fallback, the report names the reason
  "request too large for inline form", and the run ends `reported`.

## M4: sources and scale

- `digester` and `mapper` bodies; corpus split at about 450 KB by directory; binary
  files listed.
- Reconciliation barrier with consumed-file hashes and top-up auditors.
- Hub extraction into `cross-cutting`, the manifest `groups` key, and `unticketed`.
- Map corrections: the adversary's `map corrections` list, `domain/<source>-map.r2.md`,
  and top-ups writing `pass2/<group>-topup.md` tagged `origin: topup` before stage 6.
- Medium and high tiers and the specialists: tests, work-item hygiene (reading the
  "Exported forge files" subsection's optional keys), cross-bundle interactions.
- Late adversary and its gate rules, including `origin: topup`.
- Per-group mergers writing `converged/<group>.md` when the ledger files together
  exceed 450,000 bytes.
- Global queue under `--max-agents`, pass one launched first.
- The soft budget during stages 2 to 7, when set.
- `usage.md` with token source and scope.

Cases, all on `full`:

- `M4-a`: the broken `MUST` rule is found and cites the guideline file at its pinned
  sha, not the digest.
- `M4-b`: the legacy repo is read from an export at its pinned sha, not its checkout.
- `M4-c`: the cross-repo API break is found by the interaction auditor.
- `M4-d` (`_test` holds the digest chunk with the `MUST` rule until pass one has
  finished): a top-up auditor runs for the affected group, its file lists the digest's
  hash, and the broken `MUST` rule finding first appears in the top-up's section.
- `M4-e` (`_test` fails one digester scope three times): stage 2 fails, the barrier
  clears, and the run ends `partial`.
- `M4-f` (`--max-agents 2`): `stages.json` start and end times never show more than
  two agents running, and every token number in `usage.md` has a source and scope
  label.
- `M4-i` (`_test` expires the budget when stage 3 completes): no stage from 4 on
  launches new agents, stage 8 runs, and the run ends `partial`.
- `M4-g`: a Codex addition cleared by the late adversary `counts`; a finding the late
  adversary raises is `provisional`; with `--effort high` the stage 6 entry in
  `stages.json` records timeout `3600`.
- `M4-h`: the `convention` contested finding, which pass two downgrades and Codex
  disputes, is `contested` and is counted at its lower severity.
- `M4-j`: the file touched by three tickets is in `cross-cutting` and listed in each
  former group with a note; a rerun with a manifest `groups` key of two entries yields
  exactly those two groups plus `unticketed`.
- `M4-k` (`_test` plants one wrong line in the legacy map): `domain/legacy-map.r2.md`
  exists with a corrections header, a top-up runs for the group that consumed the map
  and writes `pass2/<group>-topup.md`, the group's `pass1/` file is unchanged, and the
  top-up's finding carries `origin: topup` and is `provisional` until the late
  adversary clears it.
- `M4-l` (`_test` sets the ledger split threshold to 1,000 bytes): `converged/` has one
  file per group, and `converged.md` maps every ledger id.
- `M4-m`: the `verified fact` contested finding is counted at its higher severity.

## M5: resume

- Input hashes per stage, invalidation of later stages, superseded outputs.
- `--from`, and the head-sha change stop.

Cases, all on `full` after a complete run:

- `M5-a`: edit the claims file and resume; stages 1 to 8 rerun and the old outputs are
  marked superseded.
- `M5-b`: `--from 5` reruns stages 5 to 8, reuses stages 1 to 4, and marks
  `ledger/5.md`, `ledger/6.md`, and `ledger/7.md` superseded.
- `M5-c`: move the app's branch head; resume stops and asks.
- `M5-d`: `--from 6` reruns stages 6 to 8, reuses `ledger/5.md` unchanged, and marks
  `ledger/6.md` and `ledger/7.md` superseded.

## M6: act

- Report revision binding, clean-checkout check, own-commit tracking in `act/log.md`.
- Baseline checks, per-ticket commits, after checks, introduced versus preexisting
  failures, ask per commit, no push, no forge edits unless the user says to for that
  item.

Cases, all on `solo` after a complete run unless stated:

- `M6-a`: approving the drift item produces one local commit after one confirmation,
  with no push.
- `M6-b`: a second `/cca:act` on the same run does not call the first commit drift.
- `M6-c`: a hand-made commit on the branch is reported as drift.
- `M6-d`: a dirty checkout stops act with nothing stashed.
- `M6-e`: a check failing at baseline is reported as preexisting; a check the change
  breaks is reported as introduced and no commit is offered.
- `M6-f`: editing the report after approval stops act.
- `M6-g` (`full`): two approved items on two tickets that share the CRLF file give two
  commits, each passing its checks, and the file's line endings are unchanged.

## M7: release

- `docs/acceptance.md`: one line per case above, with the date, the Claude Code
  version, and pass or fail, and the table below with every row covered.
- `README.md`: what it is, install, commands, manifest, effort, the read-only boundary
  and its limits, Codex optional, pairing with `ccl`, the Claude Code version tested.
- `docs/decisions.md`: the resolved questions and the M0 decisions, with dates.
- `CHANGELOG.md` 0.1.0 entry, version bump in both manifests.
- Tag and release only after the user approves.

Cases: `tests/lint.sh` passes; every case in `docs/acceptance.md` passed on the
release candidate; a fresh install from the marketplace loads the plugin.

## Spec coverage

| Spec section | Milestone | Cases |
|---|---|---|
| Hard rules 1 and 2, read-only boundary and detection | M1, M2 | M1-c, M1-d, M1-g, M2-i |
| Hard rules 3 and 4, names and advisor | M0, M6 | inspection of agent and stage files; M6-a checks the commit message |
| Hard rule 5, live data | M2 | M2-h |
| Evidence | M2, M4 | M2-a, M2-j, M4-a |
| Inputs, manifest, conflicts, ids, exported forge files | M1 | M1-a, M1-f, M1-h |
| Grouping and hub files | M1, M4 | M1-a, M4-j |
| Sources of truth, pinned | M1, M4 | M1-c, M4-a, M4-b |
| Effort tiers | M1, M4 | M1-a, M4-c |
| Run directory, run ids, `runs.json` | M1 | M1-e |
| Stage 1 | M1 | M1-a to M1-d |
| Stages 2 and 3, applicability | M1, M4 | M4-a, M4-e |
| Stage 4 and the barrier | M2, M4 | M2-a, M4-d |
| Stage 5 and the ledger | M2 | M2-a, M2-b |
| Map corrections and top-ups | M4 | M4-k |
| Stage 6 and the call contract | M3 | M3-a to M3-f |
| Codex request shape and timeout | M3 | M3-g |
| Merger size and inline cap | M3, M4 | M3-h, M4-l |
| Stage 7, late adversary, review gate | M2, M4 | M2-c, M4-g, M4-h, M4-m |
| Stage 8, verdict, revision | M2 | M2-a, M2-f, M1-b |
| Stage 9 | M6 | M6-a to M6-f |
| Act commits per ticket | M6 | M6-g |
| Roles and fallbacks | M2, M3 | M2-d to M2-g, M3-b, M3-f |
| Resume | M5 | M5-a to M5-c |
| Per-stage ledger files | M5 | M5-b, M5-d |
| Compaction recovery | M0 | inspection of the preamble |
| Atomic state | M1 | inspection |
| Budget and usage | M1, M4 | M1-b, M4-f, M4-i |
| Terminal states | M1 to M3 | M1-b, M1-d, M3-c |

## Commits

Each milestone is one or more commits in the form `type(scope): subject`, lowercase,
with a body that says why.

## Open items

- Whether `gh api` GET calls can be pre-approved narrowly enough in `allowed-tools`, or
  must prompt.

## Out of scope

Anything not in `SPEC.md`. Changes to `ccl` or `codex-lite`. Items the spec defers.
