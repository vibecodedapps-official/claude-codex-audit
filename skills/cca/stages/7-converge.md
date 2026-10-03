# Stage 7: converge (late adversary, `cca:merger`, then the orchestrator)

The orchestrator's procedure for stage 7. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and the
run's `common.md` apply throughout.

Inputs: `ledger/5.md`, `ledger/6.md`, `audit-brief.md`, `common.md`, and the live inputs
`live/findings.md`, `live/claims.md`, and each `live/carried/<id>.md` that
`live/findings.md` names (`${CLAUDE_PLUGIN_ROOT}/skills/cca/live.md`), each recorded in
the stage entry with its hash, or `absent` when it does not exist. They exist only on a
run resumed with live results; a claim-only result leaves `live/findings.md` absent.

Outputs: `late/adversary.md` (medium and high, and low when `live/` lists ids),
`ledger/7.md`, `gate.md`,
`ledger/slices/<group>.md` and `converged/<group>.md` (split mode only; a group split
by size has `<group>-<k>` parts), and `converged.md`.

## Steps

1. **Check the budget** first. If it has expired, stage 7 does not start and gets no
   entry; go to stage 8. Otherwise write the stage 7 entry as `running` with its input
   hashes. Check the budget again before every launch in this stage; once it has
   expired, launch nothing more, let running agents finish, and go to stage 8.

2. **Late adversary, at medium and high, and at low when `live/` lists ids.** At low it
   runs for those live ids only (below). Launch one fresh `cca:adversary` with
   the Agent tool, in the background, never as a fork, with its `model` from `--models`
   or the manifest, else the agent's default. The prompt holds the paths of
   `audit-brief.md`, `common.md`, `ledger/5.md`, and `ledger/6.md`, the output path
   `late/adversary.md`, and the path of the list of ids to challenge, which the script
   builds, so no id is typed into the prompt: `mkdir -p <run dir>/tmp`, then `sh
   ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh late-ids <run dir> --tier <tier>
   --stage6 <complete|failed> > <run dir>/tmp/late-ids.txt` (`--stage6` is stage 6's
   state, as `gate` takes it; a nonzero exit fails stage 7). It holds:
   - every late addition: `origin: pass2`, `origin: topup`, and `origin: codex`;
   - every finding the second opinion asked to restore, at medium and high;
   - every finding `live/findings.md` lists, with its live result and derivation (a
     carried `X<n>` or `L<n>` is read from its `live/carried/<id>.md`, the ledger may no
     longer hold it); at low, these are the only ids, and the prompt also names
     `live/findings.md` and the carried files; at every tier, the prompt names each
     result copy of `live/findings.md` and `live/claims.md` (`live.md`, "Derivation"),
     when there is any, for the adversary to read in full;
   - under `## Claims challenged`, every claim `live/claims.md` derives
     `true, reproduced`, which the adversary reproduces or overturns like any claim the
     report marks true (`common.md`, "Pass-two verdicts").

   For each id it gives one verdict block, `### verdict on <id>: <verdict>` (`survives`,
   `downgraded`, `reworded`, or `dropped`), with `- severity:`, `- label:`, `- evidence:`,
   and `- reason:` lines, reading the stage 5 verdicts in `ledger/5.md`. Anything it
   raises itself is written as `### L<n>: <title>` with `origin: late` and an id `L<n>`,
   numbered after the highest carried `L<n>` (`live/carried/L<n>.md`; a carried id is
   reserved), and stays provisional: there is no
   further round. It ends with `runs:` and `status: complete`.

   Failure: an error, a missing file, no `status: complete`, a listed id without a
   verdict, or a listed live true claim without a `## Claims challenged` line. A
   `_test.fail` entry with `role: adversary` and scope `late` or `any` applies. Ladder:
   first failure, relaunch on the same model; second, relaunch with `model: fable`,
   recorded as a swap; third, the late adversary scope failed: record it in the stage
   entry as a failed scope with its coverage loss (every id it would have challenged),
   every late addition stays provisional, and the merger still runs.

