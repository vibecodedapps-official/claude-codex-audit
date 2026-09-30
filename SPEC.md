# claude-codex-audit

A Claude Code plugin that takes a finished bundle of work (one or many pull requests,
in one or many repos) and tries to break it before merge. Every stage is adversarial
and evidence-gated. The audit is read-only and stops at a report. The only write phase
is a separate command that acts on items the user approves by id.

Status: final, 2026-09-30. Reviewed by Codex `gpt-6.1-sol` in two rounds on the spec
alone (17 findings, then 6 new), and in three more rounds with the architecture and
build plan (13 findings, then 1, then 1). Every required finding is resolved; the last
one, the pinned-tree export, was also checked by hand. Revised 2026-09-30 after a
hand-audit session's feedback, with a second opinion on the feedback, a critique of the
change plan, and a review of the resulting diff by Codex `gpt-6-astra`. No code exists.

## Problem

Large bodies of work built in rapid succession, often by agents, reach review faster
than a person can check them. Each PR looks fine alone, but the bundle carries semantic
drift from its tickets, rules broken from a guidelines corpus nobody reread, and claims
in the build session's own summary that were never true. A hand-run audit of one such
bundle on 2026-09-29 found real defects, and also showed two traps: a two-dot diff
invented a "deleted features" finding, and a single reviewer pass accepted its own
framing without challenge.

`ccl` (claude-codex-loop) builds and publishes one unit of work. `cca` is its pair: it
audits what was built, across units.

## Goals

1. One command runs a full, repeatable audit of a bundle and ends in a report with
   evidence for every finding.
2. Every finding that counts toward the verdict has been challenged by a reviewer
   other than its author and seen by both a fresh Claude adversary and the second
   opinion. Anything that has not is provisional and does not count (see Review gate).
3. No tracked content in an audited repo changes until the user approves items by id.
4. A crashed or interrupted run loses no finished stage, and never reuses a stale one.
5. The cost of a run is visible, with the source and scope of every number stated.
6. Works without Codex, with a stated swap.
7. The report never claims more than the audit did: an incomplete audit cannot say
   "ready to merge".

## Non-goals

- Replacing per-PR code review, CI, or `ccl`'s own review steps.
- Resolving disagreements between reviewers. The report keeps both positions.
- Editing tickets, PRs, or remote branches without an explicit signal.
- Anything specific to one repo, org, forge, or guidelines corpus.

## Name

Plugin `cca`, repository `claude-codex-audit`, marketplace
`vibecodedapps-claude-codex-audit`. The name follows `claude-codex-loop` (`ccl`), so the
pairing is plain. Commands are `/cca:audit`, `/cca:act`, and `/cca:resume`.

## Roles

| Role | Default | Fallback when the default fails |
|---|---|---|
| Orchestrator | The session's model, in the main session | none, the run ends `blocked` |
| Digester (stage 2) | `cca:digester` agent, Opus | retry once, then the same agent on Fable, else the stage fails |
| Domain mapper (stage 3) | `cca:mapper` agent, Opus | as for the digester |
| Auditor (stage 4) | `cca:auditor` agent, Opus | as for the digester |
| Adversary (stage 5) | `cca:adversary` agent, Opus, fresh context | as for the digester |
| Second opinion (stage 6) | Codex `gpt-6.1-sol` through `/codex-lite:ask` | `cca:adversary` on Fable, else Opus, given the Codex request |
| Merger (stage 7) | `cca:merger` agent, Sonnet | the orchestrator |

Role agents are plugin agent definitions under `agents/`, each with a tool list. Every
agent is launched explicitly by the orchestrator as a new agent, never as a fork. Role
models are overridden with `--models role=model,...` or the manifest's `models` key,
using the values the Agent tool accepts. `--codex-model` sets the Codex model; Codex
model ids are always the full id.

A fallback swaps who fills a role. It never removes a stage. Every swap is named in the
report. The report records the requested model for each agent. cca 0.1 does not
collect the effective model, so the report says "requested", not "used".

### Stage applicability

A stage is **not applicable** when its input does not exist: stage 2 without a document
corpus among the sources of truth, stage 3 without a code base among them. A stage
**fails** when it is applicable and neither the default nor the fallback produced a
complete output. A not-applicable stage counts as satisfied for every stage that waits
on it and is listed in Coverage. A failed stage also counts as satisfied for waiting
stages, so the run goes on, but its coverage loss is recorded and the run ends
`partial`.

## Hard rules

These hold for every stage and are copied into the run's `common.md`.

