---
name: cca
description: The orchestrator for the cca plugin. It is loaded by /cca:audit, /cca:resume, and /cca:act, and runs an adversarial, evidence-gated, read-only audit of a bundle of pull requests, or acts on approved report items. Do not trigger this skill in any other way, and do not load it for general questions about auditing or code review.
user-invocable: false
allowed-tools:
  - Bash(git status *)
  - Bash(git --no-optional-locks status *)
  - Bash(git diff *)
  - Bash(git log *)
  - Bash(git show *)
  - Bash(git rev-parse *)
  - Bash(git merge-base *)
  - Bash(git for-each-ref *)
  - Bash(git stash list *)
  - Bash(git check-ignore *)
  - Bash(git hash-object --no-filters *)
  - Bash(git grep *)
  - Bash(git -C * status *)
  - Bash(git -C * --no-optional-locks status *)
  - Bash(git -C * diff *)
  - Bash(git -C * log *)
  - Bash(git -C * show *)
  - Bash(git -C * rev-parse *)
  - Bash(git -C * merge-base *)
  - Bash(git -C * for-each-ref *)
  - Bash(git -C * stash list *)
  - Bash(git -C * check-ignore *)
  - Bash(git -C * hash-object --no-filters *)
  - Bash(git -C * grep *)
  - Bash(git config --list --local)
  - Bash(git -C * config --list --local)
  - Bash(git remote -v)
  - Bash(git -C * remote -v)
  - Bash(git ls-files *)
  - Bash(git -C * ls-files *)
  - Bash(git -C * ls-tree *)
  - Bash(git -C * cat-file *)
  - Bash(gh pr view *)
  - Bash(gh issue view *)
---

# cca orchestrator

You are the orchestrator of one `cca` run in the main session. `/cca:audit` runs stages
1 to 8 and stops at a report. `/cca:resume` reruns an audit from a stage, reusing only
artifacts whose inputs have not changed. `/cca:act` runs stage 9, the only write phase,
on items the user approved by id. Follow the steps in order. The long procedure for
each stage is in its stage file; read that file at the start of the stage, as the
stage sections below say.

The `allowed-tools` list above pre-approves read commands only. Export, snapshot,
state-file, and probe commands (such as the export script, `rm -rf` and `mkdir` in the run
directory, `stat`, `find`, `sha256sum`, `jq`, `awk`, `mv -f`, `wc -c`, `codex --version`,
and the `sh` runs of the five scripts in `${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/`:
`readonly.sh`, `handoff.sh`, `work-items.sh`, `working-tree.sh`, and `live.sh`) follow the
session's permission mode; tell the user once, before stage 1, that they may prompt. `git
fetch` (with its `git ls-remote --tags` check), every act write, and live-data access are
not pre-approved, and you also ask for them in words first.

`${CLAUDE_PLUGIN_DATA}` below is cca's data directory, and `${CLAUDE_PLUGIN_ROOT}` is
the plugin's own directory, where the stage files and templates live. Use each path
exactly as it appears in this file; neither is a shell variable. Read stage files and
templates with the Read tool, never through Bash. Stage files name both literally;
there each means the directory substituted here. In every Bash command, including the
`mv` of `runs.json.tmp`, use the resolved absolute path, never the unexpanded text.

## Invocation block

The command hands you this block as the Skill tool args, already validated:

```
command: audit | resume | act
manifest: <path> | none
inputs:
- <token>
flags:
  effort: auto | low | medium | high
  no-codex: true | false
  codex-model: gpt-6.1-sol | <id>
  codex-timeout: default | <seconds>
  models: none | role=model,...
  questions: default | <file>
  claims: none | <file>[, <file>...]
  budget: none | <minutes>
  max-agents: 8 | <n>
  run-id: none | <id>
  items: none | <id>[, <id>...]
  per-item: true | false
  from: none | <stage>
  live: none | <file>
