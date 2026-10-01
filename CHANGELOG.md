# Changelog

## Unreleased

### Fixed

- Stage 6: the acknowledgment check applies to the fallback's answer too, not only
  Codex's.
- Stage 6: every blocker or high finding and every pass-two downgrade or drop needs a
  position; missing ones get one follow-up, then fail the stage (`missing_positions`);
  above 60 mandatory ids the asks are batched (`batched`).
- Stage 6: a request over the inline cap is first reduced by dropping diffs
  (`inline_reduced`) before the swap.
- Stage 8: the terminal state is decided from stages 1 to 7 only.
- Stage 1: fetches are explicit, tag-free, into remote-tracking refs only, verified by
  sha, and recorded in the approval.
- Stage 1: a bundle's base is pinned by the PR's `baseRefOid`; resume compares head and
  base.
- Stage 1: raw `gh` output is saved and hashed (`forge_hashes`); resume re-queries and
  compares.
- Resume: reads `manifest.json` and `stages.json` first and reruns from stage 1 when
  stage 1 is missing, running, or has no brief.
- Stage 2: a text file over 450,000 bytes is split into byte-range chunks
  (`split_files`).
- Stage 7: split-mode group mergers read per-group slices under `ledger/slices/`.
- Docs: acceptance evidence for the fixture map path and the lint output for an agent
  that lists Edit.

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
