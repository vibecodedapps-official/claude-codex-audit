# Decisions

This file records the design decisions behind cca 0.1.0: the questions the design
settled, the five platform decisions confirmed against Claude Code before the build, the
choices made while building, what is still open, and what is deferred past 0.1. It
replaces the pre-implementation spec, architecture, and build plan documents, in the
repository history before this change; their user-facing content is in `README.md`.

## Resolved questions (2026-09-30)

Settled during the design and its review rounds.

1. **Role agents.** Plugin agent definitions under `agents/`, with tool lists that
   exclude Edit and NotebookEdit, plus the read-only check at the end of every stage,
   because tool lists alone do not constrain Bash.
2. **Worktrees.** Not used. An exact export of the pinned tree into the run directory,
   with symlinks as placeholder files, gives agents a pinned tree without writing any
   repo metadata, so the read-only boundary needs no worktree exception.
3. **Azure DevOps.** Deferred. Exported ticket and thread files cover it in 0.1 (see
   "Exported forge files" in `README.md`).
4. **Run location.** The primary repo is the session's repo if it is a bundle, else the
   first bundle. The absolute run path is stored in `runs.json`.

## Platform decisions confirmed before the build (2026-09-30)

Probed on Claude Code 2.1.284, from the Claude Code documentation and from what a
session on that version showed. Each entry says which part is documented and which is
only observed.

1. **Agent type name.** Documented: a plugin agent's type for the Agent tool is
   `<plugin>:<agent>`, and agents are read from `agents/` at the plugin root. So the
   types are `cca:digester`, `cca:mapper`, `cca:auditor`, `cca:adversary`, and
   `cca:merger`.
2. **Model override.** Documented: the Agent tool's `model` parameter takes precedence
   over an agent's frontmatter `model` since Claude Code 2.1.251. Frontmatter accepts
   `sonnet`, `opus`, `haiku`, `fable`, a full model id, or `inherit`. cca records the
   model it requested; it does not collect the model actually used, so the report says
   "requested".
3. **Tokens and duration.** Documented: background agent completion notifications
   carry no token or duration fields. Observed: the task notification in a 2.1.284
   session carried `subagent_tokens`, `tool_uses`, and `duration_ms`. The scope of
   `subagent_tokens` is not documented. `usage.md` therefore labels every token number
   "task notification, subagent_tokens; scope not documented", and no total is
   presented as exact.
4. **Plugin data and root paths.** Documented: `${CLAUDE_PLUGIN_DATA}` resolves to the
   plugin's data directory under `~/.claude/plugins/data/`, and it and
   `${CLAUDE_PLUGIN_ROOT}` are substituted in skill, command, and agent content. They
   are not exported into the Bash tool's environment. The skill text carries them
   literally so they are substituted at load. Observed: codex-lite writes its request
   and thread files into its own data directory, and no permission prompt appeared for
   that in the probing session, which ran in auto mode.
5. **Fan-out.** The Agent tool, not the Workflow tool. This is a design choice, not a
   platform fact: the queue mixes stages and reacts to each completion, and the
   orchestrator must stay able to ask the user mid-run. Workflow agents cannot be
   continued or interleaved with user questions.

## Implementation decisions (2026-09-30)

Choices made while building 0.1.0 where the design left room.

- **Scope of the release.** 0.1.0 implements the whole design, milestones M0 to M7, as
  files. Tagging and publishing the release are separate steps that need approval.
- **Unapplied map corrections.** A map correction that a top-up raises is not reissued
  (one round). It is recorded under "Map corrections not applied" in `ledger/5.md` and
  in the stage 5 entry of `stages.json`, not appended to `audit-brief.md`. The brief is
  a stage 1 output whose hash every later stage records, so editing it would make resume
  rerun every stage.
- **Finding ids and origin tags.** Pass one findings are `<group>-F<n>`. A pass-two
  addition is `<group>-P<n>` with `origin: pass2`; a map-correction top-up finding is
  `<group>-T<n>` with `origin: topup`; a second-opinion addition is `X<n>` with
  `origin: codex`; a late adversary finding is `L<n>` with `origin: late`. Converged
  items are `C<n>`.
- **Contested items in the verdict.** A contested item whose counted severity is
  `blocker` or `high` gives `not ready`, as an agreed one does. The counted severity
  follows the contested rules (the higher severity only when that position is a
  `verified fact`).
- **`--models` values.** Only the Agent tool's short model names are accepted: `opus`,
  `sonnet`, `haiku`, `fable`. Any other value is rejected in one line.
- **Empty inputs.** A command with no prompt inputs states `inputs: none` in the
  invocation block it hands to the skill.
- **Paths between skill files.** The skill and its stage files and templates refer to
  each other through `${CLAUDE_PLUGIN_ROOT}`, and the orchestrator reads them with the
  Read tool, not through Bash.
- **Group derivation (2026-10-01).** A changed file touched by a commit whose message
  references a ticket belongs to that ticket's group, and to each such group when
  several tickets' commits touch it, so a file three tickets touch reaches
  `cross-cutting`. The pre-implementation text counted only files the ticket, PR, or
  commit texts name, and files touched by one ticket's commits alone.
