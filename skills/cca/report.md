# Report template

Stage 8 fills this template into `<run dir>/report.md`, from what is on disk:
`converged.md`, the ledger files, the `pass2/` files, the Claims lists from pass one,
`stages.json`, and `usage.md`. Everything between `<` and `>` is filled in; every
section is present, with `none` when empty. Finding and item shapes are those in
`common.md`.

## Revision line

The report's first line is its revision:

```
revision: sha256:<hex>
```

`<hex>` is the SHA-256 of the file body below that line, byte for byte, as written.
Write the body first, hash it (`sha256sum`, or `shasum -a 256`), then write the file
with the revision line followed by the body. `/cca:act` binds its approval to this
line.

## Partial and blocked runs

- When a stage failed or the budget ran out, the report is still written, from
  whatever is on disk: `converged.md` when it exists, else the ledger files, else the
  `pass1/` and `pass2/` files. Every finding that has not passed the review gate is
  marked `provisional`. The verdict is `audit incomplete`, with the counts so far,
  never `ready to merge`. The terminal state is `partial`.
- When no report can be written, or the read-only check failed, the run is `blocked`
  and this template is not used; the reason is printed.

## Body

```
# cca audit report: <run-id>

run: <run directory> | tier: <tier> (<reason>) | terminal state: <reported | partial>
bundles: <bundle> <repo> <head sha> against <base> <base sha> (merge-base <sha>), ...
generated: <time>
```

### 1. Verdict

`not ready`, `merge after fixes`, or `ready to merge`; in a `partial` run,
`audit incomplete`. Write the counts first, then the verdict, then the rule that
decided it, so a reader can check it.

Counts table: for each severity (blocker, high, medium, low, note), the number of items
by gate (`counts`, `provisional`) and by disposition (`agreed`, `contested`,
`dismissed`), plus the contested count.

Rules, applied in order, to items whose gate is `counts` only:

1. Each item has one effective severity:
   - `agreed`: the severity the reviewers accept.
   - `contested` with equal severities across positions: that severity.
   - `contested` with different severities: the higher severity only when the higher
     position's label is `verified fact`; otherwise the lower. With more than two
     positions, the highest position's label decides.
   - `contested` where one position is `dropped`: the item counts only when the
     keeping position's label is `verified fact`, at its severity; otherwise it does
     not count.
   - `dismissed`: does not count.
2. Any counted `agreed` blocker or high item, or any contested item whose effective
   severity is blocker or high, means `not ready`.
3. Otherwise, any counted medium item means at best `merge after fixes`.
4. Otherwise, `ready to merge`.
5. In a `partial` run, the verdict is `audit incomplete`, whatever rules 2 to 4 give;
   state the counts so far.

The verdict line reads:
`verdict: <verdict> | counted: <n> blocker, <n> high, <n> medium, <n> low, <n> note | provisional: <n> | contested: <n> | dismissed: <n>`

### 2. Findings by ticket

Per ticket (then `unticketed`, then `cross-cutting`), items severity first. Each: item
id (`C<n>`), title, effective severity, gate, disposition, the absorbed ledger ids,
the evidence (as cited in the ledger), what breaks and for whom, and its state after
each stage (pass-two verdict, second opinion, late adversary). Provisional items are
marked `provisional` and say which review they still lack.

### 3. Verified as sound

Every Verified OK item from pass one, each marked `challenged` or `not challenged`
per the tier's pass-two rule: at low, none is challenged; at medium, up to 5 per
report are; at high, all are. A challenged item that failed the challenge moves to
section 2 as the finding it became and is noted here.

### 4. Disagreements kept

Every `contested` item: each position with its reviewer, severity, label, and
evidence, and the severity the verdict rule counted it at. No side is picked.

### 5. Recommended next steps

Ordered: what to fix before merge, what to check live, what to record as follow-up.

### 6. Code fixes

By repo, then file: each change, with the item ids it resolves.

### 7. Work-item fixes

Per ticket: the ticket text to change, drafted, with the item ids. Drafted text names
no model, agent, or tool.

### 8. Decisions

Each decision the change made or needs: the recommendation, the reason, and a
reversibility class (`reversible`, `hard to reverse`, or `contract change`). A named
owner, from the tickets or threads only, for `hard to reverse` and `contract change`;
otherwise "owner not recorded". Act may post a decision to its ticket as a drafted
comment only when the user says to for that item.

### 9. Live checks

For each finding with a live check: its item id, the query, where it runs, and the
severity each result implies. Mark each `run (approved <time>)` with its result, or
`not run: not approved`. A result is not fed back into this run; the user reruns the
audit or acts on the finding by hand. Every approved live access is logged here.

### 10. Claims

Every numbered claim from `claims.md` with `true`, `false`, or `not verified`, and the
item id or evidence. `other` sentences are counted, not listed.

### 11. Coverage

- Stages: each stage 1 to 8 as `complete`, `not applicable`, `failed`, `swapped`, or
  `not run: budget expired`, with the reason.
- Swaps: every swap, with role, scope, from, to, and reason (including Codex swaps and
  "request too large for inline form").
- Failed scopes and the files, rules, or questions they left unreviewed.
- Corpus files stage 2 split by byte range: the source, the path, its size, each
  range, and the chunk id (`digest-N`) that covered it with that chunk's status.
- Bundles whose base sha moved on resume while the merge base stayed the same
  (`base moved`, from the stage entries' `base_moved` key): the recorded and the
  current base sha, noting that the recorded base sha was kept for every diff.
- Unanswered questions, and questions marked "not run".
- Departures from the original stage plan (for example, the low tier's single auditor
  covering tests and work-item hygiene).
- Read-only check: each `baseline/<stage>-check.md` result, and every ignored file
  accepted, with the run that wrote it. Not detected by the check: an ignored file
  replaced with one of the same size and a restored modification time, changes inside
  `.git/` other than refs, stashes, and config, and changes outside the audited
  repos. A user's own edits to an audited repo during the run would also have tripped
  the check.
- Forge: which bundles were not queried, and exports' "not in export" keys.
- Test injection: the `_test` key, when present.

### 12. Usage

From `usage.md`, per stage: agents, requested models (the report says "requested",
never "used"), wall-clock, and tokens labeled "task notification, subagent_tokens;
scope not documented", or "not reported", including every Codex call. Any sum is
labeled "sum of reported numbers, not exact".
