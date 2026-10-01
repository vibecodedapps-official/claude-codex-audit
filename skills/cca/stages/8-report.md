# Stage 8: report (orchestrator)

The orchestrator's procedure for stage 8. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and the
run's `common.md` apply. The report's section headings and layout are in
`${CLAUDE_PLUGIN_ROOT}/skills/cca/report.md`; this file says where each part comes from and how the verdict is
decided.

Stage 8 always runs, even after a failed stage or an expired budget. It does not run
when the run is `blocked`: then no report is written, the reason is printed, and every
finished stage file is kept.

Inputs: `converged.md`, `gate.md`, `ledger/5.md`, `ledger/6.md`, `ledger/7.md`, the
`pass1/` and `pass2/` files (Claims and Verified OK lists, attacked Verified OK lists, the
`## Decisions` and `## Scope` sections of pass one, and the `## Claims challenged`,
`## Decisions challenged`, and `## Scope challenged` sections of pass two),
`claims.md`, `audit-brief.md`, `manifest.json`, `stages.json`, `usage.md`, and
`baseline/*-check.md`, whichever exist.

Recorded input hashes (`git hash-object --no-filters`): `converged.md`, `gate.md`, the
ledger files, `claims.md`, `audit-brief.md`, `manifest.json`, and each `pass1/` and
`pass2/` file read, whichever exist. `stages.json` and `usage.md` are read but not
hashed: they are run state, not inputs, and stage 8's own entry is written into
`stages.json`, so a hash of it could never match on resume.

Outputs: `report.md`, `claims-verdicts.md`, and `work-items.jsonl`. The format of
`work-items.jsonl` is in `${CLAUDE_PLUGIN_ROOT}/skills/cca/work-items.md`; the format of
`claims-verdicts.md` is below, after the steps.

## Steps

1. **Write the stage 8 entry as `running`,** with the recorded input hashes above.

2. **Pick the source of items from what is on disk,** first match:
   1. `converged.md`, whenever it exists and the stage 7 entry records
      `"converged_check": "pass"`, whatever stage 7's status (a failed late adversary
      does not discard a checked merge): use its items, gates, and dispositions.
   2. Else the ledger files that exist: one item per ledger finding, with its state after the last verdict it has. Compute its gate with the rules
      in `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/7-converge.md` step 4 from the ledger files present; a
      finding that has not passed them is `provisional`. Disposition: `dismissed` when
      its last verdict is `dropped` and no one asked to restore it, `contested` when
      verdicts disagree on existence or severity, else `agreed`.
   3. Else the `pass1/` and `pass2/` files: one item per finding, every one
      `provisional`, with the pass-two verdicts that exist.

   In the fallback paths 2 and 3, stage 8 still assigns `C<n>` ids, sequential in
   ledger order (or file order for path 3), each item listing its finding id as
   absorbed, so every reported item can be named to `/cca:act`. Every finding not yet
   through the review gate is marked provisional.

3. **Decide the terminal state** from stages 1 to 7 only; stage 8's own entry is
   `running` at this point. `reported` when every applicable stage 1 to 7 is `complete`
   or `not_applicable` in `stages.json`. `partial` when any of them failed, is
   `running`, is missing, or the budget expired. The state is final only after step 12
   writes stage 8 `complete`; if step 11's read-only check fails, the run is `blocked`,
   as step 11 says.

4. **Count before deciding.** For each item whose gate is `counts`, find its counted
   severity, then write the counts into the report so a reader can check the verdict:
   - `agreed`: its severity.
   - `contested` with two positions:
     - equal severities: that severity;
     - one position is `dropped`: the item counts only if the keeping position's label
       is `verified fact`, at that position's severity; otherwise it does not count;
     - otherwise: the higher severity when the higher position's label is
       `verified fact`, else the lower severity.
   - `contested` with more than two positions: the highest position's label decides.
     When it is `verified fact`, the item counts at the highest severity; otherwise
     apply the two-position rule to the highest and the lowest positions.
   - `dismissed`: does not count.
   - `provisional` items never count, whatever their disposition.

   A label of `unverified assumption` caps a severity at `medium`, per `common.md`.

