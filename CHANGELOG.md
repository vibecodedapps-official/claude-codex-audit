# Changelog

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
  an error, since a claim is read as one line.
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
  adversary re-checks every verification claim marked `true`.
- The read-only check runs a script. An ignored file is compared by size and sub-second
  modification time, and each audited repo has its own baseline marker. Paths that git
  prints quoted are not supported and stop the check with exit 2. Nested repositories
  (checked-out submodules and untracked repositories inside an audited repo) are checked
  as part of it, and the files under a submodule that is not checked out are hashed. An
  upstream's ahead and behind count is no longer compared, and the run directory is
  matched without regard to case where the repo's `core.ignorecase` is true. The check
  compares its output prefix with the baseline and the run directory by file identity, and
  refuses a prefix with a `..` component, so a prefix spelled in other letters or routed
  through a missing directory cannot overwrite the baseline.
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
