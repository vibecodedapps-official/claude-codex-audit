# Stage 8: report (orchestrator)

The orchestrator's procedure for stage 8. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and the
run's `common.md` apply. The report's section headings and layout are in
`${CLAUDE_PLUGIN_ROOT}/skills/cca/report.md`; this file says where each part comes from and how the verdict is
decided.

Stage 8 always runs, even after a failed stage or an expired budget. It does not run
when the run is `blocked`: then no report is written, the reason is printed, and every
finished stage file is kept.

Inputs: `converged.md`, `gate.md`, `ledger/5.md`, `ledger/6.md`, `ledger/7.md`, the
`pass1/` and `pass2/` files (Claims and Verified OK lists, attacked Verified OK lists),
`claims.md`, `audit-brief.md`, `manifest.json`, `stages.json`, `usage.md`, and
`baseline/*-check.md`, whichever exist.

Recorded input hashes (`git hash-object --no-filters`): `converged.md`, `gate.md`, the
ledger files, `claims.md`, `audit-brief.md`, `manifest.json`, and each `pass1/` and
`pass2/` file read, whichever exist. `stages.json` and `usage.md` are read but not
hashed: they are run state, not inputs, and stage 8's own entry is written into
`stages.json`, so a hash of it could never match on resume.

Outputs: `report.md`.

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

3. **Decide the terminal state.** `reported` when every applicable stage is `complete`
   in `stages.json`. `partial` when any stage failed or the budget expired. (`blocked`
   never reaches this step.)

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
      disposition, item id (`C<n>`), and absorbed ledger ids. A
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
      agent, or tool.
   8. Decisions: each with the recommendation, the reason, and a reversibility class,
      `reversible`, `hard to reverse`, or `contract change`. A named owner only for
      `hard to reverse` and `contract change`, and only when the tickets or threads name
      one; else "owner not recorded".
   9. Live checks: for each finding with a live check, its id, the query, where it
      runs, and the severity each result implies; each check the user did not approve
      is listed here. In 0.1 a result is not fed back into a run: the user reruns the
      audit or acts on the finding by hand.
   10. Claims: every numbered claim in `claims.md` with `true`, `false`, or
       `not verified`, and the finding or evidence, from the pass-one Claims lists as
       revised by later verdicts. A claim no list covers is `not verified`.
   11. Coverage, from `stages.json`, `audit-brief.md`, and the check files:
       - each stage run, not applicable, failed, or swapped, and why;
       - every swap by name, with the requested model for each agent (the report says
         "requested", not "used");
       - at low tier, that one auditor covered the ticket, tests, and work-item hygiene;
       - failed scopes and scopes not run because the budget expired;
       - unanswered questions and departures from the stage plan;
       - map corrections not applied, from `ledger/5.md`;
       - when exports were used, that the forge was not queried;
       - ignored-file differences accepted by each read-only check, and what the check
         does not detect: an ignored file replaced with one of the same size and a
         restored modification time, changes inside `.git/` other than refs, stashes,
         and config, and changes outside the audited repos;
       - the manifest's `_test` key, when present.
   12. Usage per stage, from `usage.md`: agents run, requested models, wall-clock, and
       tokens, each labeled "task notification, subagent_tokens; scope not documented";
       Codex tokens "not reported". No total is presented as exact.

7. **Revision line.** Write the filled body to `report.body.tmp` in the run directory.
   Then, with Bash, compute the hash over its exact bytes and assemble `report.md` with
   a shell redirect, so no byte is re-serialized:

   ```
   hex=$(sha256sum report.body.tmp | cut -d' ' -f1)
   { printf 'revision: sha256:%s\n' "$hex"; cat report.body.tmp; } > report.md
   ```

   The Write tool is never used for `report.md`, and the file is not edited after this
   step. The revision is the sha-256 of every byte after the first LF; stage 9
   recomputes it with `tail -n +2 report.md | sha256sum`. Remove `report.body.tmp`.

8. **Read-only check.** Run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and write
   `baseline/8-check.md`. If it fails, the run is `blocked`: the report stays on disk,
   and step 11 prints the reason and `blocked` instead of a verdict.

9. **Write the stage 8 entry last,** once the check has passed, per the preamble:
   status `complete`, the recorded input hashes above, outputs `["report.md"]`.

10. **Update `${CLAUDE_PLUGIN_DATA}/runs.json`:** set this run's `state` to the terminal
    state, writing a temporary file beside it and renaming it.

11. **Print and stop:** the absolute path of `report.md`, the verdict, and the terminal
    state. For `partial`, also print `/cca:resume <run-id>`. Nothing runs after this;
    `/cca:act` is a separate command.
