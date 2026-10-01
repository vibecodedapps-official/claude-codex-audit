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

Built against Claude Code 2.1.284. The static checks, fixture builds, and one budget-0 run
have passed; no full multi-agent audit has run yet (see `docs/acceptance.md`).

## Requirements

- Claude Code with plugin agents and the Agent tool's `model` option.
- `git` 2.29 or later (the fetch commands use an empty `--refmap=`). Each audited repo
  is a local clone.
- For GitHub bundles, `gh` authenticated and `jq`. `jq` is also what validates
  `work-items.jsonl`; without it, the report's Coverage says the file was not validated.
  For any other forge, or without a forge CLI, supply ticket and thread text as exported files (see Exported forge
  files); the report then says the forge was not queried.
- Optional: the Codex CLI and the `codex-lite` plugin, 0.7.0 or later, for the second
  opinion. codex-lite runs Codex from the session's repository root, with no network
  access.

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

## Before the first run

Size the sources before the first run. Any repo that is not checked out cleanly at its
pinned sha is exported into the run directory, and an export copies every tracked blob at
that sha. Its size is the sum of the sizes that
`git -C <repo> ls-tree -r -l --full-tree <ref>` lists. An export over 1 GB asks first.

Agents run no test or lint command in an exported tree. When a repo's tests matter to the
audit, check out the pinned sha cleanly so the repo is read directly.

## Commands

```
/cca:audit [<manifest.json>] [<inputs...>] [--effort low|medium|high]
           [--no-codex] [--codex-model <id>] [--models role=model,...]
           [--questions <file>] [--claims <file>]... [--budget <minutes>]
           [--max-agents <n>] [--codex-timeout <seconds>]
/cca:resume <run-id> [--from <stage>]
/cca:act <run-id> <item-id...> [--per-item]
/cca:handoff [<manifest.json>] [<inputs...>] [--out <path>] [--verdicts <claims-verdicts.md>]
```

- `/cca:handoff` runs in the build session and writes a typed handoff for `/cca:audit`.
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
commands are asked again. If any bundle's head or base has moved since the run
started, resume stops and asks whether to restart from stage 1, since the brief's base
commit list and overlap set depend on the base tip. A GitHub PR's base is the local
`<remote>/<base branch>` ref, which stage 1 always asks to refresh, not GitHub's cached
`baseRefOid`. Resume also re-queries the forge data the
brief used; a difference invalidates stage 1, and if the forge cannot be queried,
resume stops. A run directory with `manifest.json` but no `stages.json` reruns from
stage 1; one without `manifest.json` is unrecoverable.

### `/cca:act`

Item ids are the report's `C<n>` ids. Act never widens the list you give it.
`--per-item` makes one commit per item instead of one per ticket per repo. See Stage 9.

### `/cca:handoff`

Run it in the build session, before the audit. It takes the same input forms as
`/cca:audit` and rejects a bad argument in one line, writing nothing.

- `--out <path>`: where to write the handoff. It must be outside every repo or ignored by
  its repo. Without it, the file goes to `<scratch>/cca/handoff-<YYYY-MM-DD-HHMM>.md` in
  the session's repository, with `<scratch>` chosen as in Run directory, and `-2`, `-3`
  added when that file exists. With neither, the command stops and asks for `--out`. An
  existing file is never overwritten: an `--out` that names one stops the command.
- `--verdicts <claims-verdicts.md>`: a return-trip file from an earlier audit. It is read
  first. A line whose file hash and claim text match the handoff source it names is
  applied; a mismatch is listed as reconciliation work and not applied.

The command settles each bundle's base first: the manifest's `base`, else the PR's base
branch, else the repository's default branch, which it asks you to confirm. It never uses
the branch's upstream tracking ref as the base. It gathers the record (the commit
messages from the merge-base to the head, the forge fields of each ticket, and the
session's own checkpoint record) and writes the handoff from that record only. A deferral
stays a deferral. Where the record shows no alternative was weighed, it writes
`options: none recorded`, and never invents one. It then runs `handoff.sh check` on the
file, fixes and reruns at most three times, and prints the path, the corrections applied,
the reconciliation list, and the `/cca:audit ... --claims <path>` command to run next.
It never edits tracked files, commits, or posts anything.

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
  "scratch": "../app/.scratch",
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
  ccl run's `report.md`, or a handoff written by `/cca:handoff`. Claims are never a source
  of truth. `--claims` adds to these. See Handoff and claims.