1. **Read-only boundary.** During `/cca:audit` and `/cca:resume`, nothing changes an
   audited repo's tracked files, untracked non-ignored files, the index, branches,
   tags, stashes, config, or remotes.
   "Audited repo" here means every bundle, reference, and source of truth. Allowed
   writes: the run directory; cca's data directory (`runs.json`); codex-lite's own
   request and thread files in codex-lite's data directory, written when cca calls it;
   and `git fetch` into remote-tracking refs, after the user approves it once per run.
   Nothing else. An ignored file written by a check run that an agent logged under its
   `runs:` heading is allowed and reported, never silently.
2. **Prevention and detection.** Agent tool lists exclude Edit and NotebookEdit.
   Agents that need Bash are told to run only these commands: `git show`, `git log`,
   `git diff`, `git grep`, `git ls-files`, `rg`, `ls`, and, when a question needs a
   run, the repo's test or lint commands, which may write ignored build output. That
   is instruction, not enforcement: 0.1 has no mechanical block on Bash. Instead the
   orchestrator detects changes. In stage 1 it creates a marker file in the run
   directory and snapshots, for each audited repo:
   `git status --porcelain=v2 --branch --untracked-files=all`,
   `git for-each-ref`, `git stash list`, `git config --list --local`, a content hash
   of every modified and untracked file, and an inventory of every ignored file with
   its size and modification time, all outside `.git/` and the run directory. At the
   end of every stage it takes the snapshot again and compares, and also lists any
   file newer than the marker (`find <repo> -newer <marker> -type f`), filtered through
   `git check-ignore --stdin` and excluding the run directory. A difference in tracked
   files, untracked non-ignored files, refs, index, stash, or config, including an added
   or deleted file, stops the run `blocked` and shows it, unless an approved fetch
   caused it. Each check writes `baseline/<stage>-check.md`, listing the ignored-file
   differences it accepted, or none. A difference among ignored files is accepted
   provisionally when any agent with Bash, in any stage, is running or has finished
   since the previous check; stages 2, 3, and 4 overlap, so the stage being checked
   need not be the one that ran. Once those agents have finished, the next check
   reconciles each accepted difference against their `runs:` headings; a difference no
   logged run accounts for stops the run `blocked` then. A difference with no such
   agent running or finished stops the run `blocked` at once. After a check passes,
   the accepted ignored-file inventory becomes the baseline for the next check; the
   tracked and untracked baseline never moves. Not detected: an ignored file replaced with one of
   the same size and a restored modification time, changes inside `.git/` other than
   refs, stashes, and config, and changes outside the audited repos. The report says
   so.
   The user should not edit audited repos during a run, since their own edits trip the
   check too.
3. **No model, agent, or tool names** in anything external: commit messages, PR or
   ticket text, and drafted comments. The report is internal and may name them.
4. **No `advisor` tool**, in the orchestrator or any agent.
5. **Live data.** Credentials and live systems (databases, dashboards, production
   APIs) are used only when a question cannot be answered from code, and only after the
   user says yes to that access. Each access is logged in the report. A check not
   approved is listed in the report's Live checks section.
6. **Evidence.** A claim is not a fact until evidence is cited (see Evidence).
7. **Disk first.** Every agent writes its output file before it reports back and
   returns only the path and a one-line status.
8. **Claims are not facts.** The session summary being audited is a list of claims to
   verify, never a source of truth.

## Evidence

Every piece of evidence names its repo and the commit it was read at. Three kinds:

- **Quote:** `repo@sha:path:line`, with the quoted lines.
- **Search:** the exact command, its scope, and its result, including an empty result.
  This is how absence is shown.
- **Run:** the exact command, where it ran, and the output, marked as cut where cut.
  Every run is logged under the agent's `runs:` heading, per hard rule 2.

Forge evidence is a URL with a quote. A finding separates what the evidence
**demonstrates** from what it **infers**. The label `verified fact` requires that the
defect itself is demonstrated, by a quote plus a causal explanation, or by a run.
Otherwise the label is `unverified assumption` and the severity may not exceed
`medium`. `convention` marks a finding that rests on a ranked source's rule, not on
broken behavior.

## Prerequisites

- Claude Code with plugin agents and the Agent tool's `model` option. The README
  records the version the release was tested on.
- `git`. Each audited repo is a local clone.
- For GitHub bundles, `gh` authenticated. Any other forge, or a missing forge CLI:
  the user supplies ticket and thread text as exported files, recorded with their
  provenance (see Exported forge files), and the report says the forge was not queried.
- Optional: Codex CLI and `codex-lite` 0.7.0 or later. codex-lite runs Codex from the
  session's repository root, with no network access. For Codex to read the run
  directory by path, start the session in the primary repo.

## Commands

