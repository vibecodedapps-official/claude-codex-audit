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

For a `head: working-tree` bundle, `<head sha>` is followed by
`(working tree on <parent sha>)`, the built commit and the `HEAD` it sits on.

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

Per ticket (then `unticketed`, then `cross-cutting`), items severity first. Each item
sits under a heading `#### C<n>: <title>`; the work-items validator finds items by it.
Under the heading: effective severity, gate, disposition, the absorbed ledger ids,
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

Then each operation in `work-items.jsonl`, one line per operation: its `W<n>` id, the
op, the target, the item ids it covers, and its reason. These are drafts for a person
or an adapter; act applies none of them.

### 8. Decisions

Three parts.

- Decision ledger: each `decision` claim, with its class (`stale deferral`,
  `needs <owner>`, `default taken`, or `evidenced`), resolution, authority, whether
  alternatives were weighed, reversibility class, the recommendation, and the owner. The
  auditor's position and the adversary's follow, or `not challenged` when pass two wrote
  no line for the entry; when they differ, both are kept and no side is picked. A claim
  that is `not assessed` is listed with that mark only: no class, fields, or adversary
  position.
- Raised tickets: each `scope` claim, with whether the bundle introduced it, whether the
  fix is inside the bundle's repos, cost, the recommendation (`include` or `defer`) and
  its reason, the handoff's ranking, and whether the facts and the recommendation
  differ from the handoff, each stated on its own. The adversary's position follows, or
  `not challenged`. A `scope` claim that is `not assessed` is listed with that mark only.
- Other decisions: each decision the change made or needs that is not a `decision`
  claim: the recommendation, the reason, and a reversibility class (`reversible`,
  `hard to reverse`, or `contract change`). A named owner, from the tickets or threads
  only, for `hard to reverse` and `contract change`; otherwise "owner not recorded".
  Act may post a decision to its ticket as a drafted comment only when the user says to
  for that item.

Decision and scope entries are report items, not findings: they have no item id, never
enter a ledger, and never change the counts.

### 9. Live checks

One block per live check: each finding with a live check, and each env claim
(`common.md`, "Env claims"), keyed by claim number. Every value is a whole line, and the
format is the one in `live.md`:

```
#### live <finding id> | live claim <n>
- item: C<n> | claim <n>
- query: <the query or command, exactly as the check states it>
- where: <where it runs>                  (finding)
- env: <name>                             (env claim)
- results: <what each result changes>     (finding)
- status: not run: not approved | run, approved by <who> at <time>: <result>; derived: <derived>; <reviewed | under review: <what it lacks>>
```

A result is fed back with `/cca:resume <run-id> --live <file>`. Every approved live
access, each result with its approver and time, is logged here. `none` when no finding
has a live check and no claim is an env claim.

### 10. Claims

Every numbered claim from `claims.md` with its kind (`code`, `decision`, `verification`,
`scope`, or `status`), then `true`, `false`, or `not verified`, and the item id or
evidence. `other` sentences are counted, not listed. A `decision` or `scope` claim with
no pass-one entry is `not verified`, with the reason "not assessed".

A `verification` claim is `true, reproduced` only when the audit reproduced the stated
result itself, `false, contradicted` only with counter-evidence, and otherwise
`not verified, not reproduced` with the reason. A live claim takes its derived verdict,
and `contested` when the late adversary overturned it, or `not verified, not reproduced`
when the late adversary gave no line. One line says that reproducing a stated
result does not show that the build session ran its stated check. Where the auditor's
and the adversary's verdicts differ, both are shown.

`claims-verdicts.md`, beside this report, carries these verdicts back to the build
session.

### 11. Coverage

- Handoffs: each handoff claims file, its hash, and whether `handoff.sh check`
  validated it.
- Work items: the `work-items.sh check` result for `work-items.jsonl`: `work-items: ok`,
  the error lines and that the file is not ready for an adapter, or that it was not
  validated and why.
- Stages: each stage 1 to 8 as `complete`, `not applicable`, `failed`, `swapped`, or
  `not run: budget expired`, with the reason.
- Swaps: every swap, with role, scope, from, to, and reason (including Codex swaps).
- Failed scopes and the files, rules, or questions they left unreviewed, naming the
  last byte offset of a digest that ended `status: failed at byte <offset>`.
- Each `decision` or `scope` claim that is `not assessed` (the pass-one report has no
  entry for it), and each entry that is `not challenged` because pass two wrote no line
  for it. Neither fails a scope or changes the verdict counts.
- Each bundle whose base refresh the user declined ("base: local ref, refresh
  declined" in the brief): the base commit list and overlap set are as of that ref.
- Each `head: working-tree` bundle: the loose objects `working-tree.sh build` wrote to
  the repo's object store (an allowed write), that the head commit has no ref and
  `git gc` may prune it after its prune window, the files untracked at audit time, and
  the paths flagged at audit time, each held at its index version: its local content is
  not in the head, and a change to one during the run may escape the read-only check,
  which does not compare it.
- Stage 6: whether the mandatory ids were requested in batches (`batched`) and, from
  `missing_positions`, every mandatory id left without a position (those Codex was
  asked for and left unanswered after the follow-up, and those of a fallback batch
  that failed). A partial swap, the fallback answering the ids Codex was not asked
  for, is listed as a swap with its scope.
- Corpus files stage 2 split by byte range: the source, the path, its size, each
  range, and the chunk id (`digest-N`) that covered it with that chunk's status.
- Unanswered questions, and questions marked "not run".
- Departures from the original stage plan (for example, the low tier's single auditor
  covering tests and work-item hygiene).
- Read-only check: each `baseline/<stage>-check.md` result, and every ignored file
  accepted, with the run that wrote it. Not detected by the check: an ignored file
  replaced with one of the same size and a restored modification time, changes inside
  `.git/` other than refs, stashes, and config, a change to a nested repository's refs
  other than its HEAD, its stashes, or its config, a change inside a repository that
  sits in an ignored directory, such as a linked worktree, other than an entry added or
  removed at its top level, and changes outside the audited repos. When any check file
  carries the note `note mtime precision: seconds`, say the ignored-file comparison used
  whole-second times, so a same-size rewrite within the same second was not detected. A
  user's own edits to an audited repo during the run would also have tripped the check.
- Forge: which bundles were not queried, and exports' "not in export" keys.
- Test injection: the `_test` key, when present.

### 12. Usage

From `usage.md`, per stage: agents, requested models (the report says "requested",
never "used"), wall-clock, and tokens labeled "task notification, subagent_tokens;
scope not documented", or "not reported", including every Codex call. Any sum is
labeled "sum of reported numbers, not exact".