3. **Write `ledger/7.md` once.** At medium and high, and at low for the live ids, one
   section per challenged id:

   ```
   ## <finding id>
   - verdict: <survives | downgraded | reworded | dropped> by cca:adversary (late, model <requested model>)
   - reason: <text>
   - evidence: <as cited>
   ```

   then its own additions in the `common.md` schema with `origin: late`, each marked
   provisional. At low, write one line: "No late adversary at low tier; late additions
   stay provisional." When `live/` lists ids at low, that line comes first and the
   sections of the live ids follow it. If the late adversary failed, say so and list the
   ids it would have challenged, under a `## Late adversary failed` heading (so no finding
   section runs on into it).

4. **Review gate.** A finding counts when a reviewer other than its author has
   challenged it, and the second opinion gave a position on it when it is medium or
   above, or acknowledged it when it is low or note (the rows below). Write `gate.md`
   with `mkdir -p <run dir>/tmp`, then `sh
   ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh gate <run dir> --tier <tier>
   --stage6 complete|failed --late complete|failed|not-run > <run dir>/tmp/gate.md`, with
   the stage 6 status and the late adversary's outcome (`not-run` when none ran). Only on
   exit 0, run `mv -f <run dir>/tmp/gate.md <run dir>/gate.md`. A nonzero exit moves
   nothing, so no `gate.md` exists, and fails stage 7 (stage 8 then gates from the
   ledger without reusing `gate.md`, its fallback path 2). Remove `tmp/gate.md` when
   done. The script writes one line per ledger id, per `### X<n>:` and `### L<n>:` addition, and
   per carried id, `<id>: counts | provisional; <reason>`. The rules it applies:

   | Origin | Counts when | Otherwise |
   |---|---|---|
   | `pass1` (with barrier top-up findings) | it has a stage 5 verdict from a complete pass two, stage 6 is `complete`, and, at severity medium or above (state after pass two), stage 6 gave it a position | provisional |
   | `pass2`, `topup` | stage 6 is `complete`, the late adversary gave a verdict, and, at medium or above, stage 6 gave it a position | provisional (always at low, unless the finding is in `live/findings.md` and its live review completed) |
   | `codex` | the late adversary gave a verdict | provisional (always at low, unless the finding is in `live/findings.md` and its live review completed) |
   | `late` | never, except a carried `L<n>` under the live rule below | provisional |

   Medium rule: a finding at medium or above needs a stage 6 position; at low or note,
   stage 6 having `complete` and requested it (the acknowledgment) is enough, and the
   reason says so. A late verdict replaces the stage 5 verdict for `pass2` and `topup`
   rows. When stage 6 failed, no finding passes the gate on its account. A finding whose
   stage 5 scope failed has no stage 5 verdict. A `dropped` verdict still counts as a
   challenge; the disposition decides what happens to it.

   Live rule, added to every row: a finding in `live/findings.md` counts only when stage
   6 completed with a position on it and the late adversary gave it a verdict, and it
   still needs the rest of its own row; otherwise it is `provisional`, with the reason
   `live result not yet reviewed`, checked first. A carried `X<n>` follows the `codex`
   row plus the live rule; a carried `L<n>` counts under the live rule alone, since both a
   second opinion and a fresh Claude adversary other than its author then challenged it
   (`counts; live review completed`). A carried id that `live/findings.md` does not list
   is not in the universe. At low, a live-reviewed `P`, `T`, or carried `X` finding uses
   the reviews it actually got.

   The reasons are exactly these strings, in precedence order for a provisional id (live,
   stage 6 failed, low tier, no verdict, medium without position):
   - `counts; stage 5 verdict, stage 6 position`
   - `counts; stage 5 verdict, stage 6 acknowledged (low or note)`
   - `counts; late verdict, stage 6 position`
   - `counts; late verdict, stage 6 acknowledged (low or note)`
   - `counts; late verdict` (a `codex` finding)
   - `counts; live review completed`
   - `provisional; live result not yet reviewed`
   - `provisional; stage 6 failed`
   - `provisional; no stage 5 verdict`
   - `provisional; medium or above without a stage 6 position`
   - `provisional; late addition at low tier`
   - `provisional; no late verdict`
   - `provisional; late finding`

