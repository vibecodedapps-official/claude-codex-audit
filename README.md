# claude-codex-audit (cca)

A Claude Code plugin that takes a finished bundle of work (one or many pull requests, in
one or many repos) and tries to break it before merge. Every stage is adversarial and
evidence-gated. The audit is read-only and stops at a report. The only write phase is a
separate command that acts on items you approve by id.

Each pull request in a large bundle can look fine alone while the bundle drifts from its
tickets, breaks rules in a guidelines corpus nobody reread, and carries claims in the
build session's summary that were never true. cca checks the bundle as a whole: every
finding cites evidence, is challenged by a reviewer other than its author, and is seen by
both a fresh Claude adversary and a second opinion before it counts toward the verdict.

cca is the pair of [ccl](https://github.com/vibecodedapps-official/claude-codex-loop)
(claude-codex-loop): ccl builds and publishes one unit of work, cca audits what was
built, across units.

Tested on Claude Code 2.1.284.

## Requirements

- Claude Code with plugin agents and the Agent tool's `model` option.
- `git`. Each audited repo is a local clone.
- For GitHub bundles, `gh` authenticated and `jq`. For any other forge, or without a
  forge CLI, supply ticket and thread text as exported files (see Exported forge
  files); the report then says the forge was not queried.
- Optional: the Codex CLI and the `codex-lite` plugin, 0.7.0 or later, for the second
  opinion. codex-lite runs Codex from the session's repository root, with no network
  access. For Codex to read the run directory by path, start the session in the primary
  repo.

## Install

The repo is its own marketplace. In Claude Code:

```
/plugin marketplace add vibecodedapps-official/claude-codex-audit
/plugin install cca@vibecodedapps-claude-codex-audit
```

To try a local clone without installing it:

```
git clone https://github.com/vibecodedapps-official/claude-codex-audit.git
claude --plugin-dir <path-to-clone>
```

## Commands

```
/cca:audit [<manifest.json>] [<inputs...>] [--effort low|medium|high]
           [--no-codex] [--codex-model <id>] [--models role=model,...]
           [--questions <file>] [--claims <file>]... [--budget <minutes>]
           [--max-agents <n>] [--codex-timeout <seconds>]
/cca:resume <run-id> [--from <stage>]
/cca:act <run-id> <item-id...> [--per-item]
```

- `/cca:audit` runs stages 1 to 8 and stops at the report.
- `/cca:resume` reruns a run from a stage, reusing only the stages whose inputs have not
  changed.
- `/cca:act` runs stage 9 on the items you approve.

An unknown flag or a bad value is rejected in one line, and nothing is written.

### `/cca:audit` flags

| Flag | Value | Default |
|---|---|---|
| `--effort` | `low`, `medium`, or `high`; overrides the tier cca picks | picked from the bundle's size (see Effort) |
| `--no-codex` | none; the fallback reviewer gives the second opinion | Codex, when available |
| `--codex-model` | a full Codex model id | `gpt-6.1-sol` |
| `--codex-timeout` | seconds, 1 to 3600 | by tier: low 1,200, medium 2,400, high 3,600 |
| `--models` | `role=model,...`, roles `digester`, `mapper`, `auditor`, `adversary`, `merger`, models as the Agent tool accepts them (`opus`, `sonnet`, `haiku`, `fable`) | see Roles |
| `--questions` | a markdown file of `id: question` lines | the four default questions |
| `--claims` | a claims file; repeat the flag for more | none |
| `--budget` | a soft wall-clock budget in minutes; `0` expires once stage 1 completes | no budget |
| `--max-agents` | the most subagents running at once across the run | 8 |

Prompt inputs are repo paths, PR and ticket ids (`github:owner/repo#n`, `#n` when the
repo has one GitHub remote, or `file:<path>`), and files, and they merge with the
manifest. Relative paths in the prompt are relative to the session's directory. cca
states the merged, normalized manifest before stage 1 and saves it in the run directory.

### `/cca:resume`

`--from <stage>` takes a stage number from 1 to 8. Resume reruns from the earlier of
`--from` and the first stage that is incomplete or whose inputs changed, reruns every
stage after it, and marks their old outputs superseded. Approvals you gave are not
asked again, except that a fetch approval covers only the commands it listed (an
approval for a bare name covers either candidate refspec for it); other fetch
commands are asked again. If any bundle's head has moved since the run started,
or its base has moved so that the merge base changed, resume stops and asks whether to
restart from stage 1. A base that moved with the merge base unchanged does not stop it:
the old base sha is kept for every diff and the move is recorded as `base moved` in
the report, but only when stage 1 is reused; when stage 1 reruns it pins the base
again (for a GitHub PR, the local `<remote>/<base branch>` ref after any approved
fetch, not GitHub's cached `baseRefOid`). Resume also re-queries the forge data the
brief used; a difference invalidates stage 1, and if the forge cannot be queried,
resume stops. A run directory with `manifest.json` but no `stages.json` reruns from
stage 1; one without `manifest.json` is unrecoverable.

### `/cca:act`

Item ids are the report's `C<n>` ids. Act never widens the list you give it.
`--per-item` makes one commit per item instead of one per ticket per repo. See Stage 9.

## Manifest

Inputs come from a manifest file, from the prompt, or both. Relative paths in a manifest
are relative to the manifest's directory.

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

- **`bundles`.** A repo path plus a PR (`pr`), a branch (`branch`), or both, and a base
  (`base`), with the bundle's `tickets`. A PR resolves its head branch and base from the
  forge. A bundle whose `pr` is a `file:` export must also give `branch` and `base`,
  since no forge resolves them. When the manifest gives a branch or base that disagrees
  with the PR, the run stops before stage 1 and shows both. A bundle with no resolvable
  base is rejected. Short ids such as `#159` are accepted only when the bundle's repo has
  one GitHub remote; otherwise ids are written `github:owner/repo#n` or `file:<path>`.
- **`references`.** Read-only repos consulted only when a question needs them, each with
  a `name`, a `path`, and a `ref`. Each is pinned to the sha its `ref` resolves to in
  stage 1.
- **`sources_of_truth`.** Ranked sources, each with a `rank`, a `name`, a `path`, and a
  `ref`. Rank decides which side wins a conflict and how findings are labeled. The
  default order is legacy source code, then a guidelines corpus, then the audited repo's
  own docs (`AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/`), then ticket text. Legacy and
  guidelines are included only when supplied. A manifest that lists `sources_of_truth`
  replaces the default, and the brief states the order used. Each is pinned to a sha in
  stage 1.
- **`claims`.** One or more files to verify, such as the build session's summary or a
  ccl run's `report.md`. Claims are never a source of truth. `--claims` adds to these.
- **`forge_exports`.** The `command` used to export forge files and the date
  (`exported_at`). It is a record only; cca never runs it.
- **`groups`.** Optional review groups, each with a `name`, a `repo`, and `files` globs
  relative to that repo. When present, it replaces the groups cca would derive. A file
  matching two entries goes to both with a note; changed files no entry matches go to an
  `unticketed` group.
- **`questions`.** `"default"` for the four default questions, or a path to a questions
  file, as for `--questions`.
- **`models`.** Per-role model overrides, as for `--models`.

### Exported forge files

For a forge cca does not query, supply one file per ticket or PR, as markdown with a
frontmatter block or as JSON, and name it as `file:<path>`.

- A ticket requires `id`, `url`, `title`, `state`, and `description`, and may have
  `acceptance_criteria`, `fields` (name and value), `links`, and `comments` (author,
  date, text).
- A PR requires `id`, `url`, `title`, and `body`, and may have `reviews` and `threads`
  (file, line, comments).
- Every file requires the provenance keys `source`, `exported_by`, and `exported_at`.

A missing required key stops the run before stage 1 with `export <path>: missing <key>`.
A missing optional key is listed in the audit brief as "not in export", and the
work-item hygiene review reports it.

## Audit questions

- `Q1` best practice: does the change follow the ranked sources and the repo's own
  conventions?
- `Q2` semantic drift: does the code do what the ticket and the claims say, no more and
  no less?
- `Q3` technical debt: what does the change leave for later, and is that recorded?
- `Q4` decision quality: were the choices the change made the right ones, which
  alternatives existed, and which does the auditor recommend, with the reason?

`--questions <file>` takes a markdown list of `id: question` lines that replaces the
four. A line `extends: default` keeps the four and adds yours.

## Stages

1. **Orient.** Resolve the manifest, fetch forge data or read exports, record head,
   base, and merge-base shas, dump a three-dot diff per bundle (a two-dot diff is never
   used, since it shows the base's later changes as reversals), pin every reference and
   source, split the claims into numbered sentences, and map every changed file to a
   review group.
2. **Digest.** Digester agents turn each document corpus among the sources into a cited
   rule list. Not applicable without a document corpus.
3. **Domain map.** Mapper agents answer per-ticket questions against each code base
   among the sources. Not applicable without one.
4. **Pass one.** One auditor per review group, plus the specialists the tier adds.
   Stages 2, 3, and 4 start together, and a top-up auditor covers any digest or map a
   group's auditor missed.
5. **Pass two.** A fresh adversary per pass-one report opens every citation, looks for
   counter-evidence, and rules on each finding.
6. **Second opinion.** Codex, or the fallback, reviews every finding, including dropped
   ones, and may restore findings or add new ones. Every blocker, high, and
   downgraded or dropped finding must get a position, in batches of at most 60 ids
   (Codex takes two batches; the fallback takes any further ones).
7. **Converge.** A late adversary challenges late additions (at medium and high), then
   a merger folds the ledger into one item per distinct defect, `C1`, `C2`, and so on.
8. **Report.** The verdict and the report, written from what is on disk.
9. **Act.** Only through `/cca:act`, on items you approve.

A finding **counts** toward the verdict only when a reviewer other than its author has
challenged it and both a Claude adversary and the second opinion have seen it. Anything
else is **provisional** and does not count. Reviewers who disagree are both kept, as a
`contested` item; cca never picks a side.

The verdict is `not ready`, `merge after fixes`, or `ready to merge`, from the items that
count. An incomplete audit says `audit incomplete` and never `ready to merge`.

## Roles

| Role | Default | Fallback when the default fails |
|---|---|---|
| Orchestrator | the session's model, in the main session | none; the run ends `blocked` |
| Digester (stage 2) | `cca:digester` agent, Opus | retry once, then the same agent on Fable, else the stage fails |
| Domain mapper (stage 3) | `cca:mapper` agent, Opus | as for the digester |
| Auditor (stage 4) | `cca:auditor` agent, Opus | as for the digester |
| Adversary (stage 5) | `cca:adversary` agent, Opus, fresh context | as for the digester |
| Second opinion (stage 6) | Codex `gpt-6.1-sol` through codex-lite | `cca:adversary` on Fable, else Opus |
| Merger (stage 7) | `cca:merger` agent, Sonnet | the orchestrator |

A fallback swaps who fills a role; it never removes a stage. Every swap is named in the
report. The report records the requested model for each agent and says "requested", not
"used", because cca 0.1 does not collect the effective model.

## Effort

Effort sets how the work is split and how deep pass two digs. At every tier, every
question is asked, every applicable source is read, every changed file is reviewed,
every claim is checked, and stages 5 and 6 run.

The tier is the first row whose conditions all hold. `--effort` overrides it, and the
audit brief states the tier and why.

| Tier | Conditions | Pass one | Pass two on Verified OK | Late adversary |
|---|---|---|---|---|
| low | 1 bundle, 1 ticket, under 500 changed lines | one auditor covering the ticket, tests, and work-item hygiene | no | no; late additions stay provisional |
| medium | up to 3 bundles, up to 5 tickets, under 5,000 changed lines | one auditor per group, plus one for tests and work-item hygiene, plus cross-bundle interactions when there is more than one bundle | up to 5 items per report | yes |
| high | anything else | one per group, plus tests, plus work-item hygiene, plus cross-bundle interactions when there is more than one bundle | all items | yes |

At low, one auditor covers the ticket, tests, and hygiene with the same checklist, and
the report says so.

## Run directory

The **primary repo** is the session's repository if it is one of the bundles, otherwise
the first bundle. The run directory is `<scratch>/cca/<run-id>/`, where `<scratch>` is
the first of: a directory the primary repo already ignores and uses for scratch
(`scratch/`, `tmp/`, `.scratch/`), then `.cca/` if the primary repo ignores it, else
`runs/` in cca's plugin data directory. The run id is `<YYYY-MM-DD-HHMM>-<slug>`, with a
numeric suffix on collision. Every run is recorded in `runs.json` in cca's plugin data
directory, so `/cca:resume` and `/cca:act` find it from any directory.

The run directory holds all state: the normalized `manifest.json`, `stages.json` (the
only record of which stages are complete), `audit-brief.md`, `claims.md`, `groups.md`,
the diffs, the per-stage outputs, the ledger files, `converged.md`, `report.md`,
`act/log.md`, and `usage.md`. A crashed or interrupted run loses no finished stage, and
`/cca:resume` never reuses a stale one.

### Terminal states

- `reported`: every applicable stage complete.
- `partial`: a report was written, but a stage failed or the budget ran out. The verdict
  is `audit incomplete`, and cca prints a resume command.
- `blocked`: no report could be written, or the read-only check failed. The reason is
  printed and every finished stage file is kept.

The run stops by printing the report path, the verdict, and the terminal state.

## Read-only boundary

During `/cca:audit` and `/cca:resume`, nothing changes an audited repo's tracked files,
untracked non-ignored files, the index, branches, tags, stashes, config, or remotes. An
audited repo is every bundle, reference, and source of truth. The only writes are the
run directory, `runs.json`, codex-lite's own request and thread files in its data
directory, and an explicit `git fetch --no-tags` into remote-tracking refs after you
approve the listed commands (a remote configured with `remote.<name>.prune` may also
delete stale remote-tracking refs). An ignored file written by a check run that an
agent logged is allowed and reported.

When a repo's checkout is not at the audited sha, or has changes, cca exports the exact
tree into the run directory from git objects, so no checkout filter or attribute runs and
nothing is written to the repo. Symlinks are exported as placeholder files holding their
target, and submodules are listed, not exported. An export over 1 GB is asked about
first.

Role agents' tool lists exclude Edit and NotebookEdit. Each agent has Write, limited by
instruction to its own output file in the run directory; the read-only check after every
stage, described below, is the guard that detects a change to an audited repo and stops
the run. Agents with Bash are told to run only read commands (`git show`, `git log`, `git diff`,
`git grep`, `git ls-files`, `rg`, `ls`) and, when a question needs a run, the repo's
test or lint commands. That is instruction, not enforcement: 0.1 has no mechanical
block on Bash. Instead cca detects changes. It snapshots each audited repo in stage 1
(status, refs, stash, local config, content hashes of modified and untracked files, and
an inventory of ignored files) and compares after every stage. A change to tracked
files, untracked non-ignored files, refs, index, stash, or config stops the run
`blocked` and shows it. A change among ignored files is accepted only when a logged
agent run accounts for it.

What is not detected:

- an ignored file replaced with one of the same size and a restored modification time;
- changes inside `.git/` other than refs, stashes, and config;
- changes outside the audited repos.

The report says so. Do not edit an audited repo during a run: your own edits trip the
check too.

## Codex is optional

The second opinion (stage 6) goes to Codex through codex-lite when the Codex CLI and
codex-lite are installed. Without them, with `--no-codex`, or when a Codex call is
refused, times out, fails twice, or would need an inline request over 450,000 bytes,
the role is swapped to a fresh `cca:adversary` agent on Fable, else Opus, given the same
request (one launch per batch of at most 60 mandatory ids). The swap is named in the
report. Stage 6 always runs.

cca never runs the `codex` CLI itself, except `codex --version` to check it is there.
Codex runs from the session's repository, so when the run directory is outside it, the
request carries every input inline instead of naming files. Starting the session in the
primary repo avoids that.

## Live data and external text

- **Live data.** Credentials and live systems (databases, dashboards, production APIs)
  are used only when a question cannot be answered from code, and only after you say yes
  to that access. Each access is logged in the report. A check you did not approve is
  listed in the report's Live checks section, with the query, where it runs, and what
  each result would mean; the finding stays an unverified assumption, capped at medium,
  until the check runs. In 0.1 a live check result is not fed back into a run: rerun the
  audit or act on the finding by hand.
- **External text.** Anything cca drafts for outside use (commit messages, PR or ticket
  text, and comments) names no model, agent, or tool. The report is internal and may
  name them.

## Stage 9: act

`/cca:act <run-id> <item-id...>` shows each approved item with the report's revision and
asks you to confirm. Approval is bound to the run, the revision, and the items; if the
report changed since, act stops. Each affected checkout must be on the bundle's branch
with no uncommitted changes; act never stashes or resets. New commits on the branch that
act did not make are shown as drift before it goes on.

Act runs the repo's required checks first as a baseline, then makes one local commit per
ticket per repo (or per item with `--per-item`), rerunning the checks for each and asking
before each commit. A check the change breaks is marked introduced and that commit is
not offered until you decide; a failure present at baseline is reported as preexisting.
Act never pushes and never edits tickets or PRs until you say to for that item. Every
action is logged in `act/log.md` in the run directory.

## Budget and usage

`--max-agents` caps concurrent subagents; extra work is queued, never merged or dropped.
`--budget` is soft: when it runs out, running agents finish, no new stage from 2 to 7
starts, the report is written from what is on disk, and the run ends `partial` with a
resume command. cca prints elapsed time and agents run at each stage boundary.

`usage.md` records per stage the agents run, their requested models, wall-clock time,
and tokens as reported in each agent's completion notification. Every token number is
labeled with its source; the scope of that number is not documented by the platform,
and the label says so. Codex usage through codex-lite is "not reported". No total is
presented as exact.

## Pairing with ccl

In 0.1 the pairing is manual: pass a ccl run's `report.md` as a claims file
(`--claims <path>`). Automatic chaining from ccl is not implemented.

## Development

The plugin is prompt files only: commands, one orchestrator skill with its stage files
and templates, and five agent definitions. Its checks are:

- `sh tests/lint.sh`: checks the static parts (command and agent frontmatter, no agent
  with Edit or NotebookEdit, every stage file the skill names exists).
- `sh tests/fixture/build.sh <solo|solo-dirty|full>`: builds a throwaway fixture in a
  temp directory and prints its manifest path. Expected outcomes are listed in
  `tests/fixture/expected.md`.
- `sh tests/fixture/verify.sh <manifest path> [name]`: checks a built fixture against
  the key literals in `tests/fixture/expected.md` and prints one line per mismatch. CI
  runs it after each build.

Acceptance results are recorded in `docs/acceptance.md` and design decisions in
`docs/decisions.md`. On Windows, run the scripts under Git Bash.

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