```
/cca:audit [<manifest.json>] [<inputs...>] [--effort low|medium|high]
           [--no-codex] [--codex-model <id>] [--models role=model,...]
           [--questions <file>] [--claims <file>]... [--budget <minutes>]
           [--max-agents <n>] [--codex-timeout <seconds>]
/cca:act <run-id> <item-id...> [--per-item]
/cca:resume <run-id> [--from <stage>]
```

`/cca:audit` runs stages 1 to 8 and stops. `/cca:act` runs stage 9. `/cca:resume`
reruns from a stage, reusing only artifacts whose inputs have not changed.

## Inputs

Inputs come from a manifest file, from the prompt, or both. Relative paths in a
manifest are relative to the manifest's directory; in the prompt, to the session's
directory. The orchestrator states the merged, normalized manifest before stage 1 and
saves it as `manifest.json` in the run directory.

```json
{
  "bundles": [
    { "repo": "../app", "pr": "github:owner/app#123", "base": "origin/main",
      "tickets": ["github:owner/app#159", "file:./exports/ab-4567.md"] }
  ],
  "references": [
    { "name": "legacy", "path": "../legacy-app", "ref": "main" }
  ],
  "sources_of_truth": [
    { "rank": 1, "name": "legacy source", "path": "../legacy-app", "ref": "main" },
    { "rank": 2, "name": "guidelines", "path": "../guidelines", "ref": "main" }
  ],
  "claims": ["./session-summary.md"],
  "forge_exports": { "command": "az boards work-item show --id 4567",
                     "exported_at": "2026-09-29" },
  "groups": [
    { "name": "auth", "repo": "../app", "files": ["src/auth/**"] }
  ],
  "questions": "default",
  "models": { "adversary": "opus", "merger": "sonnet" }
}
```

- **Bundles.** A repo path plus a PR, a branch, or both, and a base. A PR resolves head
  branch and base from the forge. A bundle whose `pr` is a `file:` export must also
  give `branch` and `base`, since no forge resolves them. When the manifest gives a
  branch or base that disagrees with the PR, the run stops before stage 1 and shows
  both. A bundle with no resolvable base is rejected. Short ids such as `#159` are
  accepted only when the bundle's repo has one GitHub remote; otherwise ids are
  written `github:owner/repo#n`
  or `file:<path>`.
- **References.** Read-only repos consulted only when a question needs them. Each is
  pinned to the sha its `ref` resolves to in stage 1.
- **Sources of truth, ranked.** Rank decides which side wins a conflict and how
  findings are labeled. The default order is legacy source code, then a guidelines
  corpus, then the audited repo's own docs (`AGENTS.md`, `CLAUDE.md`, `README.md`,
  `docs/`), then ticket text. Legacy and guidelines are included only when supplied.
  A manifest that lists `sources_of_truth` replaces the default, and the brief states
  the order used. Each is pinned to a sha in stage 1.
- **Claims.** One or more files, such as the build session's summary or a `ccl` run's
  `report.md`.
- **Questions.** The four defaults, or a file that replaces or extends them.
- **`_test`.** Fault injection for the plugin's own fixture checks only, such as
  treating a named scope's first completion as failed. Undocumented in the README and
  recorded in the report when present.

### Exported forge files

One file per ticket or PR, as markdown with a frontmatter block or as JSON. A ticket
requires `id`, `url`, `title`, `state`, and `description`, and may have
`acceptance_criteria`, `fields` (name and value), `links`, and `comments` (author, date,
text). A PR requires `id`, `url`, `title`, and `body`, and may have `reviews` and
`threads` (file, line, comments). Every file requires the provenance keys `source`,
`exported_by`, and `exported_at`. A missing required key stops the run before stage 1
with `export <path>: missing <key>`. A missing optional key is listed in the brief as
"not in export", and the hygiene auditor reads the brief and reports it. The manifest's
`forge_exports` key records the command and date; cca never runs it.

### Audit questions

- `Q1` best practice: does the change follow the ranked sources and the repo's own
  conventions?
- `Q2` semantic drift: does the code do what the ticket and the claims say, no more and
  no less?
- `Q3` technical debt: what does the change leave for later, and is that recorded?
- `Q4` decision quality: were the choices the change made the right ones, which
  alternatives existed, and which does the auditor recommend, with the reason?

`--questions <file>` takes a markdown list of `id: question` lines. A line
`extends: default` keeps the four.

## Effort

Effort sets how the work is split and how deep pass two digs. At every tier, every
question is asked, every applicable source is read, every changed file is reviewed,
every claim is checked, and stages 5 and 6 run.

