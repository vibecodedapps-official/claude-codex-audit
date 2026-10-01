# Stage 5: pass two (`cca:adversary`, one per pass-one report)

The orchestrator's procedure for stage 5. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and the
run's `common.md` apply throughout; this file does not restate the finding schema or
the agent output contract.

Inputs: `audit-brief.md`, `common.md`, every complete `pass1/<scope>.md`, and the
`domain/*-map.md` files.

Outputs: `pass2/<scope>.md` per pass-one report, `domain/<source>-map.r2.md` per
corrected map, `pass2/<group>-topup.md` per map-correction top-up, and `ledger/5.md`.

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
   - `runs:`, `consumed:`, and a last line `status: complete`.

   A report with a finding that has no verdict is incomplete and counts as a failure.

4. **Failure.** The adversary failed when it returned an error, its file is missing, its
   last line is not `status: complete`, or a finding lacks a verdict. A `_test.fail`
   entry with `role: adversary` and this scope or `any` makes the scope's first `times`
   completions failures. Ladder: first failure, relaunch on the same model; second,
   relaunch with `model: fable`, recorded as a swap; third, the scope failed and its
   findings have no pass-two verdict. Record tokens and duration per completion with the
   label "task notification, subagent_tokens; scope not documented". Check the budget
   before every launch; after it expires, launch nothing and record each scope not run.

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
   including dropped findings. One section per finding id, in scope order, then pass-one
   order, then pass-two additions, then top-up findings:

   ```
   ## <finding id>
   - origin: pass1 | pass2 | topup
   - author: <agent type>, model <requested model>, file <path>
   ### Original
   <the finding's full text, verbatim>
   ### Pass-two verdicts
   - <verdict> by cca:adversary (model <requested model>) in <pass2 path>: <reason>; evidence: <as cited>
   ### State after pass two
   <severity>, <label>, <survives | downgraded | reworded | dropped | no verdict: late addition | no verdict: scope failed | no verdict: not run, budget expired>
   ```

   After the finding sections, add per scope its attacked Verified OK items with
   results and its coverage gaps, then a section "Map corrections applied" (each
   `.r2.md` file and its lines) and a section "Map corrections not applied" (each
   rejected or one-round correction with its reason). Each of these parts sits under
   its own `## ` heading that is not a finding id, so that the last finding section,
   which runs to the next `## ` line, never takes it in:
   `## Verified OK challenged: <scope>`, `## Coverage gaps: <scope>`,
   `## Map corrections applied`, and `## Map corrections not applied`.

7. **Stage completion.** Stage 5 is `complete` when every pass-one report got a complete
   pass two, every top-up succeeded, and `ledger/5.md` is written; otherwise `failed`,
   and the run will end `partial`. When the budget expired, still write `ledger/5.md`
   from what is on disk, so stage 8 can use it.

8. **Read-only check.** Run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and write
   `baseline/5-check.md`.

9. **Write the stage 5 entry last,** once the check has passed, per the preamble:
   status, inputs, outputs (every `pass2/` file, each `.r2.md`, and `ledger/5.md`),
   agents, swaps, failed scopes, map corrections not applied, and each `_test` fault
   applied.
