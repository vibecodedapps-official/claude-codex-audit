# Stage 4: pass one (`cca:auditor`)

The orchestrator's procedure for stage 4. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` (queue,
budget, per-role failure rule, `_test` handling, `stages.json` writing, read-only check)
and the run's `common.md` (hard rules, evidence rules, finding schema, Verified OK and
Claims lists, agent output contract) apply throughout. This file does not restate them.

Stages 2, 3, and 4 start together. Read this file together with `2-digest.md` and
`3-domain.md`, and enqueue this stage's jobs first.

Inputs: `audit-brief.md`, `common.md`, `groups.md`, `claims.md`, the questions in the
brief, and whatever `guidelines/digest-*.md` and `domain/*-map.md` exist when each
auditor reads them.

Outputs: `scope/<scope>.md` and `pass1/<scope>.md` for every pass-one scope.

## Steps

1. **Write the stage 4 entry as `running`** in `stages.json`, with its input hashes
   (`git hash-object --no-filters <file>` for `audit-brief.md`, `groups.md`,
   `claims.md`, `common.md`), before the first launch.

2. **List the scopes by tier.** The tier is in `audit-brief.md`.

   | Tier | Scopes |
   |---|---|
   | low | one scope, `combined`: every group in `groups.md`, plus tests and work-item hygiene |
   | medium | one scope per group in `groups.md`; `tests-hygiene`; `interactions` when there is more than one bundle |
   | high | one scope per group in `groups.md`; `tests`; `hygiene`; `interactions` when there is more than one bundle |

   Group scopes include `unticketed` and `cross-cutting` when `groups.md` has them. A
   group in `groups.md` with no files gets no scope and no agent; record it in the
   stage entry as "skipped: no files".
   Scope is never merged or dropped to fit `--max-agents`; extra work waits in the queue.

3. **Write one scope file per scope**, `scope/<scope>.md`, holding:
   - the scope id and its role (group, `combined`, `tests`, `hygiene`, `tests-hygiene`,
     or `interactions`);
   - the changed files it covers, copied from `groups.md` with their notes (for a
     specialist, every changed file of every bundle);
   - each claim assigned to it in stage 1, by number with its kind (for `combined`, every
     claim); the scope that holds the `hygiene` claims gets every one of them: `hygiene` at
     high tier, `tests-hygiene` at medium, `combined` at low;
   - the tickets it concerns and the readable-tree path of each repo, from the brief;
   - the question ids to answer (every question, at every tier);
   - for every scope that is assigned a `decision` claim, the decision ledger row of the
     table below, copied beside its other checklist rows;
   - for a specialist or `combined` role, its checklist, copied from this table:

   | Role | Checklist |
   |---|---|
   | tests | coverage of new behavior; weakened, deleted, or skipped tests; CI config changes |
   | hygiene | each ticket matches the change; each acceptance criterion met or not, with evidence; follow-ups recorded; each `status` claim's parent and links checked against the forge data; every key the brief lists as "not in export" reported as a finding; the scope check for every `scope` claim (`## Scope` in `common.md`) |
   | tests-hygiene | both rows above |
   | interactions | contracts, schemas, and APIs changed in one bundle and used in another; stack order and the combined state the brief states |
   | combined | the group review of every changed file, plus the tests and hygiene rows above, in one report |
   | decision ledger (every group and specialist scope with a `decision` claim) | the decision ledger for each `decision` claim assigned to the scope (`## Decisions` in `common.md`): three dimensions, class, reversibility, recommendation |

   At low tier the report's Coverage section says that one auditor covered the ticket,
   tests, and work-item hygiene with this checklist, instead of separate auditors.

4. **Launch one `cca:auditor` per scope** with the Agent tool, in the background, never
   as a fork, with the `model` parameter set from `--models` or the manifest's `models`
   key for `auditor`, else the agent's default. The prompt is short and holds only:
   - the path of `audit-brief.md`;
   - the path of `common.md`;
   - the path of `scope/<scope>.md`;
   - the output path, `pass1/<scope>.md`;
   - the scope's question ids and text.

   Finding ids are `<scope>-F<n>`. Record each launch (type, model, scope, start time)
   for the stage entry.

5. **Queue rule.** One queue serves stages 2 to 7. Digest jobs go in first, then maps,
   then pass-one jobs, so that more digests and maps finish before the barrier and fewer
   top-ups run. The order cannot remove top-ups, and auditors may start a little later.
   Never have more than `--max-agents` agents running (default 8). Each completion
   notification drives the next launch.

6. **`_test.hold`.** Apply the preamble's hold rule. When `_test.hold` has `until: 4`,
   the held stage's jobs wait until every pass-one auditor launched in step 4 has ended
   (top-ups do not count), which is what makes the barrier's top-up path run. When it
   has `stage: 4`, the jobs of step 4 wait instead. Record the hold in the stage entry.