The tier is the first row whose conditions all hold. `--effort` overrides it, and the
brief states the tier and why.

| Tier | Conditions | Pass one | Pass two on Verified OK | Late adversary |
|---|---|---|---|---|
| low | 1 bundle, 1 ticket, under 500 changed lines | one auditor covering the ticket, tests, and work-item hygiene | no | no; late additions stay provisional |
| medium | up to 3 bundles, up to 5 tickets, under 5,000 changed lines | one auditor per group, plus one for tests and work-item hygiene, plus cross-bundle interactions when there is more than one bundle | up to 5 items per report | yes |
| high | anything else | one per group, plus tests, plus work-item hygiene, plus cross-bundle interactions when there is more than one bundle | all items | yes |

The low tier departs from the original idea's separate tests and hygiene auditors: at
one ticket and under 500 lines, one auditor covers all three with the same checklist,
and the report says so.

## Run directory

The **primary repo** is the session's repository if it is one of the bundles,
otherwise the first bundle. `<scratch>` is the first match of: a directory the primary
repo already ignores and uses for scratch (`scratch/`, `tmp/`, `.scratch/`, confirmed
with `git check-ignore`), then `.cca/` if the primary repo ignores it, else
`<plugin data>/runs/`. The run directory is `<scratch>/cca/<run-id>/`. The run id is
`<YYYY-MM-DD-HHMM>-<slug>`, and a numeric suffix is added on collision. Every run is
recorded in `<plugin data>/runs.json` with its absolute path, so `/cca:resume` and
`/cca:act` find it from any directory.

```
manifest.json             normalized inputs
stages.json               per-stage inputs, input hashes, outputs, status
audit-brief.md            scope, tier, bundles, shas, drift, source order
common.md                 hard rules, evidence rules, schemas
claims.md                 every sentence from the claims files, numbered
groups.md                 changed file to review group map
diffs/<bundle>.diff       three-dot diff per bundle
diffs/<bundle>.stat       file list with change counts
forge/<bundle>/           PR body, threads, ticket text
guidelines/digest-N.md    stage 2
domain/<source>-map.md    stage 3
pass1/<group>.md          stage 4
pass2/<group>.md          stage 5
ledger/5.md               stage 5: every finding with its pass-two verdicts
ledger/6.md               stage 6: the second opinion's dispositions
ledger/7.md               stage 7: the late adversary's verdicts
codex/request.md          stage 6 request
codex/response.md         stage 6 answer, verbatim
converged.md              stage 7
report.md                 stage 8
act/log.md                stage 9
usage.md                  per-stage agents, tokens, wall-clock
```

`stages.json` is the only record of completion. A stage is complete when every output
it lists exists and the stage's entry says `complete`. The entry is written last.
`stages.json` and `runs.json` are written to a temporary file beside the destination
and renamed. Each ledger file is written once by the orchestrator. "The ledger" means
their concatenation in order; nothing leaves it.

## Stages

### 1. Orient (orchestrator)

1. Resolve and normalize the manifest. Ask once for approval to `git fetch` the repos
   whose refs are missing or stale.
2. For each bundle, fetch forge data, or read the exports: PR title, body, reviews,
   threads, and each linked ticket's text and comments. Save under `forge/`.
3. Record for each bundle: head sha, base sha, merge-base sha, commits on the base
   since the merge-base, and files changed on both sides since the merge-base. Record
   the pinned sha of every reference and source of truth.
4. Dump the diff with three dots, `git diff <base>...<head>`, per bundle. A two-dot
   diff is never used, because it shows changes on the base as reversals on the head.
5. Stacked and multi-repo bundles: when one bundle's base is another bundle's head,
   record the stack. The brief states the combined state under audit: each bundle at
   its head, with stacks read in order.
6. Readable trees, for every bundle at its head sha and every reference and source of
   truth at its pinned sha. If the repo's working tree is at that sha with no tracked
   changes, agents read it directly. Searches in a directly read tree use `git grep` at
   the pinned sha, or `rg` over `git ls-files`; a symlink is not followed outside the
   repo; a citation to an untracked, ignored, or outside path is invalid evidence.
   If the tree is not read directly, the orchestrator exports the exact tree, with
   symlinks as placeholder files, into `<run dir>/trees/<name>/`, writing only to the
   run directory. The export
   writes each blob from `git ls-tree -r <sha>` with `git cat-file`, so no checkout
   filter, smudge or process driver, or attribute runs. `git archive` and
   `git checkout-index` are not used: the first honors `export-ignore` and
   `export-subst`, and the second runs configured filters, which can reach the network
   or write outside the run directory. File modes follow the tree; a symlink is
   exported as a regular file holding its target, listed in the brief, and never
   dereferenced; submodule entries are listed, not exported. An export over 1 GB is
   asked about first; if declined, that repo is read with `git show <sha>:<path>` and
   only agents with Bash may be assigned to it.
   `audit-brief.md` maps each name to the path agents must read. An export holds
   tracked files only, so a check run that needs installed dependencies is done only
   in a working tree read directly; otherwise the question is marked "not run".
