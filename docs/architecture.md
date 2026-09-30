# Architecture

How `cca` 0.1.0 is built from `SPEC.md`. Drafted 2026-09-30 and revised the same day
after three review rounds with the spec and build plan. The spec says what the
plugin does; this file says which Claude Code parts do it, what each file holds, and
how state moves between stages. Where the two disagree, the spec wins and this file is
fixed.

The plugin is prompt files only: commands, one orchestrator skill, five agent
definitions, and templates. It ships no runtime code. Two development scripts, a lint check and a fixture
builder, live under `tests/` and are never loaded by the plugin.

## Shape

```
/cca:audit ─┐
/cca:resume ├─> commands/*.md  (parse, validate, state invocation)
/cca:act ───┘          │
                       v
              skills/cca/SKILL.md  (orchestrator, main session)
                       │  reads skills/cca/stages/<n>-*.md at each stage
                       │
     ┌─────────────────┼─────────────────────────┬───────────────┐
     v                 v                         v               v
 Agent tool       Agent tool                Skill tool       git / gh (Bash)
 cca:digester     cca:auditor               codex-lite:ask
 cca:mapper       cca:adversary
                  cca:merger
     │                 │                         │
     └────────> run directory (all state on disk) <─────────────┘
```

The orchestrator is the only component that talks to the user, calls Codex, runs
`git fetch`, exports pinned trees, and writes `stages.json`, `ledger.md`, and
`report.md`. Agents read the run directory and the audited trees and write only their
own output file.

## Components

### Commands

`commands/audit.md`, `commands/resume.md`, and `commands/act.md` follow `ccl`'s
thin-forwarder pattern:

1. Parse `$ARGUMENTS` into inputs and flags. Reject unknown flags, missing values, and
   bad values with one line and no further action.
2. Validate cheaply: manifest file exists and parses, repo paths are git checkouts
   (`git -C <path> rev-parse --git-dir`), a run id exists in `runs.json` for resume
   and act.
3. State the parsed invocation as a fenced block.
4. Invoke the Skill tool with `cca:cca` and that block as args.

Commands write no file. Each command's `allowed-tools` lists only read commands.

### Orchestrator skill

`skills/cca/SKILL.md` is marked `user-invocable: false`. It holds the preamble (hard
rules, roles, stage order, terminal states, failure rules) and a short section per
stage that says which stage file to read. The long per-stage instructions live in
`skills/cca/stages/`, read at the start of each stage, so the skill's first load stays
small:

```
skills/cca/SKILL.md
skills/cca/stages/1-orient.md
skills/cca/stages/2-digest.md
skills/cca/stages/3-domain.md
skills/cca/stages/4-pass-one.md
skills/cca/stages/5-pass-two.md
skills/cca/stages/6-second-opinion.md
skills/cca/stages/7-converge.md
skills/cca/stages/8-report.md
skills/cca/stages/9-act.md
skills/cca/stages/resume.md
skills/cca/common.md        template, copied into the run as common.md
skills/cca/report.md        report template
skills/cca/codex-request.md Codex request template
```

### Agent definitions

Plugin agents under `agents/`, launched with the Agent tool as `cca:<name>`, in the
background, never as forks. Each prompt is short: the paths of `audit-brief.md`,
`common.md`, the scope file, and the output file, plus the scope's questions. The
definition's body holds the role's standing instructions.

| Agent | Model | Tools | Writes |
|---|---|---|---|
| `digester` | opus | Read, Grep, Glob, Bash, Write | `guidelines/digest-N.md` |
| `mapper` | opus | Read, Grep, Glob, Bash, Write | `domain/<source>-map.md` |
| `auditor` | opus | Read, Grep, Glob, Bash, Write | `pass1/<group>.md` |
| `adversary` | opus | Read, Grep, Glob, Bash, Write | `pass2/<group>.md`, late and fallback outputs |
| `merger` | sonnet | Read, Write | `converged.md` |

The files are `agents/digester.md` and so on, and the plugin namespace supplies the
prefix, so the Agent tool type is `cca:digester`. M0 confirms the exact form.