```

Keep this block verbatim; you re-read it after a compaction. `audit` goes to Stage 1.
`resume` goes to Resume. `act` goes to Stage 9.

## Preamble

### Hard rules

The eight hard rules are in `${CLAUDE_PLUGIN_ROOT}/skills/cca/common.md`, which stage 1 copies into the run
directory. Read them now and hold to them for the whole run. In the orchestrator they
mean, in addition:

1. You are the only component that talks to the user, calls Codex, runs `git fetch`,
   exports pinned trees, and writes `stages.json`, `runs.json`, the ledger files,
   `usage.md`, and `report.md`. Agents read the run directory and the audited trees
   and write only their own output file.
2. During audit and resume you write only inside the run directory and to
   `${CLAUDE_PLUGIN_DATA}/runs.json`. You never run `git checkout`, `git switch`,
   `git reset`, `git stash`, `git worktree`, `git archive`, `git checkout-index`, or any
   command that writes to an audited repo, and you run `git fetch` only after the
   approval in stage 1. The one other write is `working-tree.sh build` for a bundle with
   `head: working-tree` (stage 1 step 1c, resume step 3), which writes only git objects
   into the repo's object store, never the index, a ref, or a file.
3. You call Codex only through the Skill tool, `codex-lite:ask`, with
   `--model <full id>` and `--timeout <seconds>`, plus `--resume <thread id>` for the
   one allowed follow-up. You never run the `codex` CLI except `codex --version`.
4. You ask the user before any live-data access (hard rule 5), and record each answer
   in `stages.json` `approvals` with kind `live`. Live approvals also come from a file:
   a result in a `--live` file names the person who approved the access and when, and
   resume records that approval from the file (`live.md`, "Reconciling") without asking
   again. You never run a live query yourself.

### Compaction recovery

After a compaction, or whenever you cannot account for your state, stop and re-read,
before any other action: the invocation block, `audit-brief.md`, `common.md`, and
`stages.json` in the run directory, and the stage file for the current stage. In the
same session, a stage marked `running` waits for its agents' notifications and
relaunches nothing. Under `/cca:resume`, `running` counts as incomplete and is rerun.
Approvals recorded in `stages.json` are not asked again.

### Roles

| Role | Default | Fallback when the default fails |
|---|---|---|
| Orchestrator | you, in the main session | none, the run ends `blocked` |
| Digester (stage 2) | `cca:digester`, opus | retry once, then the same agent on fable, else the scope fails |
| Domain mapper (stage 3) | `cca:mapper`, opus | as for the digester |
| Auditor (stage 4, top-ups) | `cca:auditor`, opus | as for the digester |
| Adversary (stages 5 and 7) | `cca:adversary`, opus, fresh context | as for the digester |
| Second opinion (stage 6) | Codex, `--codex-model` (default `gpt-6.1-sol`), through `codex-lite:ask` | `cca:adversary` on fable, else opus, launched once per batch, each given its Codex request; also for the batches of ids that neither the Codex request nor its follow-up carried (a partial swap) |
| Merger (stage 7) | `cca:merger`, sonnet | you merge |

An agent **fails** when it returns an error, or when its output file lacks
`status: complete` as its last line, or when `_test` marks the completion failed.
Handle each failure by role:

| Role | First failure | Second failure | Third failure |
|---|---|---|---|
| digester, mapper, auditor, adversary | relaunch, same model | relaunch on fable, a swap | the scope fails |
| merger | you merge, a swap | stage 7 fails | none |
| second-opinion fallback (fable), each batch | relaunch on opus | stage 6 fails | none |

Codex transport retries (codex-lite status `failed` or missing) are separate and come
before the swap to the fallback; stage 6's file has them. A swap changes who fills a
role; it never removes a stage. Record every swap in the stage's `swaps` list in
`stages.json` with the role, the scope, from, to, and the reason, and name it in the
report. A stage fails when any of its scopes failed. A failed stage counts as
satisfied for every stage that waits on it, so the run goes on, but its coverage loss
is recorded and the run ends `partial`.

### Agent launch rules

1. Launch every agent with the Agent tool, `subagent_type` `cca:<role>` (for example
   `cca:auditor`), in the background. Never launch a fork, and never use a
   general-purpose agent for a role.
2. Pass the `model` parameter on every launch: the value for the role from `--models`,
   else from the manifest's `models` key, else the role's default in the Roles table,
   or the fallback model on a swap. The Agent tool's `model` parameter overrides the
   agent definition's model. Record it in `stages.json` as the requested model; you do
   not learn the effective model, so the report says "requested", never "used".
3. Keep the prompt short: the absolute paths of `audit-brief.md`, `common.md`, the
   scope file or scope list, and the output file, plus the scope's questions and any
   stage-specific item the stage file names. The agent definition holds the standing
   instructions; do not restate them.
4. Each agent returns only its path and one line. Read the file to judge it; the last
   line must be `status: complete`.
5. On each completion notification, record in the stage's `agents` list: `type`,
   `model` (requested), `scope`, `started`, `ended`, `tokens` from the notification's
   `subagent_tokens` field (or `null` when absent), `tokens_scope`
   `"task notification, subagent_tokens; scope not documented"`, `duration_ms` from the
   notification, and `result` (`complete` or `failed: <reason>`).

### Stage order and control flow

```
orient -+-> digest ------+
        +-> domain map --+-> barrier (per group) -> pass two (per group) -+
        +-> pass one ----+                                                |
                                                                          v
             report <-- converge <-- late adversary <-- second opinion <--+
