# Decisions

This file records the design decisions behind cca 0.1.0, 0.2.0, and 0.3.0: the questions
the design settled, the five platform decisions confirmed against Claude Code before the
build, the choices made while building 0.1.0, the 0.2.0 and 0.3.0 decisions, what is still
open, and what is deferred past 0.3. It replaces the pre-implementation spec,
architecture, and build plan documents, in the repository history before this change;
their user-facing content is in `README.md`.

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
- **Inline Codex requests (resolved 2026-10-01, in 0.2.0).** The first request no
  longer has an inline form, so the cap and the diff dropping left it. See "Absolute-path
  Codex requests" under the 0.2.0 decisions. The follow-up still carries an input Codex
  could not open inline, under the 450,000-byte cap.
  Stage 6 also checks that the answer gives a position for every mandatory finding id
  (every blocker or high finding and every pass-two downgrade or drop).

## Round 4 review fixes (2026-09-30)

- B1: fetches are explicit and tag-free into remote-tracking refs only, with no
  `--prune`; the pinned shas are verified after the fetch and the commands are recorded
  in the approval, which covers only those commands (different planned commands are
  asked again), except that an approval for a bare name covers the `ls-remote` check and
  either candidate refspec for it, with the resolved kind (`tag` or `branch`) recorded
  in the entry's `resolved` map so resume matches it without contacting the remote; the
  fetch also covers tags (to `refs/remotes/<remote>/tags/<name>`) and shas (to
  `refs/remotes/<remote>/cca/<sha>`) from each repo's selected remote, and a
  `<other remote>/<branch>` ref from that configured remote. Every ref mapping is
  recorded in the brief for resume. The remote of a GitHub PR bundle is the one whose
  URL names the PR's owner and repo (from `url` in `pr.json`), else `origin`, else the
  only remote, settled at section C; for other repos it is selected lazily, only when
  step 1a needs a fetch, and several remotes without `origin` stop the run only then. A
  PR bundle whose repo has no remote stops with `bundle <name>: no remote`.
- B2: a GitHub PR bundle's base is pinned to the local sha of `<remote>/<baseRefName>`
  after step 1a and its approved fetch, which refreshes the base branch for every
  GitHub PR bundle and every remote-tracking `base` ref. The
  PR's `baseRefOid` is GitHub's cached base at the last sync, not the live branch tip,
  so it is recorded in the brief as information only and never pinned or compared.
  Whenever any fetch for a bundle's repo is approved, the base branch is fetched with
  it, since a present remote-tracking ref may be behind. Every restricted fetch passes
  `--refmap=` so a configured refspec cannot write a local tag. Resume stops for a
  changed head or a changed base sha alike: the brief's base commit list and overlap
  set depend on the base tip, so an unchanged merge base does not make them current
  (a 2026-09-30 review reversed the earlier merge-base shortcut).
- B3: each `gh` call is made once and saved by shell redirect, never through the model;
  the PR output is saved unprojected as `pr.json`, and `pr.hash.json`, a `jq` projection
  without the shas and viewer-dependent fields (which would otherwise invalidate stage 1
  under another login), is what `forge_hashes` hashes. Resume re-queries once into
  `pr.json.new`, projects it the same way, and hashes by `git hash-object --stdin`; a
  `gh` or `jq` failure stops resume. `jq` is required for GitHub PRs.