7. Split the claims files into `claims.md`: every sentence, numbered, with its source
   file and line, classified as `claim` (a checkable statement about the work) or
   `other`, and tagged with the bundle and ticket it concerns. Nothing is dropped.
8. Map every changed file to a review group in `groups.md`. A ticket's group holds the
   files that the PR description, commit messages, or ticket text name, and files
   touched only by that ticket's commits. Files no ticket explains go to an
   `unticketed` group. A file whose mapping is uncertain is listed in both groups with
   a note. A file present in more than two derived groups moves to `cross-cutting` and
   is listed in each former group with a note. After that extraction, two groups merge
   when each has more than half of its remaining files in the other, checked pairwise
   in ticket order, once. A manifest `groups` key, when present, replaces the
   derivation, the extraction, and the merge: globs are relative to the entry's `repo`;
   a file matching two entries goes to both with a note; changed files no entry
   matches go to `unticketed`.
9. Assign every `claim` to the group that will check it. A claim about a
   `cross-cutting` file goes to `cross-cutting`.
10. Write `audit-brief.md` and `common.md`. The read-only baseline (hard rule 2) is
    taken right after the approved fetch in step 1, before any export or other stage 1
    work, so everything after it is checked.

### 2. Digest (`cca:digester`, one per ~450 KB)

For each document corpus among the sources of truth, the orchestrator splits the text
files by directory into chunks of about 450 KB, listing skipped binary files. Each
digester reads its chunk in full and writes a cited rule list: rule text, `MUST`,
`SHOULD`, or `MAY`, `repo@sha:path:line`, and a `potential finding:` line wherever a
rule collides with a claim or the diff stat, naming the group. Auditors cite the
original document, never the digest.

### 3. Domain map (`cca:mapper`, one per code base among the sources of truth)

For each code base among the sources of truth, the orchestrator writes a per-ticket
question list from the tickets and claims: how the source handles what the ticket
changes. In a legacy-parity audit this is the parity question list. Each mapper
answers the list against its source with quotes, and notes where two sources disagree.
Auditors cite the source at its sha, never the map, as for digests.

### 4. Pass one (`cca:auditor`)

One auditor per review group, plus the specialists the tier adds:

- **Tests:** coverage of new behavior, weakened or skipped tests, CI config changes.
- **Work-item hygiene:** tickets match the change, acceptance criteria met or not,
  follow-ups recorded.
- **Cross-bundle interactions** (whenever there is more than one bundle): shared
  contracts, schemas, and APIs changed in one bundle and used in another, and stack
  order.

Stages 2, 3, and 4 start together. Auditors read whatever digests and maps exist, and
list in their output each digest and map file they read, with its content hash.

Each finding uses this schema:

```
### <group>-F<n>: <one-line title>
- severity: blocker | high | medium | low | note
- question: Q1 | Q2 | Q3 | Q4 | <custom id>
- label: verified fact | unverified assumption | convention
- claims: <claim numbers tested, or none>
- evidence: <quote, search, or run, per Evidence>
- demonstrated: <what the evidence shows>
- inferred: <what follows from it but is not shown>
- what the code does:
- what breaks, and for whom:
- recommended change: <repo> <path> <change>
- alternatives: <each weighed, and the one recommended>
- live check: <query>; <where it runs>; <what each result changes>; or none
- work-item impact: <ticket, acceptance criterion, or none>
```

A finding with a live check keeps `unverified assumption` and its cap until the check
has run. The check runs inside the audit only after the user approves that access per
hard rule 5; otherwise it is listed in the report for the user to run. A missing
rationale in the ticket or PR is not by itself a defect.

Each report also has a **Verified OK** list, items checked and found sound with
evidence, and a **Claims** list: each assigned claim with `true`, `false`, or
`not verified`, and the finding or evidence.

**Reconciliation barrier.** When stages 2 and 3 are each complete, failed, or not
applicable, the orchestrator compares each pass-one report's list of consumed files
with the final digests and maps. For each report that missed a digest or map, or read
an earlier revision of one, a top-up `cca:auditor` applies every rule in that digest
and every answer in that map to the group's files, not only the `potential finding`
lines, and appends its findings and its consumed-file list to the group's file.
Stage 5 does not start on a group until its barrier is cleared.