The model in each definition is the default. `--models` and the manifest override it
through the Agent tool's `model` parameter. Bash is given only where a role may need
`git show`, `git grep`, or a read-only check run; the body lists the allowed commands.

Every agent ends by writing its file with a last line `status: complete`, then returns
the path and one line. The orchestrator treats a returned agent without that line in
its file as failed.

## Run directory and state

Layout is in the spec. Three files carry state.

### `runs.json`

In the plugin data directory (`${CLAUDE_PLUGIN_DATA}`). One entry per run:

```json
{ "run_id": "2026-09-30-1412-travelly-limits", "path": "/abs/path/to/run",
  "primary_repo": "/abs/path/to/app", "created": "2026-09-30T14:12:00Z",
  "state": "reported" }
```

### `stages.json`

In the run directory. Written only by the orchestrator, entry by entry, and each entry
last within its stage:

```json
{
  "plugin_version": "0.1.0",
  "stages": {
    "4": {
      "status": "complete",
      "inputs": { "audit-brief.md": "<hash>", "groups.md": "<hash>",
                  "claims.md": "<hash>", "common.md": "<hash>" },
      "outputs": ["pass1/g1.md", "pass1/tests.md"],
      "agents": [ { "type": "cca:auditor", "model": "opus", "scope": "g1",
                    "started": "...", "ended": "...", "tokens": 81234,
                    "tokens_scope": "final request only", "result": "complete" } ],
      "swaps": [],
      "superseded": []
    }
  }
}
```

Hashes are `git hash-object --no-filters <file>`, which needs no other tool. Source and
bundle inputs are recorded as shas. A stage's status is one of `running`, `complete`,
`failed`, `not_applicable`, or `superseded`.

### `ledger.md`

Written by the orchestrator after stage 5 and appended after stages 6 and 7. One
section per finding id, holding the original finding text, then each verdict in order
with its reviewer and evidence, then its current gate and disposition. The merger
reads it and never edits it.

## Control flow

```
orient ─┬─> digest ────┐
        ├─> domain map ─┼─> barrier (per group) ─> pass two (per group) ─┐
        └─> pass one ───┘                                                 │
                                                                          v
             report <── converge <── late adversary <── second opinion <──┘
```

Stages 2, 3, and 4 launch together. Pass two starts per group once that group clears
the barrier, so early groups do not wait for late ones. Stage 6 starts when every group
has finished pass two. The late adversary and merger run in stage 7.

**Queue.** The orchestrator keeps one queue of agent jobs across stages and never has
more than `--max-agents` running. Launch order is pass one first, then digests, then
maps, so auditors start at once as the spec asks. Completion notifications drive the
next launch.

**Failure.** An agent fails when it returns an error or leaves its file without
`status: complete`. Handling is per role, following the spec's Roles table:

| Role | First failure | Second failure | Third failure |
|---|---|---|---|
| digester, mapper, auditor, adversary | relaunch, same model | relaunch on Fable, a swap | scope failed |
| merger | the orchestrator merges, a swap | stage failed | none |
| second-opinion fallback (Fable, after Codex is swapped out) | relaunch on Opus | stage 6 failed | none |

Codex transport retries (codex-lite `failed` or missing status) are separate and
happen before the swap to the fallback. The stage fails if any scope failed. A failed
stage counts as satisfied for waiting stages and makes the run `partial`.

**Fault injection.** When the manifest has a `_test` key, the orchestrator treats the
named scope's first `n` completions as failures, drops a named Codex acknowledgment,
holds a named stage until another completes, or expires the budget when a named stage
completes, so each path can be checked without waiting for a real failure or for
time to pass. The key is recorded in the report.

**Budget.** The orchestrator checks elapsed time at every notification. Past the
budget, it launches nothing from stages 2 to 7, waits for running agents, and goes to
stage 8.

**Export.** For a repo not checked out at its pinned sha, the orchestrator lists the
tree with `git -C <repo> ls-tree -r -z --full-tree <sha>` and writes every entry under
`<run dir>/trees/<name>/` from `git -C <repo> cat-file --batch`: a regular blob as a
file, with the executable bit for mode `100755`; mode `120000` as a symlink whose
target is the blob's content; mode `160000` (a submodule) listed in the brief and not
exported. `cat-file` reads objects only, so no filter, smudge or process driver, or
attribute runs. Git LFS files are exported as their pointer files, and the brief says
so. `git archive` and `git checkout-index` are not used, for the reasons the spec gives.

