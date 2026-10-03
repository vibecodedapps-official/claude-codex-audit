# Fault injection (`_test`)

The orchestrator reads this file only when the manifest has a `_test` key. It exists so
that the acceptance runs can force failures, a held stage, an expired budget, a planted
map error, or small size thresholds; a normal audit never loads it. Each field below
changes how one stage behaves and nothing else. The stage files mention `_test` where
a field touches them; the rules for each field are here only.

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