5. **Choose normal or split mode.** Add the byte sizes of `ledger/5.md`, `ledger/6.md`,
   and `ledger/7.md`, `live/findings.md`, and every `live/carried/<id>.md` (`wc -c`;
   the live files count when they exist), and record the total with them in the stage
   entry. Over 450,000 bytes, or over `_test.ledger_split_bytes`
   when set, use split mode (step 7); otherwise normal mode (step 6).

6. **Normal mode.** Launch one `cca:merger` with the Agent tool, in the background, never
   as a fork, with its `model` from `--models` or the manifest, else the agent's default.
   The prompt holds the paths of `audit-brief.md`, `common.md`, `ledger/5.md`,
   `ledger/6.md`, `ledger/7.md`, and `gate.md` (with the instruction to take each item's
   gate from it), `live/findings.md` and each `live/carried/<id>.md` when they exist, the
   path of any complete earlier `converged.md` for the same ledger files, and the output
   path `converged.md`. The merger reads the ledger files and never edits them. It writes
   one item per distinct defect:

   ```
   ## C<n>: <title>
   - absorbs: <id>, <id>, ... (every ledger id this item takes in)
   - sources: <each id with its origin, author, and model>
   - gate: counts | provisional (the word alone, nothing after it)
   - disposition: agreed | contested | dismissed
   - severity: <the agreed severity, for agreed>
   - positions: <for contested, each reviewer's severity, label, verdict, and evidence pointer (ledger file and section)>
   - reason: <for dismissed, why it was dropped and not restored>
   - tickets: <work-item impact>
   - recommended change: <repo, path, change>
   ```

   Each item has exactly one `- absorbs:` line, ids separated by a comma and a space on
   one line, and exactly one `- gate:` line; `check` reads both by those forms.

   Dispositions: `agreed`, the reviewers who saw it accept it at one severity;
   `contested`, they disagree on existence or severity, and every position is kept with
   its evidence, with no side picked; `dismissed`, dropped and not restored, kept with the
   reason. An item's gate is `counts` when any id it absorbs counts in `gate.md`. A
   counted item's severity, label, and disposition come only from absorbed ids that
   count; a provisional duplicate never raises them (the same shape as the pending-live
   rule below). A finding in `live/findings.md` whose live review has not completed (its `gate.md` reason
   is `live result not yet reviewed`) must not set a counted item's severity, label, or
   disposition through a reviewed duplicate. Every position on it from this rerun's stages
   6 and 7 (each was given in light of the result) and its derivation are `pending
   review`: the merger lists them under the item with that mark and leaves them out of its
   severity, label, and disposition. Once the live review has completed they are ordinary
   positions, the derivation reading "live result, approved by <who> at <time>". Ids are
   `C<n>` in ledger order and are stable once written: a relaunched merger or the
   orchestrator's own merge keeps the ids of any complete earlier `converged.md` for the
   same ledger files. The file ends with `status: complete`.

