# Changelog

## Unreleased

### Added

- A `--live` entry can give `result_file: <path>` in place of a one-line `result`, so a
  result that is more than one line, such as the rows a query returns, is kept verbatim.
  The path is relative to the `--live` file and stays under its directory. `live.sh
  import` copies each file to `live/results-<k>/<heading line>.txt` and writes
  `SHA256SUMS` from the copies, committed with the results file. `import`, `active`, and
  `assemble` stop with a named line when a copy of an active import is missing or no
  longer matches its hash. The derivation, the second opinion, the late adversary, and
  the report read the copy, and the report gives its path and hash.

### Fixed

- `skills/cca/work-items.md` says what `work-items.sh` already enforces: a required
  top-level string field, `comment_id` included, must not be empty (`set_field`'s
  `value` may be).
- "Writing a handoff" in `skills/cca/handoff.md` says `parent` and `links` come only from
  the forge record, never from PR or commit text, as `/cca:handoff` already did.

### Changed

- A `head: working-tree` bundle whose repo has skip-worktree or assume-unchanged paths is
  built, not refused. The head holds each flagged path at its index version, whatever
  its file on disk holds, and `working-tree.sh build` prints one `flagged <path>` line
  per such path, submodules included. The brief and the report's Coverage list them, and
  the bundle is read from an export of its head, never from the local files. A flagged
  path the build cannot hold at its index version is still refused: a flagged submodule
  or intent-to-add entry, a path that is a directory on disk or lies under a symlink or
  a file, or a path git prints quoted, which cannot be checked on disk. The read-only
  check does not compare a flagged file's content, so a change to one during the run may
  escape it; Coverage says so. Resume reruns stage 1 when a directly read working-tree
  bundle now has a flagged path, in a submodule too. A sparse checkout is now refused in
  a checked-out submodule too, not only in the top level.

## 0.3.1 - 2026-10-02

### Fixed

- Stage 1's GitHub reads name the host of the PR or ticket they read, `github.com`
  included, so they no longer go to gh's default host (`GH_HOST`, else the only saved
  login) when that differs from the bundle's host (#13). The host comes from the id's URL,
  else from the bundle repo's remote for that owner and repo, else, for a ticket, from
  the bundle's PR, else `github.com`. An SSH remote on a host other than GitHub's counts
  only when gh knows that host, which needs gh 2.81.0 or later unless the id is given
  as a URL; a known host whose login fails is never swapped for another. Resume and
  `/cca:handoff` name the same host, and resume reruns stage 1 when a host changed.
  When the PR read, its review threads, or a named ticket's read fails, the run stops
  with a line that names the host it queried; give the id as a URL when that host is
  wrong. A failed read of a closing issue, or of a ticket's parent, is a gap listed in
  the brief, not a stop, and resume retries it. `tests/lint.sh` fails on a
  `gh pr` or `gh issue` command in a code span under `agents/`, `skills/`, or
  `commands/` that passes neither `-R <host>/<owner>/<repo>` nor a URL argument, and on
  a `gh api` command without a `--hostname` option.

### Changed

- A run started under 0.3.0 and resumed under 0.3.1 reruns from stage 1.

## 0.3.0 - 2026-10-01

Closes issues #5 to #11. No full multi-agent audit has run yet; see `docs/acceptance.md`.

### Added

- A manifest bundle key `head: working-tree` audits uncommitted work. Stage 1 builds a
  commit from the working tree with `skills/cca/scripts/working-tree.sh`, without touching
  the index or refs, and reads the checkout directly, so tests can run. The objects it
  writes, and that the head has no ref, are disclosed in the report. A repo whose files use
  Git LFS or a filter that runs a program, or whose nested repositories have uncommitted
  work, is refused.
- `/cca:resume <run> --live <file>` feeds approved live check results back into a run. The
  format is in `skills/cca/live.md`, validated by `skills/cca/scripts/live.sh`. A changed
  finding goes back to the second opinion and the late adversary before it counts.
- Verification checks tagged `env: <name>;` are listed as live checks by claim number, and
  `claims-verdicts.md` calls them `not reproducible here`, not recheck requests.
- Optional handoff keys `parent` and `links`, for tickets and raised tickets. Stage 1 fetches
  the PRs that close a GitHub ticket, and its parent through GraphQL, so hygiene can check
  both.
- Work-item operations `update_comment`, `remove_link`, and `set_fields`, mentions, and
  `W<n>` items for supporting operations.
- A manifest bundle key `ticket_token`, so a bare-number ticket id matches only as a ticket
  reference, and a `tokens` fixture.
- `/cca:handoff --memory <dir>` lists the memory files that hold each `false` claim's keys,
  with `skills/cca/scripts/memory.sh`. `claims-verdicts.md` gains a `ticket:` sub-line.

### Changed

- `work-items.sh` rejects unknown keys, an empty `set_fields`, a `W<n>` that names no
  operation, and operations that reach no report item or claim.
- Report section 9 lists each live check as a block keyed by finding id or claim number.
- GitHub tickets need gh 2.73.0 or later.
- `/cca:resume --live` needs `jq`, on any forge.
- CI runs the three new script tests on all runners and under mawk, and fails when jq is
  missing.