- **`scratch`.** An ignored directory inside the primary repo, under any name, where the
  run directory goes, to keep it in the repo. See Run directory.
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

## Handoff and claims

A claims file is a statement of what the build session says it did. cca checks it and
never takes it as true. `/cca:handoff` writes the claims in a typed form, and stage 1 reads
a prose claims file as typed claims too, one kind per sentence. The handoff format is in
`skills/cca/handoff.md`; `/cca:audit` validates a handoff with `handoff.sh` before stage 1
and stops with the script's error lines when it does not pass.

**Claim kinds.**

- `verification`: says something was checked, tested, verified, confirmed, reproduced, or
  passes.
- `decision`: states a choice made or rejected, a deferral, or who decided.
- `scope`: says what belongs in or out of the bundle, or ranks a ticket for inclusion.
- `status`: a work item's type, state, iteration, owner, or links.
- `code`: any other checkable statement about code, data, or behavior.

For prose, the first kind that fits, in the order above, wins. A handoff's kinds come from
`handoff.sh claims`, not from judgment. Every `scope` and `status` claim goes to the
`hygiene` scope. A handoff's commit lists also seed the review groups, along with the
commit messages.

**Verification rule.** A `verification` claim is `true` only when the audit reproduced the
stated result itself, by a run, or by a quote when the stated result is a fact of the code
at the pinned sha. A claim the audit cannot reproduce is `not verified` with the reason
`not reproduced` (not run, no access, needs a live check, budget expired, exported
tree, or setup differs). It is never `true`, and it is not `false` either: `false` is
kept for counter-evidence, and a run under a different setup than the check needs is not
counter-evidence. The pass-two adversary re-checks every verification claim marked
`true`. Reproducing a result does not show that the build session ran its check, and the
report says so once.

**Decision classes.** Each `decision` claim lands in one class: `stale deferral` (an open
deferral with no named person or that nothing tracks), `needs <owner>` (a tracked deferral
with a named person, or a hard-to-reverse or contract-changing choice no person decided),
`default taken` (a taken decision with no alternative weighed in a record the audit can
read), or `evidenced`. Each has a reversibility class: `reversible`, `hard to reverse`, or
`contract change`. Decision entries are report items, not findings: they never enter the
ledger or change the verdict counts. When an entry shows a defect, the auditor files a
separate finding for it.

**Scope check.** For each raised ticket (a `scope` claim) the hygiene scope answers
whether the bundle introduced the behavior, whether the fix lies inside the bundle's repos,
and what it costs. It then recommends `include` or `defer`, and records whether its facts
or its recommendation differ from the handoff's ranking. Report section 8 holds the
decision ledger, the raised tickets, and the other decisions.