**Read-only check.** Stage 1 writes `baseline/marker` and one snapshot file per
audited repo under `baseline/`. After each stage, the orchestrator reruns the snapshot
commands (including the content hashes of modified and untracked files and the
ignored-file inventory), diffs them against `baseline/`, and runs
`find <repo> -newer baseline/marker -type f -not -path '<repo>/.git/*'`, excluding the
run directory when it is inside that repo. A difference or any listed file ends the
run `blocked`. `git config --list --local` is used instead of reading a config file,
so the check works the same when a repo's `.git` is a file.

## Codex interface

One call, at most one follow-up, both through the Skill tool:

```
Skill codex-lite:ask
  --model gpt-6.1-sol --timeout 1200 Read cca/<run-id>/codex/request.md in <scratch> and answer as it asks.
```

When the run directory is not inside the session's repo, the request is built in
inline form: every input's full content under a header with its path and sentinel,
diffs included, so it names no file Codex must open. The same form is used for the
retry after a missing acknowledgment. The follow-up passes `--resume <thread id>` with the id from
the first answer's `thread` line, plus the same `--model` and `--timeout`.

The orchestrator parses codex-lite's last lines for `status:` and `thread`. Status
handling and the fallback are in the spec. The fallback is `cca:adversary` launched
with the same request file and an output path of `codex/response.md`, recorded as a
swap.

## Report and verdict

The orchestrator fills `skills/cca/report.md` from `converged.md`, the ledger, `claims`
lists from pass one, `stages.json`, and `usage.md`. The verdict rules are applied by
the orchestrator from counts it writes into the report first, so a reader can check
them.

## Act

`/cca:act` reads the report, checks the revision line against the approval, then works
repo by repo. It reuses `stages.json`'s bundle shas and `act/log.md` to tell its own
commits from drift. It never uses the exports under `trees/`; changes go to the
user's checkout on the bundle's branch.

## Permissions

The plugin runs under the session's permission mode. Command and skill `allowed-tools`
pre-approve only read commands: `git status`, `git diff`, `git log`, `git show`,
`git rev-parse`, `git merge-base`, `git for-each-ref`, `git stash list`,
`git check-ignore`, `git hash-object`, `git grep`, `git -C` forms of these, and
`gh pr view`, `gh issue view`, `gh api` GET calls. The export commands are pre-approved
because they write only into the run directory. `git fetch`, all act writes, and live-data access are not pre-approved and are also asked in words
first, per the spec. Whether a skill's `allowed-tools` apply inside subagents is not
assumed; agent definitions carry their own tool lists.

## Checks

The plugin's behavior comes from a model, so its checks are fixture runs, not unit
tests.

- `tests/fixture/build.sh <name>` builds one throwaway fixture (`solo`, `solo-dirty`,
  or `full`, described in the build plan) in a temp directory and prints its manifest
  path.
- `tests/fixture/expected.md` lists each fixture's expected outcomes as literals, and
  the traps that must not appear, such as a "deleted" finding from the base's later
  commit.
- `tests/lint.sh` checks the static parts: every command and agent file has the
  required frontmatter keys, no agent tool list includes Edit or NotebookEdit, and
  every stage file the skill names exists.

A milestone passes when every acceptance case the build plan names for it passes.
Failure paths are driven by the `_test` manifest key, not by timing.

## Decisions to confirm in M0

1. The Agent tool type name for a plugin agent (`cca:auditor` or another form).
2. That the Agent tool's `model` parameter overrides a plugin agent's `model`
   frontmatter.
3. That background agent completion notifications carry token and duration fields,
   and what scope the token field has.
4. That `${CLAUDE_PLUGIN_DATA}` is available to a skill for `runs.json`, and whether
   cca's calls to codex-lite write only in codex-lite's data directory, with or
   without a permission prompt.
5. Agent tool, not the Workflow tool, for fan-out: the queue must mix stages and react
   to each completion, and the orchestrator must stay able to ask the user mid-run.