7. **Split mode.** One `cca:merger` per group, then one final merger:
   1. Assign each ledger id to a group: the scope in its id for `pass1`, `pass2`, and
      `topup` findings; for `codex` and `late` findings, and for a carried `X<n>` or
      `L<n>`, the group whose files their recommended change or evidence names, else
      `ungrouped`.
   2. Write one slice per group, `ledger/slices/<group>.md`, before launching its
      merger (slices are not under `converged/`, which holds one file per group). The
      slice holds every section of `ledger/5.md`, `ledger/6.md`, and `ledger/7.md`
      whose finding id belongs to the group (step 7.1), each section prefixed with the
      pointer line `source: ledger/<n>.md, section <finding id>`, then the group's
      lines from `gate.md`. The slice also holds, for each id of the group that
      `live/findings.md` lists, that section of `live/findings.md` (the same `## <id>`
      cut as `ledger/5.md`), and, for a carried id, its whole `live/carried/<id>.md`,
      each after a pointer line `source: live/findings.md, section <id>` or
      `source: live/carried/<id>.md`. The shell writes the slice, never the model: the
      orchestrator reads none of it, and no section passes through its own output. For
      each id of the group (from the step 7.1 assignment, which covers every ledger id),
      in finding id order, and for each ledger file `<n>` (5, 6, or 7) that has a
      section for it, append by redirect the pointer line, then the section; after the
      sections, the id's `gate.md` line. The two kinds of file are cut differently.
      In `ledger/5.md`, a section is exactly `## <id>` and runs to the next `## ` line;
      `### ` lines never start or stop one, because a section embeds the finding's own
      `### <scope>-F<n>: <title>` heading under `### Original`. In `ledger/6.md` and
      `ledger/7.md`, a section starts at a line that is exactly `## <id>` or begins
      `### <id>: ` (an addition in the `common.md` schema, such as `X<n>` or `L<n>`)
      and runs to the next `## ` line or `### <word>: ` line, where `<word>` has no
      space or colon; their sections embed no finding headings, and subheadings
      without a colon stay inside. Every other part of a ledger file (the role, the
      acknowledgments, the merge verdict, the "seen, no position" list, the map
      corrections, a failure note) sits under a `## ` heading that is not a finding
      id, which ends a section and is never extracted:

      ```
      # ledger/5.md
      awk -v id=<id> '/^## /{p = ($0 == "## " id); if (p) f = 1} END{exit !f}' ledger/5.md &&
        printf 'source: ledger/5.md, section <id>\n' >> <slice> &&
        awk -v id=<id> '/^## /{p = ($0 == "## " id)} p' ledger/5.md >> <slice>
      # ledger/6.md and ledger/7.md (<n> is 6 or 7)
      awk -v id=<id> '/^## |^### [^ :]+: /{p = ($0 == "## " id || index($0, "### " id ": ") == 1); if (p) f = 1} END{exit !f}' ledger/<n>.md &&
        printf 'source: ledger/<n>.md, section <id>\n' >> <slice> &&
        awk -v id=<id> '/^## |^### [^ :]+: /{p = ($0 == "## " id || index($0, "### " id ": ") == 1)} p' ledger/<n>.md >> <slice>
      # live/findings.md, when it has a section for the id; a carried id's file whole
      awk -v id=<id> '/^## /{p = ($0 == "## " id); if (p) f = 1} END{exit !f}' live/findings.md &&
        printf 'source: live/findings.md, section <id>\n' >> <slice> &&
        awk -v id=<id> '/^## /{p = ($0 == "## " id)} p' live/findings.md >> <slice>
      [ -f live/carried/<id>.md ] &&
        printf 'source: live/carried/<id>.md\n' >> <slice> &&
        cat live/carried/<id>.md >> <slice>
      # once per id, after its sections
      awk -v id=<id> 'index($0, id ": ") == 1' gate.md >> <slice>
      ```

      When a slice exceeds 450,000
      bytes (`wc -c`), or `_test.ledger_split_bytes` when set, split the group into
      parts `<group>-1`, `<group>-2`, ... with slices `ledger/slices/<group>-1.md`,
      `ledger/slices/<group>-2.md`, ... and one merger each; the final merger treats
      them as one group. Fill the parts greedily in finding id order: build each id's
      block (its sections with their pointer lines, including its `live/findings.md`
      section and carried file, then its `gate.md` line) by the
      commands above into `<run dir>/tmp/block.md`, truncating that file first
      (`: > <run dir>/tmp/block.md`) since the commands append, measure it with `wc -c`, and append
      it to the open part with `cat` and a redirect; a part closes when adding the next
      id's block would take it over the threshold, and that id starts the next part. A
      single id whose block alone exceeds the threshold forms a part of its own, marked
      `over threshold` in its slice header (a first line written by `printf`) and in
      the stage entry. Every id lands in exactly one part, so the split ends and gives
      the same parts each time. Remove `<run dir>/tmp/block.md` when the slices are
      written.
   3. Launch one merger per group (per part), prompt: the paths of `audit-brief.md`,
      `common.md`, its slice, the three ledger files `ledger/5.md`, `ledger/6.md`, and
      `ledger/7.md` "for duplicate checks only", and the output path
      `converged/<group>.md` (or `converged/<group>-<k>.md` for a part). The merger
      reads the slice and may open a full ledger file only to settle a suspected
      duplicate inside its own slice; it records each file it opened, with the
      reason, under its own `opened:` heading, not under `runs:` (which stays as
      `common.md`'s output contract defines it). Each item holds: the item, sources,
      each position's severity and label, disposition, gate, absorbed ledger ids, and
      a ledger section pointer. No `C<n>` ids yet. Each file ends with
      `status: complete`. The `absorbs` and `gate` lines keep the form of step 6.
   4. Launch the final merger with the paths of `audit-brief.md`, `common.md`, every
      `converged/<group>.md` (every part of a split group), the ledger files, and
      `gate.md`, and the output path `converged.md`. It assigns `C<n>` ids, merges
      items that are the same defect across groups or across the parts of one group,
      and opens a ledger section only to settle a suspected cross-group or cross-part
      duplicate, recording it under `opened:` as in step 7.3. `converged.md` keeps the item
      form of step 6, one `- absorbs:` and one `- gate:` line per `## C<n>: ` item.

8. **The orchestrator checks the merge against the ledger,** after the merge, when
   `converged.md` exists. Run `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh check
   <run dir> --through 7 --tier <tier> --stage6 complete|failed --late
   complete|failed|not-run > <run dir>/tmp/check7.txt`; read only `wc -l` of that file and
   its first 50 lines (`head -n 50`), never the whole output. It checks that every
   finding id in the ledger files, every `### X<n>:` and `### L<n>:` addition, and every
   carried id sits in the `absorbs` list of exactly one item with no unknown id, that
   each item's `gate` is `counts` exactly when an absorbed id counts, that `gate.md`
   equals the `gate` output, and that no id of the `late-ids` list lacks a verdict in
   `ledger/7.md`. Then check by hand:
   - no item's severity differs from its source finding's severity without a cited
     verdict (a pass-two `downgraded`, a second-opinion recalibration, or a late
     verdict) that sets it, and a severity or label change is accepted only from a
     position that is not `pending review`: an item whose severity or label follows a
     pending one fails the check; and a counted item's severity, label, and disposition
     follow only absorbed ids that count, never a provisional duplicate;
   - every `contested` item keeps each position with its evidence.

   A check that fails, by the script or by hand, counts as a merger failure.

9. **Merger failure.** A merger failed when it returned an error, its file lacks
   `status: complete`, or the check in step 8 fails. A `_test.fail` entry with
   `role: merger` and scope `any`, `converged`, or the group applies. Ladder: first
   failure, the orchestrator merges itself, following step 6 or 7 (in split mode from
   the same slices) and writing the same files, recorded as a swap (role merger, from
   `cca:merger` to the orchestrator); a second failure (the orchestrator's merge fails
   the check) fails stage 7, and stage 8 writes the report from the ledger.

10. **Stage completion.** Stage 7 is `complete` when `ledger/7.md`, `gate.md`, and
    `converged.md` are written and pass the check (step 8, which needs `converged.md`), and the late adversary (at medium and
    high, and at low when `live/` lists ids) succeeded; otherwise `failed`, and the run
    will end `partial`. A failed late adversary scope fails the stage but does not discard
    a `converged.md` that passed the check: stage 8 uses it.

11. **Read-only check.** Run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and write
    `baseline/7-check.md`.

12. **Write the stage 7 entry last,** once the check has passed, per the preamble: status,
    inputs (with the live inputs, each by hash or `absent`), outputs, agents with tokens
    labeled "task notification, subagent_tokens; scope not documented", swaps, the mode
    (normal or split) with the byte total and the threshold used, each part marked `over
    threshold` (step 7.2), `"converged_check": "pass"` or `"fail"` from step 8 (absent
    when no merge was attempted), failed scopes with coverage loss, and each `_test` fault
    applied.