7. **On each completion notification** for a pass-one auditor:
   1. Record the end time and the notification's `subagent_tokens` and `duration_ms` in
      the stage entry and `usage.md`, with the token label "task notification,
      subagent_tokens; scope not documented".
   2. The agent failed when it returned an error, or when `pass1/<scope>.md` is missing
      or its last line is not `status: complete`. When `_test.fail` has an entry with
      `role: auditor` and a `scope` equal to this scope or `any`, treat this scope's
      first `times` completions as failures whatever the file says.
   3. On failure, follow the auditor ladder:

      | Failure | Action |
      |---|---|
      | first | relaunch on the same model with the same prompt; no swap |
      | second | relaunch with `model: fable`; record a swap (role `auditor`, scope, from model, to `fable`, reason) |
      | third | the scope failed; record it and its coverage loss; stage 4 will be `failed` |

      A relaunch overwrites the output file. A failed scope counts as done for the
      barrier and for stage completion, and gets no pass two.
   4. On success, check that the file has `runs:` and `consumed:` headings (either may
      say none). The `consumed:` list names each digest and map read, with its hash.
      Check coverage too: the report's `## Decisions` names every `decision` claim
      assigned to the scope, and a report from a scope that holds `hygiene` claims has
      a `## Scope` that names every `scope` claim assigned to it. A miss does not fail
      the scope: the entry was never written, so record the claim as `not assessed`
      in the stage entry. Stage 8 lists it in the coverage disclosure and gives it the
      verdict `not verified`, with the reason "not assessed".

8. **Reconciliation barrier.** Once stages 2 and 3 each have status `complete`,
   `failed`, or `not_applicable` in `stages.json`, compute the barrier for each scope
   whose pass-one report is complete:
   1. The final set is every digest and map in the `output_hashes` of the stage 2 and
      stage 3 entries, with those hashes. Confirm each with
      `git hash-object --no-filters <file>`; a file whose hash differs from its entry is
      read at its current hash. A stage that is `not_applicable` adds nothing; a
      `failed` stage adds the outputs it did complete.
   2. Compare it with the report's `consumed:` list. A final file missing from the list,
      or listed with another hash (an earlier revision), is a miss.
   3. No misses: the scope has cleared the barrier. Start its pass two per
      `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/5-pass-two.md` at once; do not wait for other scopes.
   4. Misses: enqueue a top-up `cca:auditor` for the scope. Before launching it, copy
      `pass1/<scope>.md` to `pass1/<scope>.pre-topup.md`. The prompt says "mode: top-up
      after the barrier" and holds the paths of `audit-brief.md`, `common.md`, and
      `scope/<scope>.md`, the missed digest and map paths with their hashes, the scope's
      questions, and the output path `pass1/<scope>.md`. The agent's standing
      instructions cover the rest: apply every rule in each missed digest and every
      answer in each missed map to the scope's files, not only the `potential finding`
      lines; cite the original document or source at its sha, never the digest or map;
      keep every existing line, drop only the final `status: complete` line, and append
      a top-up section (a heading starting `## top-up` or `## Top-up`) with the new
      findings (ids continue the scope's `F<n>` numbering), `runs:`, and `consumed:`,
      ending with `status: complete`.
   5. A top-up succeeded when the file ends with `status: complete`, has a top-up
      section, and keeps the earlier content: compare line by line, after stripping
      CR from every line, the lines before the first top-up heading (`## Top-up`, or
      `## top-up`) with the saved copy less its `status: complete` line, ignoring
      trailing empty lines. On failure,
      restore the file from the saved copy and follow the auditor ladder with scope id
      `<scope>-topup` (a `_test.fail` entry naming that id or `any` applies). When the
      top-up scope fails, the scope still clears the barrier with its pass-one report,
      and the missed files are recorded as coverage loss.
   6. After a successful top-up, compute the barrier again, since a digest or map may
      have changed while it ran, and repeat from sub-step 2 on a new miss. The scope
      clears once no miss remains.

9. **Budget.** Before every launch (first launch, relaunch, top-up), check the budget per
   the preamble. Once it has expired, launch nothing more, let running agents finish,
   record each scope or top-up not run as "not run: budget expired", and go to stage 8
   when no agent is running.

10. **Stage completion.** Stage 4 is done when every scope has a complete report or has
    failed, every scope has cleared the barrier, and every top-up has finished or
    failed. Its status is `complete` when no scope failed and no job was cut by the
    budget, else `failed`, and the run will end `partial`. Pass two may already be
    running for early scopes; it does not wait on this step.

11. **Read-only check.** Run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and write
    `baseline/4-check.md`. Auditors have Bash, so an ignored-file difference is accepted
    provisionally while any of them runs and is reconciled against the finished
    auditors' `runs:` headings. A difference in tracked files, untracked non-ignored
    files, refs, index, stash, or config ends the run `blocked`.

12. **Write the stage 4 entry last,** once the check has passed, per the preamble
    (temporary file beside `stages.json`, then rename): status, inputs (including each
    consumed digest and map hash), outputs (every `scope/` and `pass1/` file, and each
    `.pre-topup.md` copy), agents, swaps, failed scopes with reasons, each claim
    recorded as `not assessed`, and each `_test` fault applied.