5. **Decide the verdict.**
   - Run `partial`: `audit incomplete`, with the counts so far. Never `ready to merge`.
   - Any counted item at `blocker` or `high`: `not ready`.
   - Else any counted item at `medium`: `merge after fixes`.
   - Else: `ready to merge`.

   The verdict line gives the verdict, counts by severity, by gate, and by disposition,
   and the number of `contested` items.

6. **Fill the template `${CLAUDE_PLUGIN_ROOT}/skills/cca/report.md`**, in its twelve sections:
   1. Verdict, from steps 4 and 5.
   2. Findings by ticket, severity first: each item with its evidence, gate,
      disposition, item id (`C<n>`), and absorbed ledger ids. Each item sits under a
      heading `#### C<n>: <title>`, so the work-items validator can find it. A
      `provisional` item says which review it still lacks, from its reason in
      `gate.md` or from the gate rules when `gate.md` does not exist.
   3. Verified as sound: every Verified OK item from the pass-one reports, marked
      `challenged` when a pass-two adversary's `## Verified OK challenged` list names
      it, else
      `not challenged`. At low tier every item is `not challenged`.
   4. Disagreements kept: every `contested` item with each position and its evidence.
   5. Recommended next steps.
   6. Code fixes by repo and file, with item ids.
   7. Work-item fixes: the ticket text to change, drafted. Drafted text names no model,
      agent, or tool. Also each operation in `work-items.jsonl` with its `W<n>` id, the
      op, the target, the item ids it covers, and its reason. Decide the operations here,
      numbered `W1` upward in this order; step 7 below writes `work-items.jsonl` from
      the same list, so the ids match.
   8. Decisions, in three parts:
      1. Decision ledger: each `decision` claim, with its class (`stale deferral`,
         `needs <owner>`, `default taken`, or `evidenced`), the three dimensions
         (resolution, authority, evidence) from the auditor's `## Decisions` entry, its
         reversibility class, the recommendation, and the owner, then the auditor's
         position and the adversary's, from `## Decisions challenged`, or the mark
         `not challenged` when that entry has no line. When they differ, both are kept
         and neither is picked. A claim the stage 4 entry records as `not assessed` is
         listed with that mark only: no class, dimensions, or adversary position.
      2. Raised tickets: each `scope` claim, with the fields of the auditor's
         `## Scope` entry (introduced by the bundle, fix inside the bundle's repos,
         cost, recommendation, the handoff's ranking, whether the facts or the
         recommendation differ from the handoff) and the adversary's position from
         `## Scope challenged`, or `not challenged` when that entry has no line. A `scope`
         claim recorded as `not assessed` is listed with that mark only.
      3. Other decisions: each decision the change made or needs that is not a
         `decision` claim, with the recommendation, the reason, and a reversibility
         class, `reversible`, `hard to reverse`, or `contract change`. A named owner
         only for `hard to reverse` and `contract change`, and only when the tickets or
         threads name one; else "owner not recorded".

      Decision and scope entries are report items, not findings: they get no `C<n>` id
      of their own, never enter a ledger, and never change the counts. A finding an
      entry names in its `finding:` field is in section 2 like any other.
   9. Live checks: for each finding with a live check, its id, the query, where it
      runs, and the severity each result implies; each check the user did not approve
      is listed here. A result is not fed back into a run: the user reruns the
      audit or acts on the finding by hand.
   10. Claims: every numbered claim in `claims.md` with its kind, then `true`, `false`,
       or `not verified`, and the finding or evidence, from the pass-one Claims lists as
       revised by later verdicts. A claim no list covers is `not verified`, and so is a claim
       the stage 4 entry records as `not assessed`, with the reason "not assessed". A
       `verification` claim is `true, reproduced` only when the audit reproduced the
       stated result itself; `false, contradicted` only with counter-evidence; else
       `not verified, not reproduced`, with the reason. A claim that a
       `## Claims challenged` line overturned shows both verdicts and is `contested`.
       Say once, in this section, that reproducing a stated result does not show that
       the build session ran its stated check.
   11. Coverage, from `stages.json`, `audit-brief.md`, and the check files:
       - each handoff claims file: its path, its hash, and whether `handoff.sh check`
         validated it (from the brief's Handoff section);
       - the `work-items.sh` result from step 8 below: `work-items: ok`, the error
         lines and that the file is not ready for an adapter, or that it was not
         validated and why;
       - each stage run, not applicable, failed, or swapped, and why;
       - every swap by name, with the requested model for each agent (the report says
         "requested", not "used");
       - at low tier, that one auditor covered the ticket, tests, and work-item hygiene;
       - failed scopes and scopes not run because the budget expired, naming the last
         byte offset of a digest that ended `status: failed at byte <offset>`;
       - each `decision` or `scope` claim recorded as `not assessed` (the pass-one
         report has no entry for it), and each entry recorded as `not challenged`
         because pass two wrote no line for it;
       - each bundle whose base refresh was declined, from the brief's "base: local
         ref, refresh declined" line;
       - stage 6: whether the mandatory ids were requested in batches (`batched`) and,
         from `missing_positions`, every mandatory id left without a position (those
         Codex was asked for and left unanswered after the follow-up, and those of a
         fallback batch that failed); a partial swap (the fallback answering the ids
         Codex was not asked for) is listed as a swap with its scope;
       - every file stage 2 split by byte range, from the stage 2 entry's `split_files`:
         the source, the path, its size, each range, and the chunk id (`digest-N`) that
         covered it with that chunk's status;
       - unanswered questions and departures from the stage plan;
       - map corrections not applied, from `ledger/5.md`;
       - when exports were used, that the forge was not queried;
       - ignored-file differences accepted by each read-only check, and what the check
         does not detect: an ignored file replaced with one of the same size and a
         restored modification time, changes inside `.git/` other than refs, stashes,
         and config, a change to a nested repository's refs other than its HEAD, its
         stashes, or its config, a change inside a repository that sits in an ignored
         directory, such as a linked worktree, other than an entry added or removed at
         its top level, and changes outside the audited repos. When any
         `baseline/<stage>-check.md` carries the note `note mtime precision: seconds`,
         say the ignored-file comparison used whole-second times, so a same-size rewrite
         within the same second was not detected;
       - the manifest's `_test` key, when present.
   12. Usage per stage, from `usage.md`: agents run, requested models, wall-clock, and
       tokens, each labeled "task notification, subagent_tokens; scope not documented";
       Codex tokens "not reported". No total is presented as exact.

   The filled body is written to `report.body.tmp` in the run directory, not yet to
   `report.md`. Section 11 (Coverage) is filled in two passes: everything except the
   `work-items.sh` result now, and that result in step 8.

7. **Write `work-items.jsonl`** in the run directory, from the operations listed in
   section 7, one JSON object per line, in the format in
   `${CLAUDE_PLUGIN_ROOT}/skills/cca/work-items.md`. With no operations, the file is
   written empty.

8. **Validate it.** Run
   `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/work-items.sh check work-items.jsonl report.body.tmp claims.md`
   from the run directory, with `${CLAUDE_PLUGIN_ROOT}` resolved as the preamble says.
   Put the result in the Coverage section of `report.body.tmp`, a text change that
   alters no item:
   - exit 0: `work-items: ok`;
   - exit 1: the file is kept, every error line is listed, and the file is marked not
     ready for an adapter;
   - exit 2: the file is kept, and Coverage says it was not validated, with the
     script's message (`work-items: jq not found` when `jq` is missing).

   Fix nothing in the report to satisfy the validator; a mismatch is reported, not
   hidden.

9. **Revision line.** With Bash, compute the hash over the exact bytes of
   `report.body.tmp` and assemble `report.md` with a shell redirect, so no byte is
   re-serialized:

   ```
   hex=$(sha256sum report.body.tmp | cut -d' ' -f1)
   { printf 'revision: sha256:%s\n' "$hex"; cat report.body.tmp; } > report.md
   ```

   The Write tool is never used for `report.md`, and the file is not edited after this
   step. The revision is the sha-256 of every byte after the first LF; stage 9
   recomputes it with `tail -n +2 report.md | sha256sum`. Remove `report.body.tmp`.

10. **Write `claims-verdicts.md`,** in the format below, carrying the revision `<hex>`
    from step 9. Write it with the Write tool; it is not hashed.

11. **Read-only check.** Run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and write
    `baseline/8-check.md`. If it fails, the run is `blocked`: the report stays on disk,
    and step 14 prints the reason and `blocked` instead of a verdict.

12. **Write the stage 8 entry last,** once the check has passed, per the preamble:
    status `complete`, the recorded input hashes above, outputs
    `["report.md", "claims-verdicts.md", "work-items.jsonl"]`.

13. **Update `${CLAUDE_PLUGIN_DATA}/runs.json`:** set this run's `state` to the terminal
    state, writing a temporary file beside it and renaming it.

14. **Print and stop:** the absolute path of `report.md`, the verdict, and the terminal
    state. For `partial`, also print `/cca:resume <run-id>`. Nothing runs after this;
    `/cca:act` is a separate command.

## `claims-verdicts.md`

The return trip to the build session. Step 10 writes it from the report's section 10 and
the claims files, in this format:

```
# Claims verdicts: <run-id>

report revision: sha256:<hex>
generated: <time>

Apply a line only when its file hash and claim text match what you hold. `false` lines
are corrections: the statement is contradicted by the cited evidence. `not verified` lines
on verification claims are recheck requests: the audit could not reproduce the check, which
is not evidence the statement is wrong. `contested` lines need a person to decide.

## <claims file absolute path> (handoff | prose), hash <git hash-object --no-filters>

- claim <n> [<kind>] <source file>:<line> <handoff ref or ->: <true | false | not verified | contested>; finding: <C<n>, ... or none>; evidence: <pointer>
  ticket: <the claim's ticket id, or none>
  text: <the claim's text as in claims.md>
  correction: <text or none>
```

- The header text and the intro paragraph are written as shown.
- One entry per `claim` line of `claims.md`: a main line and three sub-lines indented two
  spaces, `ticket:`, `text:`, and `correction:`. A sub-line holds the whole rest of its
  line, so a claim's text or a correction may contain `; `. Entries are grouped by claims
  file, in claim order. The file's hash is the one stage 1 recorded for that claims file
  in the `inputs` of its `stages.json` entry, so it names the bytes the audit read, not
  the file as it is now. `other` sentences are not listed.
- `ticket` is the ticket the claim is about, so a build session can find what it wrote
  about that ticket. For a handoff claim, it is the ticket field `handoff.sh claims`
  printed; for a prose claim, the ticket stage 1 tagged it with, an export written as its
  `id`; else `none`. A file written by 0.2.0 has no `ticket:` sub-line.
- `(handoff)` for a file `handoff.sh detect` accepted, else `(prose)`. The handoff ref
  is the one in the claim line, or `-` for a prose claim.
- `contested` is used when the auditor's and the adversary's verdicts differ; both are
  given in the report's Claims section. Otherwise the verdict is the one in the report's
  section 10. For a `verification` claim, `true` means reproduced and not overturned.
- `correction` is the corrected text for a `false` line, drawn from the cited evidence;
  `none` for every other verdict. The text names no model, agent, or tool.
- `evidence` points to the report item (`C<n>`) or the evidence the verdict rests on.