- Run directory: it is created before the PR is read (the run id comes from the
  manifest, with no `gh` call; for a `file:` PR export the slug uses the export's `id`,
  else the bundle's `branch`, never the path), so `pr.json` can be written by redirect;
  a stop in that section removes it.
- B4: resume reads `manifest.json` and `stages.json` first and reruns from stage 1 when
  stage 1 is missing, running, or has no brief, or when `stages.json` is missing; only
  a missing `manifest.json` is unrecoverable. Resume never moves `manifest.json`, its
  walk list includes `tmp/`, and on the stage-1-rerun path stale `pr.json.new` files
  are removed first.
- B5: stage 6 requires a position for every mandatory id, and every mandatory id is
  requested in a run that completes. Above 60 ids the asks are batched: Codex gets the
  first batch in the request, and its one follow-up asks for at most 60 positions
  (missing first-batch ids first, then second-batch ids as far as 60 allows); every id
  neither carries goes to the fallback in batches of at most 60, one launch per batch
  (scope `second-opinion-<k>`), recorded as a partial swap (reason "mandatory ids
  beyond the Codex request and follow-up"). With no Codex the fallback is launched once
  per batch. A fallback batch fails stage 6 only when it fails after the ladder;
  `missing_positions` holds the ids Codex was asked for and left without a position
  after the follow-up and those of a failed fallback
  batch.
- C1: a text file over 450,000 bytes is split into byte-range chunks, listed in
  `split_files` and in the report's Coverage. The orchestrator measures an exported
  file in place and copies a directly read tree's file once under the run's `tmp/` (run
  state, never an input or output, removed on every exit of step 3) to compute the
  ranges, and a digester reads its range in slices of up to 24,000 bytes ending at the
  last LF (a Bash result is cut near 30,000 characters), numbering lines through one
  `awk` stage so every quoted line has an absolute number, ending `status: failed at
  byte <offset>` when it did not reach the end.
- C2: split-mode group mergers read a per-group slice under `ledger/slices/`, not the
  whole ledger files; a ledger file or section a merger opens is recorded under
  `opened:`. The slices are written by shell (`awk`, `grep`, `printf`, redirects), never
  through the model, with `<run dir>/tmp/block.md` as scratch.
- C3: an over-cap Codex request is reduced by dropping the diffs of bundles whose repo
  is the session repository (others are never dropped, since Codex cannot reach them)
  before the swap, recorded as `inline_reduced`; still over the cap, or with none
  droppable, it swaps with the reason "request too large for inline form". (Removed in
  0.2.0; see "Absolute-path Codex requests".)

## 0.2.0 decisions (2026-10-01)

0.2.0 closes five gaps that one real audit of 0.1.0 found (F1 to F5) and adds a typed
handoff from the build session to the audit with a return trip (H1 to H5). The plan was
reviewed twice by a second opinion before implementation; the settled findings are listed
below. Nothing was run against a live audit; the acceptance record keeps every
agent-driven case `not run` until one runs.

- **Manifest `scratch` key (F1).** A repo may keep its scratch directory under any
  ignored name. The key must name a path inside the primary repo that the repo ignores,
  or the run stops before stage 1. The run directory then lands in the repo, under the
  name the repo already uses for scratch. A resumed run keeps its
  recorded directory, since moving it would orphan the run's state.
- **Absolute-path Codex requests (2026-10-01).** A probe ran Codex in codex-lite's
  read-only sandbox on Windows with the elevated sandbox. It read a token file outside
  every repository by absolute path and quoted it exactly. So the request now names every
  input by absolute path, for any run directory, and the inline first request, its cap,
  the diff dropping, and `inline_reduced` are gone. Only an input Codex did not acknowledge
  with its sentinel goes inline, in the one follow-up, under the 450,000-byte cap; over
  it, stage 6 fails. No codex-lite change was needed, so the `--cwd` item (F6) is dropped
  from the deferred list. Limits: Linux and macOS rely on Codex's documented read-only
  policy, not a run here. The sentinel check catches a read that fails, so a platform
  where it fails is detected, not trusted. Audited sources were never sentinel-checked
  and stay named by read path and sha.
- **Release wording (F2).** The README says what ran and what has not, matching the
  acceptance record. The first medium-tier run on a real bundle is the acceptance run.
- **The read-only check is a script (F3).** The check is the step most likely to be
  skipped or botched on a long run, so `readonly.sh` takes a snapshot and compares it, and
  the orchestrator keeps only the judgment the script cannot make. Exit 2 (the check could
  not complete) ends the run `blocked`, since the boundary could not be checked.
- **Sub-second mtime replaces the second channel.** 0.1 caught a same-size rewrite within
  one second with a second "newer than the marker" channel. The inventory now records
  modification time at sub-second precision, so the channel is not needed, and a write
  made while a snapshot ran is not reported again once it is in an accepted inventory.
  Each audited repo has its own marker. The ignored base for the next check is the last
  check that passed. Pending ignored differences are reconciled after every check that
  did not exit 1 or 2, so a pending write never escapes attribution.
- **Quoted paths are unsupported.** A path git prints quoted (one holding a double quote,
  backslash, tab, newline, or control character) fails the check with exit 2 naming it,
  instead of risking a wrong comparison. Failing closed fits the boundary.
- **Sizing note (F4).** The README tells a user to size sources before a first run, since
  an export copies every tracked blob at the pinned sha, and agents run no test or lint
  command in an exported tree. `skills/cca/common.md` now states that as broadly as the
  auditor's boundary does.
- **Work-item operations plan (F5).** Stage 8 writes `work-items.jsonl`, one JSON object
  per operation, with `$new:<key>` placeholders, for a forge adapter or a person to apply.
  It is validated before the report is hashed and carries no report revision: a resume
  that rewrites the report supersedes the file with it. `/cca:act` applies none of it, so
  no write path to a forge is added.
- **The handoff command is an inline command, not a skill.** A skill named `handoff` would
  collide with the command name, so `commands/handoff.md` holds the whole procedure.
- **Typed claims (H2).** Five kinds, so each is checked the way its kind needs. A
  handoff's kinds come from `handoff.sh claims`, never from judgment, and one item is one
  claim, never split further. Prose files keep the sentence split with a kind per sentence,
  by an ordered rule (verification first).
- **Verification claims (departure from the feedback).** The feedback says a verification
  claim "counts as false unless the audit reproduces the check". 0.2.0 never marks an
  unreproduced verification claim `true`, but marks it `not verified` with the reason
  `not reproduced`, and lists it in `claims-verdicts.md` as a recheck request, not a
  correction. `false` stays reserved for counter-evidence. Reason: an audit that lacks
  access (a declined live check, an expired budget, an exported tree) would otherwise tell
  the build session to correct a statement that may be accurate, which is the memory
  damage the return trip exists to prevent. The acceptance case reads: a verification claim
  the fixture cannot reproduce is never reported `true`, and appears as a recheck request.
  The owner can reverse this.
- **A run under another setup is not counter-evidence.** A suite run without an
  environment variable it needs, or in another directory, can fail for that reason alone.
  Such a run leaves the claim `not verified, not reproduced`, because a `false` from it
  would rewrite an accurate statement, which the departure above exists to prevent.
- **Reproduction is not proof the check ran.** A reproduced result does not show that the
  build session ran its stated check, and the report says so once.
- **Decision classes (H3).** The class follows from three dimensions read from the record:
  resolution (taken, open deferral, settled later), authority (a person, a role, a
  checkpoint, not recorded), and evidence (alternatives weighed, or not). The classes are
  `stale deferral`, `needs <owner>`, `default taken`, and `evidenced`, the first that
  holds, with the reversibility class 0.1 already had. Evidence counts only from a record
  the auditor can open; the handoff's own `rejected` lines are claims, not that record.
  A checkpoint pointer cannot be opened, so a build session that wants a checkpoint choice
  to count records it in a commit body or ticket comment. A deferral stays a deferral:
  `/cca:handoff` never rewrites its status.
- **Decision and scope entries are not findings.** They are report items with their own
  sections, never enter `ledger/5.md`, `ledger/6.md`, or `ledger/7.md`, have no review
  gate, and never change the verdict counts. When an entry shows a defect, the auditor
  files a separate Q4 finding, which goes through the gate like any other. This keeps the
  review gate's meaning, and the verdict counts, unchanged. For the same reason a missing
  entry or challenge line does not fail a scope: a missing auditor entry is recorded as
  `not assessed` (verdict `not verified`, reason "not assessed"), and a missing adversary
  line as `not challenged`. The completeness gate for `verification` claims is unchanged.
- **Scope check (H4).** For a raised ticket, the hygiene scope states whether the bundle
  introduced the behavior, whether the fix lies inside the bundle's repos, and the cost,
  then include or defer. It records disagreement with the handoff on the facts and on the
  recommendation separately, since a handoff can be right on one and wrong on the other.
  The acceptance case asserts the facts, not the recommendation.
- **Return trip (H5).** `claims-verdicts.md` carries the report's revision and, for each
  claims file, its hash, and each line carries the claim's text. A line applies only when
  the hash and text match, so a file edited since the audit is not silently corrected.
  `/cca:handoff --verdicts` reads the file before anything else.
- **Base of a bundle in `/cca:handoff`.** The manifest's `base`, else the PR's base
  branch, else the repository's default branch with a confirmation. A branch's upstream
  tracking ref is never the base, since it is the branch's own remote copy.
- **Handoff identity and grammar.** Bundle names are slugs that match the stage 1 names,
  ticket ids are unique across the handoff and qualified when short ids collide, a
  decision's ticket resolves among tickets first, every key appears once in a fixed order,
  and a `## Bundles` line is split from the right. Each rule exists so the script can
  validate with no judgment and every error carries a line number.
- **A handoff needs a bundle.** `## Bundles` needs at least one bundle, while `## Tickets`,
  `## Decisions`, and `## Raised tickets` may each hold `none`. Every other item refers to a bundle, and a
  bundle with no tickets is valid.
- **Relative `repo` paths in a handoff.** A relative `repo` path is relative to the handoff
  file, as manifest paths are to the manifest. `/cca:handoff` writes absolute paths, so the
  file can move.
- **`claims-verdicts.md` entry layout.** `text:` and `correction:` sit on their own
  indented lines under each entry's main line, so a `; ` inside either cannot be misread
  as a field separator.
- **Version string.** A 0.1.0 run resumed under 0.2.0 reruns from stage 1, by the existing
  input-hash rule, since the stage files it was built from changed.

Review findings on the first plan draft, and how each was settled:

1. Unreproduced verification is not false: taken (the departure above).
2. The ignored check lost the newer-than-marker channel: taken, with a marker per snapshot
   and the last passing check as the ignored base, then superseded by sub-second mtime.
3. A branch's upstream is not its base: taken.
4. Decision classes mixed dimensions, and the handoff command erased deferrals: taken, with
   the three dimensions and the rule that a deferral keeps its status.
5. Handoff identities (bundle suffixes, ticket-to-bundle links, qualified refs, and the
   mapping to manifest ids): taken.
6. Grammar ambiguity (key multiplicity and order, non-empty values, option cardinality,
   first-occurrence splits, tabs, CR, versions): taken.
7. Script failure and filename handling, and portability coverage: taken, with exit 2 and
   the CI matrix.
8. Completeness of decision and scope entries, and defect promotion: taken, with completion
   checks in stages 4 and 5.
9. Return-trip provenance (file hash and claim text) and reading `--verdicts` first: taken.
10. The work-item contract contradicted itself on forge ids and had no real validation:
    taken.
11. The raised-ticket case asserted a recommendation: it now asserts the facts only.
12. Conditional acceptance expectations, the export-runs policy, and more grammar test
    cases: taken.

Review findings on the second plan draft:

- Ticket identity: ids unique across the handoff, qualified when short ids collide, raised
  `ticket` values unique, and a decision's ticket resolves among tickets first.
- Grammar: bundle names are slugs, the Bundles line is split from the right, and every
  listed bundle must exist.
- Operations validation: the validator also checks `run`, `C<n>`, and claim references
  against the report body and `claims.md`, before hashing, and operations carry no
  revision.
- Pending ignored writes: reconciled after every check that did not exit 1 or 2.
- Self-certified decision evidence: only a record the auditor opened counts.
- Validation after the report was final: moved before hashing.
- A write during a snapshot reported again: sub-second mtime replaces the marker channel
  for ignored files.
- GNU-only `touch -d` in the test: the ISO form both GNU and macOS accept, with the times
  asserted before the result.

## 0.3.0 decisions (2026-10-01)

0.3.0 closes issues #5 to #11: auditing uncommitted work, env tags, live results fed back
into a run, parent and links keys, more work-item operations, a ticket token, and memory
reconciliation. The plan was reviewed ten times by a second opinion before implementation;
the settled findings are listed below. Nothing was run against a live audit; the
acceptance record keeps every agent-driven case `not run` until one runs.

Decisions taken with the user:

- **gh 2.73.0 for GitHub tickets.** Hygiene checks closing-PR links, which
  `closedByPullRequestsReferences` gives and older gh lacks. Azure DevOps and other forges
  are unaffected: their exports already carry parent and links.
- **Live results for `X<n>` and `L<n>`.** Accepted, through carried findings (below).
- **Live bookkeeping is a script.** `live.sh` (`check`, `import`, `active`, `carry`,
  `assemble`, `retire`) holds the file bookkeeping; the orchestrator keeps only the
  derivation, a judgment.
- **`ticket_token` takes a string or a list of templates.**
- **New fixture material.** The `tokens` fixture, and `manifest-working-tree.json` in
  `solo` and `solo-dirty`.

Settled choices:

- **Working-tree head (#5).** The bundle key `head: working-tree` is manifest only and
  needs the bundle's branch checked out. Stage 1 step 1c builds the head with
  `working-tree.sh build`, into a temp index, with a fixed author, date, and message and
  `--no-gpg-sign`, so the same tree gives the same sha and a resume can rebuild a pruned
  head. The only writes are objects, disclosed in Coverage along with the head having no
  ref. The bundle is read directly, searched with `git grep <head sha>`; untracked files
  at audit time are part of the head.
- **Refusals.** No HEAD commit, a sparse checkout, skip-worktree or assume-unchanged
  paths, unmerged paths, a dirty submodule, an untracked nested repository, Git LFS, a
  filter with a `clean` or `process` program, and a quoted path. A dirty submodule's files
  are not in the parent's tree, so a rebuild could give the same sha after they change.
  Filters are never disabled, since the tree would then differ from the user's own commit.
- **Act drift.** Decided by the committed tree, not ancestry, plus any commit act did not
  log; an unchanged clean `HEAD` and a rewritten history with the same tree are not drift.
- **Resume after a pruned head.** Resume snapshots, rebuilds, and checks read-only; an
  unchanged tree gives the same sha, a different one is a changed head, handled as before.
- **Env tags (#6).** A verified entry whose check starts `env: ` must read
  `env: <name>; <check>`. Such a claim is never `true` or `false` from a run here, since a
  run here is another environment. It is `not verified, not reproduced`, listed in section
  9, and `claims-verdicts.md` calls it `not reproducible here`, not a recheck request.
  `--verdicts` applies nothing for it and `memory.sh` ignores it.
- **Live file format (#11).** A `--live` file names a finding id of a Live checks block, or
  `claim <n>`, never `C<n>`, which is not stable across a rerun. The validator recomputes
  the report body's SHA-256, matches the report's revision and the block's query exactly,
  and, for a claim, its `env`. An environment named only inside free-text `where` does not
  identify it.
- **Imports are the record.** `live/results-<k>.md` is an import once renamed into place,
  numbered across the run and never moved. Only retirements are logged
  (`live/retired.md`). The derived `live/findings.md`, `live/claims.md`, and
  `live/carried/` are rebuilt from the active imports, never created empty, and a `.pending`
  copy is never read.
- **Carried findings.** A rerun renumbers `X<n>` and `L<n>`, so a result for one carries
  the finding's block in `live/carried/<id>.md`, written once. The id is reserved on the
  rerun, and the carried finding goes through both reviews like any other.
- **Review of a live result.** A finding in `live/findings.md` counts only after stage 6
  gave a position and the late adversary a verdict. Until then every position on it from the
  rerun, and its derivation, is `pending review` and cannot set an item's severity, label,
  or disposition. Reruns from stage 5 or earlier retire the imports first.
- **Script exit codes.** `live.sh` exits 0, 1 for named validation and state errors on
  stdout, and 2 for usage and any failed operation on stderr. Writes go through a temp file
  and a rename, and a rerun after a failure completes the job.
- **Parent and links (#7).** Optional keys `parent` and `links` on tickets and raised
  tickets; `links: none` is a checkable claim. `cca-handoff: 1` stays, so ccl must check for
  cca 0.3.0 or later before writing them. `/cca:handoff` fills them from the record only,
  and gh has no parent field.
- **Work items (#8).** `update_comment`, `remove_link`, and `set_fields`; `mentions` on
  every op with `text`; `W<n>` items for an op that exists only to support another. The
  validator rejects unknown keys and an op that reaches no `C<n>` or `claim <n>`, directly
  or through a `W<n>`, so a `W` cycle fails.
- **Ticket token (#9).** A literal template with `{n}` once, never a regex, matched with
  the base boundary outside the whole token, for exported tickets only. A list is allowed
  because `#{n}` does not match `AB#4567`, and Azure DevOps commits write both.
- **Memory reconciliation (#10).** `memory.sh find` prints, never edits. Keys are the
  ticket id, quoted names, and words that are a number, a sha, or an id; a free phrase is
  never a key. Stage 8 writes a `ticket:` sub-line to `claims-verdicts.md` so the script
  needs no second file. A 0.2.0 file has none, and the script uses the text alone.
- **Not done.** Keeping `C<n>` stable across a stage 7 rerun: live entries use finding ids,
  and act binds to the revision.

Probes (2026-10-01, git 2.55.0.windows.5, gh 2.91.0, Git Bash, isolated config):

- Building a commit from a temp index with `read-tree`, `add -A`, `write-tree`, and
  `commit-tree` twice gave the same sha, left `.git/index` unchanged, and made no ref.
- With `commit.gpgSign=true` and `gpg.program=false`, `commit-tree` still exited 0, so this
  git does not sign from config; the script passes `--no-gpg-sign` anyway.
- A skip-worktree file removed from disk was missing from the built tree, so it would read
  as a deletion; flagged paths and sparse checkouts are refused.
- `git check-attr --stdin filter` printed `lfs` for a `filter=lfs` path and `unspecified`
  for the rest.
- `gh issue view --json` has no parent field and offers `closedByPullRequestsReferences`,
  first named in the gh v2.73.0 release notes.
- ccl#25 is the merged ccl 0.9.0 PR, not an open issue; ccl writing `parent` and `links`
  is ccl#26, opened 2026-10-02.

Review findings, by round, and how each was settled:

1. Round 1, 11 findings, all taken. `X<n>` and `L<n>` ids do not survive a rerun
   (replaced in round 2); results could be installed for a resume that cannot use them
   (eligibility first, retire on early reruns); a reviewed duplicate could let an item count
   at an unreviewed severity (unreviewed derivations stay out of positions); clean filters
   other than LFS can run programs (refuse any driver with `clean` or `process`, resume
   snapshots and checks around its rebuild); act kept an ancestry test (drift is the
   committed tree); a result of another query could settle a finding (the validator requires
   the query exactly); hygiene could not check GitHub links (fetch the closing PRs); memory
   keys dropped literals and took words with digits (explicit grammars); a claim-only
   import would create an empty `live/findings.md` (derived files never empty); `ticket_token`
   did not say literal or regex (literal templates, boundary outside the token); test gaps.
2. Round 2: round 1 items 4 to 10 resolved, 4 reopened, 7 new, all taken. `X<n>`/`L<n>`
   results now carry the finding and reserve its id;
   approval sources could collide after a retirement
   (imports numbered across the run); a position on a live finding could promote it before
   the late adversary saw it (`pending review`); the validated file was not the imported one
   (validate the copy, then rename); an environment as a word in `where` did not identify it
   (an exact `env` key); the validator trusted the revision header (recompute the body hash);
   a recorded `absent` input read as missing (the optional-input rule); low-tier rules made
   live-reviewed `P`/`T` findings provisional (a live exception); stage 8 read challenge
   lines from an unhashed file (`late/adversary.md` is an input); dirty submodules and
   untracked nested repositories are not in the synthetic tree (refused); test gaps.
3. Round 3, 2 reopened, 2 new, all taken, by simplifying the import model: the results
   files are the import record, only retirements are logged, derived files are rebuilt from
   the active imports; a carried finding is kept once in `live/carried/<id>.md`; a deleted
   derived file is rebuilt; carried text counts toward the split threshold.
4. Round 4, 2 findings, both taken: stage 8's fallback includes carried findings, gated by
   the live rule (V3-y); a discarded `.pending` number may be reused, since only committed
   imports have approvals to protect. The agent-driven cases were renumbered V3-j to V3-ah.
5. Round 5 found nothing in a full reread. A later reread found reconciliation ordered
   before step 6 picks the rerun stage, which retirement depends on. Round 6 on that fix:
   reconcile also when no stage reruns, recompute after reconciling, apply the eligibility
   stop with `--live` only, and remove `.pending` copies on the retirement path. Taken.
6. Round 7, on the move of bookkeeping into `live.sh`, 3 findings, all taken: exit codes for
   every mode and resume stopping on any nonzero one; literal outputs, errors, and grammars
   for entries, derived files, and `retired.md`; tests for replay, rebuild, numeric order,
   `carry L1`, malformed state, operational failures, and recovery after a partial `retire`
   or `assemble`.
7. Round 8, 2 left, both taken: the malformed derived file message got its exact text and
   order; "exit 1 writes nothing" now allows `import`'s `.pending` cleanup and an empty
   `live/`.
8. Round 9, 1 open, taken: `retire` read `live/retired.md` after removing `.pending` files,
   so it checks first and exits 1 having changed nothing.
9. Round 10 found nothing in a full reread of the `live.sh` contract and its tests.

The final review of the branch against `main` found 2, both taken:

1. The stage 1 baseline ran `git status` before `working-tree.sh` refused a program
   filter, so a clean filter or an fsmonitor hook could run first. `working-tree.sh check`
   runs the refusals alone, writing nothing, in A.4 and before resume's snapshot, and
   `readonly.sh` runs its index-reading git calls with fsmonitor off.
2. Building from `read-tree HEAD` dropped a file staged with `git add -f` despite an
   ignore rule. The temporary index is now a copy of the repo's own index (`cp -p`), so
   the head is what `git add -A && git commit` would make.

Later rounds of the same review, each fix shown failing on the old script first, all in
`working-tree.sh`:

3. A submodule's own clean filter ran inside the recursive `git status` on a same-size
   edit. The filter scan now covers every checked-out submodule before any status.
4. A `post-index-change` hook ran during `add -A`; every git call now points
   `core.hooksPath` at an empty directory. A dirty submodule staged as a rename was a
   porcelain type 2 record the refusal did not read; status now runs with
   `--no-renames`.
5. A driver literally named `set`, `unset`, or `unspecified` was skipped; it is now
   checked like any other. The skip-worktree and assume-unchanged refusal now runs in
   every checked-out submodule.
6. A missing index file let attributes the scan could not see come back from HEAD in a
   fallback build. A repo or checked-out submodule with no index file is now refused,
   and the fallback is gone.

## Deferred past 0.3

- ccl emitting a handoff, and a ccl hint suggesting `/cca:audit` (F7 and H6). Both are ccl
  changes. `skills/cca/handoff.md` is the format ccl can adopt, and `/cca:handoff` can run
  in any session, including one that ran ccl.
- Applying `work-items.jsonl` to a forge. 0.2.0 writes and validates the plan; no adapter
  ships.
- Native Azure DevOps and other forge fetching. Exported files are accepted.
- Automatic trigger from ccl. A ccl run's report is passed as a claims file, or
  `/cca:handoff` writes a handoff.
- Exact token accounting.
- A PreToolUse hook that enforces the read-only boundary mechanically.
- `readonly.sh` takes its snapshots with `git status`, which runs a clean or process
  filter on a modified file of a dirty checkout, in any audit (found in the 0.3.0 final
  review; older than 0.3.0). A `head: working-tree` bundle is safe, since its refusals
  run first. Other repos need a snapshot that never runs a filter.
- Bounded loading for every agent input (2026-09-30 review). Today the unit is the
  450,000-byte chunk or ledger slice, an ordinary corpus file is read in full, a single
  finding larger than the split threshold is passed whole as an `over threshold` part,
  and a merger may reopen a full ledger file for a duplicate check. A per-agent byte
  cap with sectioned inputs is a later design change, still deferred.