### 5. Pass two (`cca:adversary`, one per pass-one report)

Each adversary is a new agent, so it does not inherit pass one's framing. It receives
`audit-brief.md`, `common.md`, and one pass-one report. For each finding it opens every
citation, looks for counter-evidence, and challenges severity and label. Verdict per
finding: `survives`, `downgraded`, `reworded`, or `dropped`, each with evidence. It
then attacks the Verified OK list as the tier allows, and ends with a coverage-gaps
list. New findings it raises carry `origin: pass2` and are **late additions**.

Each adversary report also ends with a `map corrections` list: map file, line, what is
wrong, and the source quote that shows it. The orchestrator writes each corrected map
as `domain/<source>-map.r2.md` with a corrections header. For every group whose
pass-one consumed-file list names the corrected map, a top-up `cca:auditor` applies the
corrected answers to the group's files and writes findings tagged `origin: topup` to
`pass2/<group>-topup.md`, a stage 5 output, so the completed stage 4 files do not
change. Top-ups run before stage 6 starts. Top-up findings are late additions and pass
the review gate through stage 6 and the late adversary. One round: a correction a
top-up raises is recorded in the brief, not reissued. A failed top-up follows the
auditor failure rule.

The orchestrator writes `ledger/5.md`: every finding ever raised, with its original
text, every pass-two verdict on it, and its state after pass two. Nothing leaves the
ledger.

### 6. Second opinion (Codex)

The orchestrator writes `codex/request.md` from `ledger/5.md`: the brief, the claims,
the diff paths, every finding with its verdicts, including dropped ones, and the
coverage gaps. It asks, in order, for a verdict with its own evidence on every blocker
and high, a position on every finding pass two downgraded or dropped, dropped findings
to restore, up to ten findings no reviewer raised, severity recalibration, and an
advisory merge verdict per bundle that never replaces the report's rules. The answer
is capped at 3,000 words, with at most two quoted lines per citation. Each
generated run-directory file the request names starts with a sentinel line; audited
sources never get one. The request asks Codex to acknowledge each input by quoting its
sentinel. A missing acknowledgment means access is not confirmed: the orchestrator
retries once with those inputs inlined. If any input is still unacknowledged, stage 6
fails, the findings it covered do not pass the review gate on its account, and the run
ends `partial`.

Inlining means the request carries the full content of every input it would otherwise
name, each under a header with its run-directory path and its sentinel, so the request
names no file Codex must open. Audited source files are not inlined; the diffs are.
The inline form applies both when the run directory is outside the session's repo and
in the retry after a missing acknowledgment. When the inline request would exceed
450,000 bytes, it is not sent; stage 6 is swapped to the fallback, which reads inputs
by path, with the reason "request too large for inline form". The brief notes that a
run directory inside the session's repo avoids the inline form.

Call contract, following `ccl` except where noted:

- The call goes through the Skill tool, `codex-lite:ask`. The orchestrator never runs
  the `codex` CLI, except `codex --version` to check availability.
- codex-lite runs Codex from the root of the repository that contains the session's
  working directory. The orchestrator cannot move it there, because Claude Code resets
  the shell's directory between calls. So the Codex repo is the session's repo. When
  the run directory is outside it, every input is inlined in the request instead of
  named by path. When the session's directory is not in a git repository, codex-lite
  refuses, and the refusal is handled as below.
- Every call passes `--model <full id>` and `--timeout`, set by tier: low 1,200
  seconds, medium 2,400, high 3,600. `--codex-timeout <seconds>` overrides it, 1 to
  3,600, else rejected in one line. The stage 6 entry in `stages.json` records the
  model and timeout passed. This includes a follow-up, which uses `--resume <thread
  id>` explicitly. At most one follow-up.
- Availability is decided from `codex --version` and the installed codex-lite version.
- codex-lite's status line decides handling: `failed` or a missing status is retried
  once, then swapped to the fallback; `refused` is not retried and is swapped with the
  message recorded; `timeout` is swapped. This differs from `ccl`, which ends in
  `blocked` on `refused` or `timeout`: `ccl` is about to publish work, while an audit
  that stops loses every finding so far, and the swap is named in the report.
- With `--no-codex`, the fallback fills the role from the start.

The answer is saved verbatim in `codex/response.md` and its dispositions are added to
`ledger/6.md`. Findings Codex adds are late additions.

### 7. Converge (`cca:merger`, then orchestrator)

