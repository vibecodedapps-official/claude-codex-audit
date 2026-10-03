# Stage 5: pass two (`cca:adversary`, one per pass-one report)

The orchestrator's procedure for stage 5. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and the
run's `common.md` apply throughout; this file does not restate the finding schema or
the agent output contract.

Inputs: `audit-brief.md`, `common.md`, every complete `pass1/<scope>.md`, and the
`domain/*-map.md` files.

Outputs: `pass2/<scope>.md` per pass-one report, `domain/<source>-map.r2.md` per
corrected map, `pass2/<group>-topup.md` per map-correction top-up, `ledger/inventory.txt`,
and `ledger/5.md`.

## Steps

1. **Write the stage 5 entry as `running`** when the first scope clears the barrier in
   stage 4, with its input hashes.

2. **Launch one adversary per pass-one report as soon as its scope clears the
   barrier.** Stage 5 does not wait for other scopes. Each adversary is a new
   `cca:adversary` launched with the Agent tool, in the background, never as a fork and
   never a continuation of an earlier agent, so it does not inherit pass one's framing.
   Its `model` parameter comes from `--models` or the manifest's `models` key for
   `adversary`, else the agent's default. The prompt holds only:
   - the path of `audit-brief.md`;
   - the path of `common.md`;
   - the path of the one pass-one report, `pass1/<scope>.md`;
   - the output path, `pass2/<scope>.md`;
   - the scope's question ids and text;
   - the Verified OK rule for the tier:

     | Tier | Verified OK items to attack |
     |---|---|
     | low | none |
     | medium | up to 5 per report, the ones the adversary judges riskiest |
     | high | all |

   A failed pass-one scope has no report and gets no adversary; its coverage loss is
   already recorded.

3. **What each adversary writes**, in the shapes `common.md` gives, which the
   orchestrator checks on completion:
   - a verdict for every finding in the report, including any top-up section, one of
     `survives`, `downgraded`, `reworded`, or `dropped`, each with evidence, after
     opening every citation, looking for counter-evidence, and challenging severity
     and label;
   - `## Verified OK challenged`, one line per item it attacked with the result; stage
     8 marks those items `challenged` and all others `not challenged`;
   - `## Coverage gaps`;
   - late additions: new findings in the `common.md` schema, each with
     `origin: pass2` and an id `<scope>-P<n>`;
   - `## Map corrections`: map file, line, what is wrong, and the source quote at its
     sha that shows it; or `none`;
   - at every tier, `## Claims challenged`, `## Decisions challenged`, and
     `## Scope challenged`, in the shapes `common.md` gives;
   - `runs:`, `consumed:`, and a last line `status: complete`.

   A report with a finding that has no verdict is incomplete and counts as a failure. So
   is a report that misses a `## Claims challenged` line: every `verification` claim the
   pass-one report marks true needs one. Every entry of the pass-one `## Decisions` and
   `## Scope` also needs a line under `## Decisions challenged` and `## Scope challenged`,
   but a missing line or heading there does not fail the scope: record each such entry as
   `not challenged` in the stage 5 entry, and stage 8 shows the pass-one entry with
   that mark. Challenge lines and the entries they challenge are report items, not
   findings; they do not go into `ledger/5.md`.

4. **Failure.** The adversary failed when it returned an error, its file is missing, its
   last line is not `status: complete`, a finding lacks a verdict, or a `## Claims
   challenged` line is missing (step 3). A `_test.fail` entry with `role: adversary` and
   this scope or `any` makes the scope's first `times` completions failures. Ladder: first failure,
   relaunch on the same model; second, relaunch with `model: fable`, recorded as a swap;
   third, the scope failed and its findings have no pass-two verdict. Record tokens and
   duration per completion with the label "task notification, subagent_tokens; scope not
   documented". Check the budget before every launch; after it expires, launch nothing
   and record each scope not run.

5. **Map corrections**, once every pass-two adversary has finished:
   1. Collect every `map corrections` entry. For each, open the cited source quote at its
      pinned sha. An entry whose quote does not match the source is rejected and listed
      under "Map corrections not applied" (step 6).
   2. For each map with an accepted correction, write `domain/<source>-map.r2.md`: a
      header `# Corrections` listing each correction (line, original text, corrected
      text, the adversary report that raised it, the source quote), then the map's full
      text with the corrected lines replaced. The original `domain/<source>-map.md` is
      not changed.
   3. For every scope whose pass-one `consumed:` list names a corrected map, at any
      hash, enqueue a top-up `cca:auditor`, its prompt saying "mode: top-up after a map
      correction", with the paths of `audit-brief.md`,
      `common.md`, `scope/<scope>.md`, and the corrected map, the corrected lines, and
      the output path `pass2/<scope>-topup.md`, with this instruction: apply the
      corrected answers to the scope's files; tag every finding `origin: topup` with an
      id `<scope>-T<n>`; list `runs:` and `consumed:`; end with `status: complete`. The
      completed `pass1/` files do not change.
   4. A top-up failure follows the auditor ladder with scope id `<scope>-maptopup` (a
      `_test.fail` entry with `role: auditor` and that id or `any` applies). A failed
      top-up is coverage loss and makes stage 5 `failed`.
   5. One round only. A map correction that a top-up raises is not reissued; list it
      under "Map corrections not applied" with the reason "one round". That list lives
      in `ledger/5.md` and the stage 5 entry, not in `audit-brief.md`: the brief is a
      stage 1 output whose hash every later stage records, so editing it would make
      resume rerun every stage.
   6. Every top-up finishes before stage 6 starts. Top-up findings are late additions
      and are not challenged in this stage.

