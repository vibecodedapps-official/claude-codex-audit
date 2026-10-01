# Changelog

## 0.1.0 - 2026-09-30

First release. Tested on Claude Code 2.1.284.

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