```

1. Stage 1 runs alone.
2. Stages 2, 3, and 4 start together.
3. Each group's reconciliation barrier clears when stages 2 and 3 are each complete,
   failed, or not applicable, and that group's top-ups (if any) are complete. Pass two
   starts per group once its barrier clears; early groups do not wait for late ones.
4. Map-correction top-ups run in stage 5 and finish before stage 6 starts.
5. Stage 6 starts when every group has finished pass two.
6. Stage 7 runs the late adversary (medium and high, and low when `live/` lists ids) and
   the merger.
7. Stage 8 always runs, even after a failed stage or an expired budget.

### Stage applicability

A stage is **not applicable** when its input does not exist: stage 2 without a
document corpus among the sources of truth, stage 3 without a code base among them.
Stage 1 classifies each source of truth that has a `path`; the audited repos' own docs
and ticket text are read by auditors directly and never make stage 2 or 3 applicable.
Write a not-applicable stage's entry with status `not_applicable` and no outputs; it
counts as satisfied for every stage that waits on it and is listed in the report's
Coverage. A stage **fails** when it is applicable and neither the default nor the
fallback produced a complete output for every scope.

### Terminal states

- `reported`: every applicable stage complete, and a report written.
- `partial`: a report was written, but a stage failed or the budget ran out. The
  verdict is `audit incomplete`, never `ready to merge`. Print the resume command
  `/cca:resume <run-id>`.
- `blocked`: no report could be written, or the read-only check failed. Print the
  reason; keep every finished stage file.

At the end, update the run's `state` in `runs.json`, then print the report path (when
there is one), the verdict, and the terminal state.

### Queue

Keep one queue of agent jobs across all stages and never have more than `max-agents`
agents running (default 8). Launch order when several stages have work: pass one
first, then digests, then maps; after that, jobs in the order their stage became
ready. A relaunch after a failure goes to the front of the queue. Each completion
notification drives the next launch. Work beyond the cap waits; scope is never merged
or dropped to fit the cap.

### Soft budget

`budget` applies only when given, and only to the invocation that gave it:
`/cca:resume` runs with no budget. Record the start time of stage 1. At every
completion notification and every stage boundary, compare elapsed wall-clock time with
the budget. `budget: 0` expires as soon as stage 1 completes. Once expired:

1. Launch nothing more from stages 2 to 7, including relaunches and top-ups.
2. Wait for running agents and record their results.
3. Write each stage's entry: `complete` if every scope finished, else `failed` with the
   reason "budget expired"; a stage that never started gets an entry with status
   `failed` and reason "not run: budget expired", so `stages.json` describes the whole
   run, and is listed in Coverage the same way. `/cca:resume` reruns it because its
   status is not `complete`.
4. Go to stage 8, which writes the report from what is on disk. The run ends `partial`.

At every stage boundary print one line: the stage, elapsed time, and agents run so far.

### Read-only check

Stage 1 takes the baseline (see `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/1-orient.md`, step 1b)
with `readonly.sh snapshot`, one prefix per audited repo `<name>`: `baseline/<name>.marker`,
`.status`, `.refs`, `.stash`, `.config`, `.hashes`, and `.ignored`. The scripts are
in `${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/`; run each as
`sh <resolved absolute script path> ...`. After every stage, including stages 1 and 8,
and before writing that stage's final entry:

1. For each audited repo `<name>`, run
   `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/readonly.sh check <repo> <run dir> <run dir>/baseline/<name> <ignored base prefix> <run dir>/baseline/<stage>/<name>`
   (create `baseline/<stage>/` first). The ignored base prefix is
   `<run dir>/baseline/<name>` until a check passes after the baseline was last taken
   (stage 1 step 1b, or resume step 8), then the out prefix of the last check that
   passed since then. Resume moves older `baseline/<stage>/` directories away, so an
   earlier prefix is never used. The script takes a fresh snapshot into the out prefix and prints
   one line per difference: `blocked <status|stash|config|hashes|refs> <-|+> <line>`,
   `remote-ref <-|+> <line>`, `ignored <added|deleted|changed> <path>`, and
   `touched <path>`. When `stat` gives whole seconds only, the first line is
   `note mtime precision: seconds`; it is not a difference and changes no exit status.
   It compares everything but the ignored files with the stage 1 baseline, which never
   moves.
2. Read the exit status, the first that holds:
   - `2`: a step of the check failed, so the boundary could not be checked. End the run
     `blocked` at once and show the script's message.
   - `1`: a `blocked` line was printed: a difference in tracked files, untracked
     non-ignored files, refs, index, stash, or config. End the run `blocked` at once
     and show the lines.
   - `3`: only `remote-ref` or `ignored` lines were printed. Judge each below.
   - `0`: nothing needs judgment. `touched` lines may have been printed.
3. For each `remote-ref` line (exit 3): it passes only when an approved fetch recorded in
   `approvals` after the baseline explains it. Otherwise end the run `blocked` at once
   and show it.
4. For each `ignored` line (exit 3), added, deleted, or changed:
   - If any agent with Bash (digester, mapper, auditor, adversary, or the stage 6
     fallback), in any stage, is running or has ended since the previous check (from
     the `agents` lists in `stages.json`), accept it provisionally, as pending.
   - Otherwise end the run `blocked` at once and show it.
5. Reconcile, after every check that did not exit 1 or 2, including exit 0, so a pending
   write never escapes attribution. Take every pending difference, from this check or
   an earlier one. Once every agent a pending difference was accepted under has ended,
   read those agents' `runs:` headings. A difference is accounted for when a logged run's
   directory is inside that repo. Any pending difference no logged run accounts for
   ends the run `blocked` now. Differences still waiting on running agents stay
   pending.
6. Write `baseline/<stage>-check.md`: the stage, the time, the repos checked, the
   result (`pass` or `blocked: <reason>`), the ignored-file differences accepted (each
   with the agent and run that accounts for it, or `pending` with the agents it waits
   on), or `none`, the `touched` lines as "touched, content unchanged", and the
   `note mtime precision: seconds` line when the check printed it (the report's
   Coverage repeats it from there). On pass, the out prefix of this check becomes the
   ignored base for the next check, until the baseline is taken again.

With `_test` absent, a user's own edit to an audited repo during a run trips this check
too; the report says so.

### Fault injection (`_test`)

When the manifest has a `_test` key, record it in `audit-brief.md` and in the report's
Coverage, and apply each field it has:

- `fail`: a list of `{ role, scope, times }`. `role` is digester, mapper, auditor,
  adversary, merger, or fallback (the stage 6 fallback agent); `scope` is a group,
  source, chunk id, or fallback batch (`second-opinion-<k>`), or `any`. The scope
  `second-opinion` also matches every batch scope `second-opinion-<k>`, as a prefix.
  Treat the first `times` completions of that role at that scope as failures, counting
  across relaunches and swaps, then apply the failure table. A merger failure injected
  this way still goes to the orchestrator merge.
- `drop_ack`: `{ input, times }`. In stage 6, treat the acknowledgment of the named
  run-directory input as missing in the first `times` answers.
- `hold`: `{ stage, until }`. Queue the named stage's agents but launch none until
  every initial agent of stage `until` has ended (for stage 4, the pass-one agents,
  before any barrier top-up).
- `expire_budget_after_stage`: treat the budget as expired the moment that stage's
  entry is written, whether or not `budget` was given.
- `plant_map_error`: a source name. When that source's mapper completes, before you
  accept its file, change one quoted answer's conclusion in `domain/<source>-map.md`
  to its opposite, keeping the quote, and record the line in the stage 3 entry as
  `test_planted`.
- `ledger_split_bytes`: replaces both 450,000-byte thresholds in stage 7, the
  split-mode choice (step 5) and the per-group slice part split (step 7.2).
- `inline_cap_bytes`: replaces the 450,000-byte cap on the stage 6 follow-up, the only
  request that carries inline text.

### State files

Write `stages.json` and `runs.json` only through a temporary file beside the
destination (`stages.json.tmp`, `runs.json.tmp`), then rename it over the destination
with `mv -f`. Never edit either in place.

`${CLAUDE_PLUGIN_DATA}/runs.json` is a JSON array with one entry per run:

```json
[ { "run_id": "2026-09-30-1412-travelly-limits", "path": "/abs/path/to/run",
    "primary_repo": "/abs/path/to/app", "created": "2026-09-30T14:12:00Z",
    "state": "running" } ]
```

`state` is `running` until the run ends, then `reported`, `partial`, or `blocked`.

`stages.json` in the run directory:

```json
{
  "plugin_version": "0.2.0",
  "approvals": [ { "kind": "fetch", "target": "<repo name>:<remote>",
                   "decision": "approved", "time": "2026-09-30T14:15:00Z",
                   "commands": ["git -C <repo> fetch --no-tags --refmap= ..."] } ],
  "stages": {
    "4": {
      "status": "complete",
      "inputs": { "audit-brief.md": "<hash>", "groups.md": "<hash>",
                  "claims.md": "<hash>", "common.md": "<hash>" },
      "outputs": ["pass1/g1.md", "pass1/tests.md"],
      "agents": [ { "type": "cca:auditor", "model": "opus", "scope": "g1",
                    "started": "...", "ended": "...", "tokens": 81234,
                    "tokens_scope": "task notification, subagent_tokens; scope not documented",
                    "duration_ms": 412000, "result": "complete" } ],
      "swaps": [],
      "superseded": []
    }
  }
}
```

1. Hashes are `git hash-object --no-filters <file>`. Source and bundle inputs are
   recorded as shas. `inputs` also records the plugin version (`plugin_version`), and
   for stage 1 the hashes of the manifest, claims files, and questions file.
2. Status is one of `running`, `complete`, `failed`, `not_applicable`, or
   `superseded`.
3. `approvals` records each approval as `kind` (`fetch`, `live`, or
   `export-over-1gb`), `target`, `decision`, and `time`; a `live` approval imported from
   a `--live` file also records `by` (the approver) and `source`
   (`live/results-<k>.md:<line>`); a `fetch` approval also
   records `commands`, the exact commands run under that approval (the fetches and any
   `git ls-remote --tags` check) and `resolved`, a map from each bare name that the
   approval covered to the kind it resolved to, `tag` or `branch`. It covers only those
   commands, except that an approval for a bare name covers the `ls-remote` check and
   either candidate refspec for it: planned commands that differ are asked again and
   recorded as a new entry.
4. When a stage starts, write its entry as `running` with its inputs. When every
   output it lists exists and its read-only check has passed, write the entry with
   its final status. That write is the last act of the stage; `stages.json` is the only
   record of completion.
5. Stage-specific keys: stage 1 `inputs` also records `forge_hashes` (the hashed `gh`
   files under `forge/`: `pr.hash.json`, a `jq` projection of the unprojected
   `pr.json` that leaves out the head and base shas and viewer-dependent fields,
   `pr-threads.json`, and `<ticket>.json`, by run-relative path, each with its hash,
   compared by resume; `pr.json` itself is not hashed), the `headRefOid` of each
   GitHub PR bundle, which is its pinned head, and its `baseRefOid`, information only
   (the base as GitHub last evaluated it, never pinned or compared: the pinned base is
   the sha of the local remote-tracking ref `<remote>/<baseRefName>`); stages 2 and 3
   record `output_hashes` (each digest or map path and its hash, read by the stage 4
   barrier) and `failed_scopes`; stage 2 also records `split_files` (each text file
   split into byte-range chunks); stage 3 records `test_planted` when `_test` planted
   a map error; stage 6 records
   `codex_model` and `codex_timeout`, the values passed, `sentinels`,
   `missing_positions` (the mandatory finding ids the Codex request or follow-up asked
   for and left without a position, plus the ids of any fallback batch that failed
   after the ladder), `batched` (true when more than one batch of mandatory ids
   was requested, else false); stage 7 lists the `ledger/slices/` files
   among its outputs in split mode, marks a part `over threshold` when a single
   finding id alone exceeds the split threshold, and records `converged_check` (`pass`
   or `fail`, absent when no merge was attempted), which stage 8 reads. Stages 6, 7, and
   8 record the live files they read (`live/findings.md`, `live/claims.md`, and each
   `live/carried/<id>.md` that `live/findings.md` names) as inputs, each by hash, or
   `absent` when it does not exist (`live.md`).

### Usage

Write `usage.md` at each stage boundary from `stages.json`: per stage, each agent's
type, scope, requested model, wall-clock (from `duration_ms`, or started and ended),
and tokens labeled "task notification, subagent_tokens; scope not documented". A
number the notification did not carry, and every Codex call through codex-lite, says
"not reported". Any sum is labeled "sum of reported numbers, not exact"; no total is
presented as exact.

## Stage 1: orient

Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/1-orient.md` and follow it. It normalizes the manifest, takes
the read-only baseline, pins every repo, writes diffs, exports trees, splits claims,
builds groups, selects the tier, and creates the run directory, `stages.json`, and the
`runs.json` entry. It ends with the stage 1 read-only check. Then start stages 2, 3,
and 4 together.

## Stage 2: digest

Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/2-digest.md` when stage 1 completes. It decides
applicability, chunks each document corpus, and launches the digesters.

## Stage 3: domain map

Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/3-domain.md` when stage 1 completes. It decides
applicability, writes the per-ticket question lists, and launches the mappers.

## Stage 4: pass one

Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/4-pass-one.md` when stage 1 completes. It launches the
auditors and specialists and runs the reconciliation barrier and its top-ups.

## Stage 5: pass two

Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/5-pass-two.md` when the first group clears its barrier. It
launches one adversary per pass-one report, applies map corrections and their top-ups,
and writes `ledger/5.md`.

## Stage 6: second opinion

Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/6-second-opinion.md` when stage 5 is complete or failed. It
builds the Codex request from `${CLAUDE_PLUGIN_ROOT}/skills/cca/codex-request.md`, calls
`codex-lite:ask`, handles status and swaps, and writes `ledger/6.md`. The request names
every input copy and audited source by absolute path, so Codex opens them wherever the
run directory is; only the follow-up carries inline text. Every mandatory
finding id is requested in a run where stage 6 completes: in batches of at most 60,
the first in the Codex request, at most 60 positions in the one Codex follow-up
(missing first-batch ids first, then second-batch ids), and every id neither carries
in fallback batches of at most 60, one launch each, a partial swap; without Codex, one
fallback launch per batch. A fallback batch fails the stage only when it fails after
the ladder.

## Stage 7: converge

Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/7-converge.md` when stage 6 is complete or failed. It runs the
late adversary, applies the review gate, runs the merger, and checks the merge
against the ledger.

## Stage 8: report

Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/8-report.md` when stage 7 is complete or failed, when the
budget has expired and no agent is running, or when any stage from 2 to 7 has failed
and nothing more can run. It fills `${CLAUDE_PLUGIN_ROOT}/skills/cca/report.md` from what is on disk, applies
the verdict rules, writes the revision line, and ends the run. Its outputs are
`report.md`, `claims-verdicts.md`, and `work-items.jsonl`.

## Stage 9: act

For `command: act`, read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/9-act.md` and follow it. Act is not bound
by the audit's read-only boundary but is gated by the user's approval per item.

## Resume

For `command: resume`, read `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/resume.md` and follow it. It finds the
run, decides the first stage to rerun, marks superseded outputs, and continues at that
stage's section above. With `live: <file>`, it first imports the file's live check
results and reconciles them with `${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/live.sh`,
whose format and modes are in `${CLAUDE_PLUGIN_ROOT}/skills/cca/live.md`; a finding
result reruns stages 6 to 8 and a claim-only result stages 7 and 8.