**Late adversary.** At medium and high, one fresh `cca:adversary` challenges every
late addition, including `origin: topup`, and every finding Codex asked to restore,
with the stage 5 verdicts. It reads `ledger/5.md` and `ledger/6.md`, and the
orchestrator writes its verdicts to `ledger/7.md`. There is no further round: anything
the late adversary itself raises is provisional.
At low, there is no late adversary.

**Review gate.** A finding **counts** when a reviewer other than its author has
challenged it, and both a Claude adversary and the second opinion have seen it, in
any role. So a pass-one finding counts after stages 5 and 6; a pass-two addition
counts after stage 6 and the late adversary; a Codex addition counts after the late
adversary. Anything else is **provisional** and does not count toward the verdict.

The merger then reads `ledger/5.md`, `ledger/6.md`, and `ledger/7.md` and writes
`converged.md`: one item per distinct
defect, with every source that raised it. Each item has its gate (`counts` or
`provisional`) and one disposition:

- `agreed`: the reviewers who saw it accept it at one severity.
- `contested`: the reviewers disagree on existence or severity. Both positions are
  kept with their evidence. The merger never picks a side.
- `dismissed`: dropped and not restored, kept with the reason.

Item ids are `C<n>`, stable once written, with the ledger ids each one absorbs.

When the ledger files together exceed 450,000 bytes, one merger per group writes
`converged/<group>.md` (item, sources, each position's severity and label,
disposition, gate, absorbed ledger ids, ledger section pointer), then one merger reads
those files and writes `converged.md`, assigning `C<n>` ids and opening a ledger
section only for a suspected cross-group duplicate.

The orchestrator checks the merge against the ledger: every ledger finding maps to one
item, and no severity changed without a cited verdict.

### 8. Report (orchestrator)

`report.md`, in this order:

1. **Verdict.** `not ready`, `merge after fixes`, or `ready to merge`, with counts by
   severity, gate, and disposition. Only items that count are used. Any `agreed`
   blocker or high item means `not ready`. Any `agreed` medium means at best
   `merge after fixes`. A `contested` item counts at the higher severity only when the
   higher position's label is `verified fact`; otherwise at the lower. When one
   position is `dropped`, the item counts only if the keeping position is
   `verified fact`, at its severity. Equal severities count at that severity. With
   more than two positions, the highest position's label decides. The verdict line
   reports the contested count. `dismissed` items do not count. In a `partial` run,
   the verdict is `audit incomplete`, with the counts so far; it is never
   `ready to merge`.
2. Findings by ticket, severity first, each with evidence, state, and item id.
3. Verified as sound: every Verified OK item, marked `challenged` or `not challenged`
   per the tier's pass two rule.
4. Disagreements kept: every `contested` item with both positions and evidence.
5. Recommended next steps.
6. Code fixes by repo and file, with item ids.
7. Work-item fixes: ticket text to change, drafted.
8. Decisions, each with the recommendation, the reason, and a reversibility class:
   `reversible`, `hard to reverse`, or `contract change`. A named owner from the
   tickets or threads only for `hard to reverse` and `contract change`, else "owner not
   recorded". Act may post a decision to its ticket as a drafted comment only when the
   user says to for that item, per stage 9 step 6.
9. Live checks: for each finding with a live check, its id, the query, where it runs,
   and the severity each result implies. In 0.1 a result is not fed back into a run;
   the user reruns the audit or acts on the finding by hand.
10. Claims: every numbered claim with `true`, `false`, or `not verified`.
11. Coverage: stages run, not applicable, failed, or swapped, and why; unanswered
    questions; departures from the original stage plan.
12. Usage per stage.

The report's first line records its revision: the sha-256 of the file body below that
line. The run stops, printing the report path, the verdict, and the terminal state.

Stage 8 always runs, even after a failed stage or an expired budget. In those cases
the orchestrator writes the report from whatever is on disk: the ledger if it exists,
else the pass-one and pass-two files, with every finding not yet through the review
gate marked provisional.

### 9. Act (`/cca:act`, gated)

Takes a run id and item ids the user approved. It never widens the list.

1. Show each approved item with the report revision, and confirm. Approval is bound to
   the run, the revision, and the items. If the report has changed since, stop.
2. Check each affected repo: the checkout must be on the bundle's branch with no
   uncommitted changes. If not, stop and say what differs. Nothing is stashed or reset.
3. Compare the branch head with the audited head. Commits that `act/log.md` records as
   made by act are expected. Any other new commit is drift: show it and ask before
   going on.
4. Before the first change in each repo, run the repo's required checks and the
   checks that cover the approved items, and record the results as the baseline,
   including any failures already present.
