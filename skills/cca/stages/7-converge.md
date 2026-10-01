# Stage 7: converge (late adversary, `cca:merger`, then the orchestrator)

The orchestrator's procedure for stage 7. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and the
run's `common.md` apply throughout.

Inputs: `ledger/5.md`, `ledger/6.md`, `audit-brief.md`, `common.md`.

Outputs: `late/adversary.md` (medium and high), `ledger/7.md`, `gate.md`,
`converged/<group>.md` (split mode only), and `converged.md`.

## Steps

1. **Check the budget** first. If it has expired, stage 7 does not start and gets no
   entry; go to stage 8. Otherwise write the stage 7 entry as `running` with its input
   hashes. Check the budget again before every launch in this stage; once it has
   expired, launch nothing more, let running agents finish, and go to stage 8.

2. **Late adversary, at medium and high only.** Launch one fresh `cca:adversary` with
   the Agent tool, in the background, never as a fork, with its `model` from `--models`
   or the manifest, else the agent's default. The prompt holds the paths of
   `audit-brief.md`, `common.md`, `ledger/5.md`, and `ledger/6.md`, the output path
   `late/adversary.md`, and the list of ids to challenge:
   - every late addition: `origin: pass2`, `origin: topup`, and `origin: codex`;
   - every finding the second opinion asked to restore.

   For each it gives a verdict (`survives`, `downgraded`, `reworded`, or `dropped`) with
   evidence, reading the stage 5 verdicts in `ledger/5.md`. Anything it raises itself
   takes `origin: late` and an id `L<n>`, and stays provisional: there is no further
   round. It ends with `runs:` and `status: complete`.

   Failure: an error, a missing file, no `status: complete`, or a listed id without a
   verdict. A `_test.fail` entry with `role: adversary` and scope `late` or `any`
   applies. Ladder: first failure, relaunch on the same model; second, relaunch with
   `model: fable`, recorded as a swap; third, the late adversary scope failed: record it
   in the stage entry as a failed scope with its coverage loss (every id it would have
   challenged), every late addition stays provisional, and the merger still runs.

3. **Write `ledger/7.md` once.** At medium and high, one section per challenged id:

   ```
   ## <finding id>
   - verdict: <survives | downgraded | reworded | dropped> by cca:adversary (late, model <requested model>)
   - reason: <text>
   - evidence: <as cited>
   ```

   then its own additions in the `common.md` schema with `origin: late`, each marked
   provisional. At low, write one line: "No late adversary at low tier; late additions
   stay provisional." If the late adversary failed, say so and list the ids it would
   have challenged.

4. **Review gate.** A finding counts when a reviewer other than its author has
   challenged it, and both a Claude adversary and the second opinion have seen it, in
   any role. Compute the gate for every ledger id from the ledger files:

   | Origin | Counts when | Otherwise |
   |---|---|---|
   | `pass1` (with barrier top-up findings) | it has a stage 5 verdict and stage 6 saw it | provisional |
   | `pass2` | stage 6 saw it and the late adversary gave a verdict | provisional (always at low) |
   | `topup` | stage 6 saw it and the late adversary gave a verdict | provisional (always at low) |
   | `codex` | the late adversary gave a verdict | provisional (always at low) |
   | `late` | never | provisional |

   "Stage 6 saw it" means stage 6 is `complete` and the finding was in the request. When
   stage 6 failed, no finding passes the gate on its account. A finding whose stage 5
   scope failed has no stage 5 verdict. A `dropped` verdict still counts as a challenge;
   the disposition decides what happens to it.

   Write `gate.md`: one line per ledger id, `<id>: counts | provisional; <reason>`.

5. **Choose normal or split mode.** Add the byte sizes of `ledger/5.md`, `ledger/6.md`,
   and `ledger/7.md` (`wc -c`). Over 450,000 bytes, or over `_test.ledger_split_bytes`
   when set, use split mode (step 7); otherwise normal mode (step 6).