6. **Write `ledger/5.md` once**, after every adversary and every top-up has finished or
   failed. It holds every finding ever raised in stages 4 and 5; nothing is left out,
   including dropped findings, except blocks of a failed file that cannot be parsed,
   which its `## Failed outputs` line counts. The script writes the finding sections; the orchestrator
   never copies a finding by hand.
   1. Write `ledger/inventory.txt` with printf, one space-separated record per line, paths
      relative to the run directory (the grammar is in `ledger.sh`'s header):

      ```
      pass1 <scope> <path or -> <requested model or -> complete|failed
      pass2 <scope> <path or -> <requested model or -> complete|failed|not-run
      topup <scope> <path or -> <requested model or -> complete|failed
      ```

      `pass1` names the current `pass1/<scope>.md`, never a `.pre-topup.md`; `pass2` has
      one record per complete pass-one scope (a failed pass-one scope has no pass-two
      record); `topup` one per `pass2/<scope>-topup.md` attempted. A `failed` record
      whose file does not exist uses `-` for the path (and for the model when none was
      requested). Every `.md` file under `pass1/` and `pass2/` except `*.pre-topup.md`
      gets exactly one record, in scope order.
   2. Run `mkdir -p <run dir>/tmp`, then `sh
      ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh build5 <run dir> >
      <run dir>/tmp/ledger5.md`. Never redirect it into `ledger/5.md`: a failed build
      (exit 1, no output) must leave no `ledger/5.md`, since stage 8 prefers the ledger
      files when they exist. It writes, in inventory scope order, then pass-one order, then pass-two additions,
      then top-up findings, one section per finding id:

      ```
      ## <finding id>
      - origin: pass1 | pass2 | topup
      - author: <agent type>, model <requested model>, file <path>
      ### Original
      <the finding's full text, verbatim>
      ### Pass-two verdicts
      - <verdict> by cca:adversary (model <requested model>) in <pass2 path>: <reason>; evidence: <as cited>
        (`- none` when the finding has no verdict)
      ### State after pass two
      <severity>, <label>, <survives | downgraded | reworded | dropped | no verdict: late addition | no verdict: scope failed | no verdict: not run, budget expired | no verdict: output failed>
      ```

      After the finding sections it writes per scope its attacked Verified OK items with
      results and its coverage gaps, then, when a record is `failed`, `## Failed outputs`
      listing those files (`- <path>`, `- <path> (<n> blocks not parsed)`, or `- <kind>
      <scope>: no file` for a record with `-` as its path). Every well-formed finding of a
      failed file is kept in the finding sections with the state `no verdict: output
      failed` and no verdict credit; a block that cannot be parsed is only counted. Each of these parts sits under its own `## ` heading that is
      not a finding id, so that the last finding section, which runs to the next `## `
      line, never takes it in: `## Verified OK challenged: <scope>`, `## Coverage gaps:
      <scope>`, `## Failed outputs`.
   3. Append the two map-correction sections yourself to `tmp/ledger5.md`, after the
      script's output, always both and in this order: `## Map corrections applied` (each `.r2.md` file and its
      lines) and `## Map corrections not applied` (each rejected or one-round correction
      with its reason). An empty one has the body `none`. They are judged, so the script
      does not write them, and `check --through 5` compares the text before the first
      `## Map corrections applied` line with the script's output.
   4. Move it into place with `mv -f <run dir>/tmp/ledger5.md <run dir>/ledger/5.md`,
      then run `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh check <run dir>
      --through 5 > <run dir>/tmp/check5.txt`, and read only `wc -l` of that file and its
      first 50 lines (`head -n 50`), never the whole output. A nonzero exit from `build5`
      (sub-step 2) or from the check means problem lines starting `ledger: `. Fix the inventory when it is the cause (a missing or extra
      record, a wrong status or path) and rerun sub-steps 2 to 4 once; a second nonzero
      exit, or a problem in a pass-one or pass-two file rather than the inventory, fails
      stage 5 (the run will end `partial`). When `build5` never succeeded, nothing was
      moved and `ledger/5.md` does not exist; record the ledger build as failed in the
      stage 5 entry (`"ledger_build": "failed"`). Remove `<run dir>/tmp/ledger5.md` when
      done.

7. **Stage completion.** Stage 5 is `complete` when every pass-one report got a complete
   pass two, every top-up succeeded, and `ledger/5.md` is written and passes
   `check --through 5`; otherwise `failed`, and the run will end `partial`. When the
   budget expired, still write the inventory and `ledger/5.md` from what is on disk
   (step 6, through the same temp file and move), so stage 8 can use it.

8. **Read-only check.** Run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and write
   `baseline/5-check.md`.

9. **Write the stage 5 entry last,** once the check has passed, per the preamble:
   status, inputs, outputs (every `pass2/` file, each `.r2.md`, `ledger/inventory.txt` with its hash, and
   `ledger/5.md`),
   agents, swaps, failed scopes, map corrections not applied, each decision or scope
   entry recorded as `not challenged`, and each `_test` fault applied.