**`claims-verdicts.md`.** Stage 8 writes it next to `report.md`, with the report's
revision. It has one entry per claim of each claims file, in claim order, grouped by file
(each group names the file's hash). An entry is a main line with the claim number, kind,
source line, handoff ref, verdict (`true`, `false`, `not verified`, or `contested`),
finding ids, and a pointer to the evidence, followed by two indented sub-lines, `text:`
and `correction:` (a correction or `none`). The text and the correction sit on their own
lines so a `; ` inside them cannot be misread. `false` entries are corrections. `not verified` lines on verification claims are recheck
requests, not evidence the statement is wrong. `contested` entries need a person to decide.

To apply it, run `/cca:handoff --verdicts <claims-verdicts.md>` in the build session. A
line is applied only when its file hash and claim text match the handoff source it names;
a mismatch is listed as reconciliation work. A build session that keeps a memory of its
own work should treat the `false` lines as the entries to correct, so a wrong premise
does not seed the next session.

### Work-item operations

Stage 8 also writes `work-items.jsonl`: one JSON object per operation, ids `W1`, `W2`, and
so on, for a forge adapter or a person to apply. An operation can create a ticket
(`$new:<key>` is a placeholder for an id that does not exist yet), set a field or state,
add a link or comment, or set a description, acceptance criteria, or PR description. The
format is in `skills/cca/work-items.md`. `sh skills/cca/scripts/work-items.sh check` (it
needs `jq`) validates the file against the report body and `claims.md` before the report is
hashed, and the result goes in the report's Coverage. cca 0.2 writes and validates the
plan. No adapter ships, and `/cca:act` applies none of it.

## Stages

1. **Orient.** Resolve the manifest, fetch forge data or read exports, record head,
   base, and merge-base shas, dump a three-dot diff per bundle (a two-dot diff is never
   used, since it shows the base's later changes as reversals), pin every reference and
   source, split the claims into numbered, typed claims, and map every changed file to a
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
8. **Report.** The verdict and the report, written from what is on disk. Stage 8 writes
   three outputs: `report.md`, `claims-verdicts.md` (see Handoff and claims), and
   `work-items.jsonl` (see Work-item operations).
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
"used", because cca does not collect the effective model.

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
the first of: the manifest's `scratch` key, a directory the primary repo already ignores
and uses for scratch (`scratch/`, `tmp/`, `.scratch/`), then `.cca/` if the primary repo
ignores it, else `runs/` in cca's plugin data directory. The `scratch` key must name a
path inside the primary repo that the repo ignores (`git check-ignore` succeeds); a
missing directory is created. Otherwise the run stops before stage 1 with
`scratch <path>: not an ignored path inside <primary repo>`. A resumed run keeps its recorded
directory, even when the manifest's `scratch` has changed since. The run id is
`<YYYY-MM-DD-HHMM>-<slug>`, with a numeric suffix on collision. Every run is recorded in
`runs.json` in cca's plugin data directory, so `/cca:resume` and `/cca:act` find it from
any directory.

The run directory holds all state: the normalized `manifest.json`, `stages.json` (the
only record of which stages are complete), `audit-brief.md`, `claims.md`, `groups.md`,
the diffs, the per-stage outputs, the ledger files, `converged.md`, `report.md`,
`claims-verdicts.md`, `work-items.jsonl`, `act/log.md`, and `usage.md`. A crashed or
interrupted run loses no finished stage, and `/cca:resume` never reuses a stale one.

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
directory, and an explicit `git fetch --no-tags --refmap=` into remote-tracking refs after you
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
the run. Agents with Bash are told to run only read commands (`git show`, `git log`,
`git diff <base>...<head>`, `git grep`, `git ls-files`, `rg`, `ls`) and, when a question
needs a run, the repo's test or lint commands. That is instruction, not enforcement: cca
has no mechanical block on Bash. Instead cca detects changes, with a script the
orchestrator runs rather than a procedure it follows by hand:
`skills/cca/scripts/readonly.sh`. In stage 1,
`snapshot` records each audited repo (status, refs, stash, local config, content hashes
of modified and untracked files, and an inventory of ignored files with sub-second
modification times) and a marker file. After every stage, `check` snapshots again and
prints the differences. A change to tracked files, untracked non-ignored files, refs,
index, stash, or config stops the run `blocked` and shows it (exit status 1). A check
that could not complete, such as a missing baseline file, also stops the run `blocked`
(exit 2). A change among ignored files, or a new remote-tracking ref, is accepted only
when a logged agent run or an approved fetch accounts for it (exit 3). A file newer than
the marker that is neither ignored nor changed in content is listed as touched and does
not stop the run. The git commands cca and its agents issue themselves run without an
index write during an audit or resume: the script sets `GIT_OPTIONAL_LOCKS=0`, the stages
run `git status` with `--no-optional-locks`, and agents run neither `git status` nor a
working-tree diff (a working-tree `git diff` refreshes the index even with that flag). A repo's own
test or lint command, which agents may run in a directly read tree, can run git itself
and is not covered. Stage 9 (act) is the write phase and is outside this boundary.

Nested repositories count as part of the audited repo: a checked-out submodule, or an
untracked directory with its own `.git`, at any depth. The snapshot records each one's
status, HEAD, changed and untracked files, and ignored files, with paths from the top
level, whatever the submodule's `ignore` setting. Every file under a submodule that is not
checked out is hashed, since git does not look there. The status leaves out the count of
commits ahead of and behind the upstream, so a fetch that moves the upstream shows only as
a remote-tracking ref. Where the repo's `core.ignorecase` is true, the run directory is
matched without regard to case.

The script does not support a file name that git prints quoted, even with
`core.quotePath=false`: one holding a double quote, a backslash, a tab, a newline, or
another control character. It exits 2 naming the path. Rename the file or leave it out of
the audited repo.

What is not detected:

- an ignored file replaced with one of the same size and a restored modification time,
  to the precision `stat` reports (sub-second where the system gives it, else seconds);
- changes inside `.git/` other than refs, stashes, and config;
- in a nested repository, a change to a ref other than its HEAD, to its stashes, or to its
  config;
- a change inside a repository that sits in an ignored directory, such as a linked
  worktree, other than an entry added or removed at its top level;
- changes outside the audited repos.

The report says so. Do not edit an audited repo during a run: your own edits trip the
check too.

## Codex is optional

The second opinion (stage 6) goes to Codex through codex-lite when the Codex CLI and
codex-lite are installed. Without them, with `--no-codex`, or when a Codex call is
refused, times out, or fails twice, the role is swapped to a fresh `cca:adversary` agent on Fable, else Opus,
given the same request (one launch per batch of at most 60 mandatory ids). The swap is named in the
report. Stage 6 always runs.

cca never runs the `codex` CLI itself, except `codex --version` to check it is there.
The request names every input by absolute path, and Codex acknowledges each input with
its sentinel. Only an input it could not open goes inline, in the one follow-up, under a
450,000-byte cap. Over the cap, the follow-up is not sent and stage 6 fails.

## Live data and external text

- **Live data.** Credentials and live systems (databases, dashboards, production APIs)
  are used only when a question cannot be answered from code, and only after you say yes
  to that access. Each access is logged in the report. A check you did not approve is
  listed in the report's Live checks section, with the query, where it runs, and what
  each result would mean; the finding stays an unverified assumption, capped at medium,
  until the check runs. A live check result is not fed back into a run: rerun the
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

The pairing is still manual: pass a ccl run's `report.md` as a claims file
(`--claims <path>`). A ccl report is a prose claims file, and stage 1 types each sentence.
`/cca:handoff` can run in any session, including one that ran ccl, and writes the typed
form. Automatic chaining from ccl, and ccl writing a handoff itself, are not implemented;
`skills/cca/handoff.md` is the format ccl could adopt.

## Development

The plugin is prompt files and three small shell scripts (`readonly.sh`, `handoff.sh`,
and `work-items.sh`, under `skills/cca/scripts/`): commands, one orchestrator skill with
its stage files and templates, and five agent definitions. Its checks are:

- `sh tests/lint.sh`: checks the static parts (command and agent frontmatter, no agent
  with Edit or NotebookEdit, every stage file the skill names exists).
- `sh tests/fixture/build.sh <solo|solo-dirty|full>`: builds a throwaway fixture in a
  temp directory and prints its manifest path. Expected outcomes are listed in
  `tests/fixture/expected.md`.
- `sh tests/fixture/verify.sh <manifest path> [name]`: checks a built fixture against
  the key literals in `tests/fixture/expected.md` and prints one line per mismatch. CI
  runs it after each build.
- `sh tests/readonly.sh`: runs `readonly.sh` against a `solo-dirty` fixture, one case per
  kind of difference, and compares output and exit status with literals.
- `sh tests/handoff.sh`: runs `handoff.sh` on the fixture handoff and on valid and broken
  copies, and compares claims, commits, and error lines with literals.
- `sh tests/work-items.sh`: runs `work-items.sh` on a valid file and broken copies. It
  needs `jq`; without it, it prints a note and exits 0.

CI runs the existing lint and fixture job, and a `scripts` job that runs the three new
tests on Linux, macOS, and Windows (under Git Bash). On Linux the default `awk` is gawk,
and a second step runs the awk-using tests (`tests/handoff.sh` and `tests/readonly.sh`)
with mawk first on `PATH` as `awk`. macOS runs them with its own BSD awk.

Acceptance results are recorded in `docs/acceptance.md` and design decisions in
`docs/decisions.md`. On Windows, run the scripts under Git Bash.

## License

Apache-2.0. See `LICENSE` and `NOTICE`.