- **Planning documents.** The pre-implementation spec, architecture, and build plan
  documents were removed from source control once implemented. Their user-facing
  content moved to `README.md`, and their decisions, open items, and deferred list to
  this file. Acceptance results are in `docs/acceptance.md`.

## Open items

- **`gh api` pre-approval.** Whether `gh api` GET calls can be pre-approved narrowly
  enough in `allowed-tools` is not settled. They are left out of `allowed-tools`, so the
  session prompts for them at run time.
- **Path substitution in stage files.** Whether `${CLAUDE_PLUGIN_ROOT}` is substituted
  inside stage files that the orchestrator reads later with the Read tool is not
  confirmed. `SKILL.md` tells the orchestrator to resolve such a reference to the same
  directory it learned when the skill loaded.
- **Data directory depends on how the plugin is loaded.** Observed 2026-10-01: with
  `--plugin-dir`, the plugin data directory id was `cca-inline`, so `runs.json` lives
  under `~/.claude/plugins/data/cca-inline/` in a plugin-dir session and under the
  marketplace install's id in an installed one. A run started one way is not found by
  `/cca:resume` or `/cca:act` started the other way.
- **Status of stages the budget skips (2026-10-01).** In the budget-0 acceptance run the
  orchestrator improvised a free-text status for stages 4 to 7, outside the skill's
  status set, so the skill now records a never-started stage as `failed` with the reason
  "not run: budget expired"; whether later runs follow it is not yet observed.
- **Inline Codex requests (known limitation, 2026-10-01).** The inline request form
  travels as the Skill tool argument, and codex-lite rewrites it into its request file,
  so a request near the 450,000-byte cap is slow and may be altered in transit. A
  request over the cap is first reduced by dropping the diffs (Codex can regenerate
  them from the shas in the brief) and re-measured before the swap to the fallback.
  Stage 6 also checks that the answer gives a position for every mandatory finding id
  (every blocker or high finding and every pass-two downgrade or drop). Keeping the run
  directory inside the session's repository avoids the inline form.

## Round 4 review fixes (2026-09-30)

- B1: fetches are explicit and tag-free into remote-tracking refs only, with no
  `--prune`; the pinned shas are verified after the fetch and the commands are recorded
  in the approval, which covers only those commands (different planned commands are
  asked again); the fetch also covers tags (to `refs/remotes/<remote>/tags/<name>`) and
  shas (to `refs/remotes/<remote>/cca/<sha>`) from each repo's selected remote, and a
  `<other remote>/<branch>` ref from that configured remote. Every ref mapping is
  recorded in the brief for resume.
- B2: a bundle's base is pinned by the PR's `baseRefOid`, and a stale base is handled
  like a stale head; resume stops only for a changed head or a changed merge base, and
  a moved base sha with the same merge base is recorded as `base moved` while the
  recorded base sha is kept for every diff.
- B3: each `gh` call is made once and saved by shell redirect, never through the model;
  the PR output is saved unprojected as `pr.json`, and `pr.hash.json`, a `jq` projection
  without the shas and viewer-dependent fields (which would otherwise invalidate stage 1
  under another login), is what `forge_hashes` hashes. Resume re-queries once into
  `pr.json.new`, projects it the same way, and hashes by `git hash-object --stdin`; a
  `gh` or `jq` failure stops resume. `jq` is required for GitHub PRs.
- Run directory: it is created before the PR is read (the run id comes from the
  manifest, with no `gh` call), so `pr.json` can be written by redirect; a stop in that
  section removes it.
- B4: resume reads `manifest.json` and `stages.json` first and reruns from stage 1 when
  stage 1 is missing, running, or has no brief, or when `stages.json` is missing; only
  a missing `manifest.json` is unrecoverable.
- B5: stage 6 requires a position for every mandatory id, and every mandatory id is
  requested in a run that completes. Above 60 ids the asks are batched: Codex gets the
  first batch in the request and the second in its one follow-up (a third batch cannot
  be requested, so stage 6 fails with `missing_positions` and the run ends `partial`);
  the fallback is launched once per batch, and a batch that fails after the ladder fails
  the stage.
- C1: a text file over 450,000 bytes is split into byte-range chunks, listed in
  `split_files` and in the report's Coverage. The orchestrator materializes it once
  under the run's `tmp/` (run state, never an input or output) to compute the ranges,
  and a digester reads its range in 24,000-byte slices (a Bash result is cut near
  30,000 characters), ending `status: failed at byte <offset>` when it did not reach the
  end.
- C2: split-mode group mergers read a per-group slice under `ledger/slices/`, not the
  whole ledger files; a ledger file or section a merger opens is recorded under `opened:`.
- C3: an over-cap Codex request is reduced by dropping diffs before the swap, recorded
  as `inline_reduced`.

## Deferred past 0.1

- Native Azure DevOps and other forge fetching. 0.1 accepts exported files.
- Automatic trigger from ccl. In 0.1 a ccl run's report is passed as a claims file.
- Exact token accounting.
- A PreToolUse hook that enforces the read-only boundary mechanically.
- Feeding a live check result back into a run. In 0.1 the user reruns the audit or acts
  on the finding by hand.