- A run started under 0.2.0 and resumed under 0.3.0 reruns from stage 1.

## 0.2.0 - 2026-10-01

Closes the gaps found by one real audit of 0.1.0, and adds a typed handoff from the build
session to the audit, with a return trip back. No full multi-agent audit has run yet; see
`docs/acceptance.md`.

### Added

- `/cca:handoff`: run in the build session, it writes a typed `handoff.md` (tickets,
  decisions, raised tickets) from the record, and with `--verdicts` applies a
  `claims-verdicts.md` from an earlier audit.
- The handoff format (`skills/cca/handoff.md`) and `skills/cca/scripts/handoff.sh`, which
  detects, validates, and turns a handoff into typed claims and a commit list. A leading
  UTF-8 byte order mark is ignored, and a claim line over 8,000 bytes, ids included, is
  an error, since a claim is read as one line. A section with no item and no `none` is an
  error.
- Typed claims, with kinds `code`, `decision`, `verification`, `scope`, and `status`.
  Prose claims files get a kind per sentence. A handoff's commit lists seed the review
  groups.
- A decision ledger for `decision` claims: each is `stale deferral`, `needs <owner>`,
  `default taken`, or `evidenced`, with a reversibility class. Report section 8 lists them.
  A missing ledger or scope entry is `not assessed`, and a missing challenge line `not
  challenged`; neither fails a scope or changes the verdict counts.
- A scope check for raised tickets: introduced by the bundle or not, fix inside the
  bundle's repos or not, cost, include or defer, and any disagreement with the handoff.
- `claims-verdicts.md`, a stage 8 output that tells the build session which of its
  statements were shown false, which could not be reproduced, and which are contested.
- `work-items.jsonl` and `skills/cca/scripts/work-items.sh`: a work-item operations plan,
  one JSON object per operation, with placeholders for tickets that do not exist yet, and
  its validator. Nothing applies it; no forge adapter ships.
- A manifest `scratch` key: an ignored path in the primary repo, under any name, for the
  run directory.
- `skills/cca/scripts/readonly.sh`: the per-stage read-only check as a script.
- Tests `tests/readonly.sh`, `tests/handoff.sh`, and `tests/work-items.sh`, and a CI
  `scripts` job on Linux, macOS, and Windows. The fixture gains a handoff and two
  manifests.
- README: a "Before the first run" note on sizing sources, and the new commands and
  outputs.

### Changed

- A `verification` claim is `true` only when the audit reproduces the result itself. One
  it cannot reproduce is `not verified` with the reason `not reproduced`, listed in
  `claims-verdicts.md` as a recheck request, never as a correction. The pass-two
  adversary re-checks every verification claim marked `true`. A run under a different
  setup than the stated check needs is not counter-evidence, and the handoff asks the
  writer to name a check's preconditions.
- The read-only check runs a script. An ignored file is compared by size and sub-second
  modification time, and each audited repo has its own baseline marker. Paths that git
  prints quoted are not supported and stop the check with exit 2. Nested repositories
  (checked-out submodules and untracked repositories inside an audited repo) are checked
  as part of it, and the files under a submodule that is not checked out are hashed. An
  upstream's ahead and behind count is no longer compared, and the run directory is
  matched without regard to case where the repo's `core.ignorecase` is true. The check
  compares its output prefix with the baseline and the run directory by file identity, and
  refuses a prefix with a `..` component, so a prefix spelled in other letters or routed
  through a missing directory cannot overwrite the baseline. A repository inside an
  ignored directory is recorded as one ignored directory, so a change inside it is not
  detected unless it adds or removes an entry at its top level, and the report says so.
- The stage 1 ticket token rule now names the token for an exported ticket (its `id`),
  matches a GitHub `#n` only for an issue in the bundle's repo, and checks a boundary on
  both sides, so `APP-1` matches neither `APP-1a` nor `XAPP-1`. Before a GitHub token the
  character is also not `-`, `_`, `.`, or `/`, so `owner/app#12` does not match inside
  `other-owner/app#12`.
- No git command cca or its agents issue rewrites an audited repo's index: the check
  script sets `GIT_OPTIONAL_LOCKS=0`, the stages run `git status` with
  `--no-optional-locks`, and agents diff only between two commits, since a working-tree
  `git diff` writes the index even with that flag.
- Agents run no test or lint command in an exported tree, in `skills/cca/common.md`,
  stage 1, and the agent definitions.
- Codex requests: the request names every input by absolute path, whatever the run
  directory, and Codex acknowledges each input with its sentinel. Only an input it could not
  open goes inline, in the one follow-up, under the 450,000-byte cap, over which stage 6
  fails. The inline first request, its diff dropping, and `inline_reduced` are gone. A probe
  showed Codex reads a file outside every repository by absolute path in codex-lite's
  read-only sandbox on Windows; Linux and macOS rely on Codex's documented policy.