5. Group approved items by ticket and repo from their work-item impact. An item with
   more than one ticket goes to the first listed, noted in the log. Make one commit per
   ticket per repo, and one per item for items with no ticket; `--per-item` commits
   each item alone. When two tickets' changes touch one file, stage each ticket's
   hunks with `git apply --cached` from a byte-exact patch that preserves line
   endings; overlapping hunks stop and ask. For each commit: make and stage the
   change, rerun the checks that cover it, then the repo's required checks, show the
   diff and both results against the baseline, and ask before the commit. Checks run
   after each commit's staging, not once at the end. A check that passed at baseline
   and now fails is marked as introduced, and the commit is not offered until the user
   decides. A failure present at baseline is reported as preexisting and is not act's
   to fix. Commit messages follow the repo's convention and name no model or tool.
6. Never push, and never edit tickets or PRs, until the user says to for that item.
7. Log every action, check result, and commit sha in `act/log.md`.

## Resume

`/cca:resume <run-id> [--from <stage>]` finds the run through `runs.json`. For each
stage, `stages.json` records the hashes of its inputs: manifest, claims, questions,
source shas, bundle shas, upstream stage outputs, and the plugin version. Resume
reruns from the earlier of `--from` and the first stage that is incomplete or whose
input hashes changed, reruns every stage after it, and marks their old outputs
superseded. Approvals are recorded in `stages.json` and not asked again on resume. If
any bundle's head sha has
changed since orient, resume stops and asks whether to restart from stage 1.

## Budget and usage

- `--max-agents` caps concurrent subagents across the run (default 8). Work beyond the
  cap is queued. Scope is never merged or dropped to fit the cap.
- `--budget <minutes>` is a soft wall-clock budget with no default: it applies only
  when given. `0` expires as soon as stage 1 completes, which makes the budget path
  testable. When it runs out, running agents finish, no new stage from 2 to 7 starts,
  finished stages are checkpointed, stage 8 writes the report from what is on disk,
  and the run ends `partial` with a resume command. The orchestrator prints elapsed
  time and agents run at each stage boundary.
- `usage.md` records per stage the agents run, their requested models, wall-clock, and
  tokens as reported by each agent's completion notification. Every token number is
  labeled with its source and its scope as the platform documents it (for example,
  "final request only"). Where a number is not reported, including Codex through
  codex-lite, it says "not reported". No total is presented as exact.

## Terminal states

- `reported`: every applicable stage complete.
- `partial`: a report was written, but a stage failed or the budget ran out. The
  verdict is `audit incomplete`.
- `blocked`: no report could be written, or the read-only check failed. The reason is
  printed and every finished stage file is kept.

## Pairing with ccl

In 0.1 the pairing is manual: a `ccl` run's report can be passed as a claims file.
Automatic chaining ("a PR over N commits or N tickets runs `cca` before it leaves
draft") is not implemented or validated. Claude Code hooks can add context or block an
action, but no supported mechanism for one plugin to start another plugin's command
has been confirmed. The likely route is a `ccl` report line that suggests `/cca:audit`
above a size threshold, which is a change to `ccl` and is deferred.

## Repository layout

```
.claude-plugin/plugin.json
.claude-plugin/marketplace.json
commands/audit.md
commands/act.md
commands/resume.md
skills/cca/SKILL.md          orchestrator
skills/cca/common.md         template for the run's common.md
skills/cca/report.md         report template
agents/digester.md
agents/mapper.md
agents/auditor.md
agents/adversary.md
agents/merger.md
README.md  CHANGELOG.md  LICENSE  NOTICE
SPEC.md
docs/architecture.md
docs/build-plan-v0.1.0.md
docs/acceptance.md
docs/decisions.md
tests/lint.sh
tests/fixture/build.sh
tests/fixture/expected.md
```

## Deferred past 0.1

- Native Azure DevOps and other forge fetching. 0.1 accepts exported files.
- Automatic trigger from `ccl`.
- Exact token accounting.
- A PreToolUse hook that enforces the read-only boundary mechanically.
- Feeding a live check result back into a run. In 0.1 the user reruns the audit or
  acts on the finding by hand.

## Resolved questions

1. **Role agents.** Plugin agent definitions under `agents/`, with tool lists that
   exclude Edit, plus the stage-end read-only check, because tool lists alone do not
   constrain Bash.
2. **Worktrees.** Not used. An export into the run directory, exact with symlinks as
   placeholder files, gives agents a pinned tree without writing any repo metadata, so
   the read-only boundary needs no worktree exception.
3. **Azure DevOps.** Deferred. Exported ticket and thread files cover it in 0.1 (see
   Exported forge files).
4. **Run location.** The primary repo is the session's repo if it is a bundle, else
   the first bundle. The absolute run path is stored in `runs.json`.
