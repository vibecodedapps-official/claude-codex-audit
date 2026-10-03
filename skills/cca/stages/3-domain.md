# Stage 3: domain map

Runs alongside stages 2 and 4, from the moment stage 1 completes. Agents:
`cca:mapper`, one per code base among the sources of truth. The maps are pointers for
auditors: auditors cite the source at its pinned sha, never the map.

## Steps

1. **Applicability.** When `audit-brief.md` lists no source of truth classed as a code
   base, write the stage 3 entry with status `not_applicable`, no outputs, and no
   agents, and stop here. The stage counts as satisfied for the barrier and is listed
   in Coverage.
2. **Entry.** Write the stage 3 entry as `running`, with inputs: the hashes of
   `audit-brief.md`, `common.md`, `claims.md`, and `groups.md`, every
   `forge/<bundle>/` file, the pinned sha of each code base, and `plugin_version`.
3. **Question lists.** For each code base `<source>`, write
   `domain/<source>-questions.md`: per ticket, the questions of the form "how does
   `<source>` handle what this ticket changes?" Derive them from the ticket text, its
   acceptance criteria, and the `claim` lines of `claims.md` tagged with that ticket:
   one question per behavior, rule, input, output, or edge case the ticket or a claim
   says the change adds, alters, or removes. In a legacy-parity audit (the source is
   the legacy the change ports or replaces) these are the parity questions: does the
   change do what the legacy does, for each case. Number them `<ticket>-M<n>` and give
   each the group id from `groups.md` whose files it concerns, and the claim numbers it
   covers. Tickets with no questions for that source are listed with `none`.
4. **Launch.** Queue one `cca:mapper` per code base (SKILL.md, Queue and Agent launch
   rules; maps launch after digests and before pass one). With `_test` `hold` naming
   stage 3, queue them but launch none until the named stage's initial agents have ended. The
   prompt gives the absolute paths of `audit-brief.md`, `common.md`, the question file,
   and the output file `domain/<source>-map.md`, the source's read path and sha from
   the brief, and the read paths and shas of the other code bases, and says: answer
   every question against this source with quotes (`repo@sha:path:line`), write
   `not found` with the search that shows it where the source has no answer, and note
   each place where this source and another code base disagree, with a quote from
   each. The scope id is `<source>`.
5. **On each completion.** Apply `_test` `fail` for role `mapper` at scope `<source>`
   or `any`. Read the output: its last line must be `status: complete`. On failure,
   apply the failure table (relaunch same model; relaunch on fable as a swap; then the
   scope fails). Record the agent in the entry. On success:
   1. With `_test` `plant_map_error` naming this source, change one answer's
      conclusion in `domain/<source>-map.md` to its opposite, keeping its quote, and
      record the line number and the original line in the entry as `test_planted`.
      Do this before hashing.
   2. Hash the file with `git hash-object --no-filters domain/<source>-map.md` and
      record it in the entry's `output_hashes` map. These are the final map hashes
      the stage 4 reconciliation barrier compares with each pass-one report's
      `consumed:` list.
6. **End.** When every code base is complete or failed:
   1. Run the read-only check (SKILL.md, Read-only check), which writes
      `baseline/3-check.md`.
   2. Write the stage 3 entry: status `complete` when every map completed, else
      `failed`, with the failed sources in a `failed_scopes` list; outputs: every
      question file, every completed map, and `baseline/3-check.md`; `output_hashes`;
      and `test_planted` when set.
   3. Print the stage boundary line. With `_test` `expire_budget_after_stage: 3`, the
      budget expires now.
   4. Tell the barrier: go to the barrier step of `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/4-pass-one.md`
      for any group whose pass-one report is already complete.

A failed stage 3 counts as satisfied for the barrier, so the run goes on; its coverage
loss (the questions never answered) is recorded and the run ends `partial`.

Stage 5 may later correct a map; the orchestrator then writes
`domain/<source>-map.r2.md` with a corrections header and leaves the stage 3 map and
its hash unchanged (see `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/5-pass-two.md`).