- Stage 8 writes three outputs: `report.md`, `claims-verdicts.md`, and `work-items.jsonl`.
- The README no longer says "Tested on"; it says what ran and what has not.

A run started under 0.1.0 and resumed under 0.2.0 reruns from stage 1, by the existing
input-hash rule.

## 0.1.0 - 2026-09-30

First release. Built against Claude Code 2.1.284; see `docs/acceptance.md` for what ran.

### Added

- `/cca:audit`: a read-only, adversarial audit of a bundle of pull requests in one or
  many repos, from a manifest, prompt inputs, or both. Stages: orient, digest, domain
  map, pass one, pass two, second opinion, converge, and report.
- `/cca:resume`: reruns a run from the first stage that is incomplete or whose inputs
  changed, or from `--from <stage>`, reusing earlier stages.
- `/cca:act`: makes local commits for report items you approve by id, with baseline and
  per-commit checks, a confirmation per commit, and no push or forge edits unless you
  say so per item.
- Five role agents, `cca:digester`, `cca:mapper`, `cca:auditor`, `cca:adversary`, and
  `cca:merger`, none with Edit or NotebookEdit.
- Effort tiers low, medium, and high, picked from the bundle's size or set with
  `--effort`.
- A review gate: a finding counts toward the verdict only after a reviewer other than
  its author challenged it and both a Claude adversary and the second opinion saw it.
- The read-only boundary with a stage-end check that stops the run `blocked` on a
  change to an audited repo, and exact tree exports from git objects when a checkout is
  not at the audited sha.
- Codex second opinion through codex-lite, optional, with a named swap to a fresh
  adversary agent.
- Exported forge files for tickets and PRs from forges cca does not query.
- `--budget`, `--max-agents`, and `usage.md` with labeled token numbers.
- Development checks: `tests/lint.sh` and the `tests/fixture/build.sh` fixture builder.

### Fixed before release

Review fixes applied between the first candidate and the tag, on 2026-09-30 and
2026-10-01.

- Stage 6: the acknowledgment check applies to the fallback's answer too, not only
  Codex's.
- Stage 6: every blocker or high finding and every pass-two downgrade or drop needs a
  position; missing ones get one follow-up, then fail the stage (`missing_positions`);
  above 60 mandatory ids the asks are batched (`batched`): Codex gets the first batch
  and at most 60 positions in its one follow-up, every other id goes to the fallback
  (one launch per batch of 60, a partial swap), and the fallback is launched once per
  batch without Codex. The
  stage fails on such a batch only when it fails after the ladder. Every mandatory id
  is requested in a run that completes.
- Stage 6: a request over the inline cap is first reduced by dropping the diffs of
  session-repository bundles (`inline_reduced`) before the swap; other repos' diffs
  are never dropped.
- Stage 8: the terminal state is decided from stages 1 to 7 only.
- Stage 1: fetches are explicit, tag-free, into remote-tracking refs only, verified by
  sha, and recorded in the approval, which covers only its listed commands; a
  `<other remote>/<branch>` ref is fetched from that remote.
- Stage 1: a GitHub PR bundle's base is pinned to the local sha of
  `<remote>/<baseRefName>` after the approved fetch (`baseRefOid` is recorded for
  information only), refreshed with every approved fetch; every restricted fetch passes
  `--refmap=`; resume stops and asks for a changed head or base sha.
- Resume: hash pipelines fail closed (`pipefail`), and a GitHub-backed run without
  `forge_hashes` reruns stage 1. Stage 6: the Codex follow-up asks for at most 60
  positions; the rest go to the fallback.
- Stage 1: `gh` output is saved by shell redirect, and a `jq` projection of it
  (`pr.hash.json`) is hashed (`forge_hashes`); resume re-queries once and compares.
  `jq` is required for GitHub PRs.
- Stage 1: the run directory is created before the PR is read.
- Stage 1: each repo has one selected remote (for a GitHub PR bundle, the one whose
  URL names the PR's repo, settled at section C; for other repos, selected lazily when
  a fetch is needed; a PR bundle whose repo has no remote stops), and the fetch also
  covers tags and shas. A fetch approval for a bare name covers the `ls-remote` check
  and either candidate refspec and records the resolved kind. The run id slug for a
  `file:` PR export uses the export's `id`, else the bundle's `branch`.
- Resume: reads `manifest.json` and `stages.json` first and reruns from stage 1 when
  stage 1 is missing, running, or has no brief, or when `stages.json` is missing; it
  never moves `manifest.json`, includes `tmp/` in the walk, and removes stale
  `pr.json.new` files on the stage-1-rerun path.
- Stage 2: a text file over 450,000 bytes is split into byte-range chunks
  (`split_files`), measured in place for an exported tree or from a copy under the
  run's `tmp/` for a directly read one, and read by the digester in slices of up to
  24,000 bytes ending at a line break, with absolute line numbers from one `awk` stage.
- Stage 7: split-mode group mergers read per-group slices under `ledger/slices/`,
  written by shell (`awk`, `printf`, redirects), not through the model.
- Docs: acceptance evidence for the fixture map path and the lint output for an agent
  that lists Edit.