6. **Normal mode.** Launch one `cca:merger` with the Agent tool, in the background,
   never as a fork, with its `model` from `--models` or the manifest, else the agent's
   default. The prompt holds the paths of `audit-brief.md`, `common.md`, `ledger/5.md`,
   `ledger/6.md`, `ledger/7.md`, and `gate.md` (with the instruction to take each item's
   gate from it), the path of any complete earlier `converged.md` for the same ledger
   files, and the output path `converged.md`. The merger reads the ledger files and
   never edits them. It writes one item per distinct defect:

   ```
   ## C<n>: <title>
   - absorbs: <every ledger id this item takes in>
   - sources: <each id with its origin, author, and model>
   - gate: counts | provisional
   - disposition: agreed | contested | dismissed
   - severity: <the agreed severity, for agreed>
   - positions: <for contested, each reviewer's severity, label, verdict, and evidence pointer (ledger file and section)>
   - reason: <for dismissed, why it was dropped and not restored>
   - tickets: <work-item impact>
   - recommended change: <repo, path, change>
   ```

   Dispositions: `agreed`, the reviewers who saw it accept it at one severity;
   `contested`, they disagree on existence or severity, and every position is kept with
   its evidence, with no side picked; `dismissed`, dropped and not restored, kept with
   the reason. An item's gate is `counts` when any id it absorbs counts in `gate.md`.
   Ids are `C<n>` in ledger order and are stable once written: a relaunched merger or
   the orchestrator's own merge keeps the ids of any complete earlier `converged.md` for
   the same ledger files. The file ends with `status: complete`.

7. **Split mode.** One `cca:merger` per group, then one final merger:
   1. Assign each ledger id to a group: the scope in its id for `pass1`, `pass2`, and
      `topup` findings; for `codex` and `late` findings, the group whose files their
      recommended change or evidence names, else `ungrouped`.
   2. Launch one merger per group, prompt: the paths of `audit-brief.md`, `common.md`,
      the three ledger files, and `gate.md`, the group's ledger ids, and the output path
      `converged/<group>.md`. Each item holds: the item, sources, each position's
      severity and label, disposition, gate, absorbed ledger ids, and a ledger section
      pointer. No `C<n>` ids yet. Each file ends with `status: complete`.
   3. Launch the final merger with the paths of `audit-brief.md`, `common.md`, every
      `converged/<group>.md`, the ledger files, and `gate.md`, and the output path
      `converged.md`. It assigns `C<n>` ids, merges
      items that are the same defect across groups, and opens a ledger section only to
      settle a suspected cross-group duplicate.

8. **The orchestrator checks the merge against the ledger:**
   - every finding id in `ledger/5.md`, `ledger/6.md`, and `ledger/7.md` appears in the
     `absorbs` list of exactly one item;
   - no item's severity differs from its source finding's severity without a cited
     verdict (a pass-two `downgraded`, a second-opinion recalibration, or a late
     verdict) that sets it;
   - each item's gate matches `gate.md`;
   - every `contested` item keeps each position with its evidence.

   A check that fails counts as a merger failure.

9. **Merger failure.** A merger failed when it returned an error, its file lacks
   `status: complete`, or the check in step 8 fails. A `_test.fail` entry with
   `role: merger` and scope `any`, `converged`, or the group applies. Ladder: first
   failure, the orchestrator merges itself, following step 6 or 7 and writing the same
   files, recorded as a swap (role merger, from `cca:merger` to the orchestrator); a
   second failure (the orchestrator's merge fails the check) fails stage 7, and stage 8
   writes the report from the ledger.

10. **Stage completion.** Stage 7 is `complete` when `ledger/7.md`, `gate.md`, and
    `converged.md` are written and pass the check, and the late adversary (at medium and
    high) succeeded; otherwise `failed`, and the run will end `partial`. A failed late
    adversary scope fails the stage but does not discard a `converged.md` that passed
    the check: stage 8 uses it.

11. **Read-only check.** Run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and write
    `baseline/7-check.md`.

12. **Write the stage 7 entry last,** once the check has passed, per the preamble:
    status, inputs, outputs, agents with tokens labeled "task notification,
    subagent_tokens; scope not documented", swaps, the mode (normal or split) with the
    byte total and the threshold used, `"converged_check": "pass"` or `"fail"` from
    step 8 (absent when no merge was attempted), failed scopes with coverage loss, and
    each `_test` fault applied.
