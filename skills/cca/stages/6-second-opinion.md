# Stage 6: second opinion (Codex through `codex-lite:ask`)

The orchestrator's procedure for stage 6. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and the
run's `common.md` apply throughout. The request's content, order, answer cap, sentinel
form, the follow-up's inline layout, and acknowledgment rule are in
`${CLAUDE_PLUGIN_ROOT}/skills/cca/codex-request.md`; this file says how to build, send,
and handle it.

Stage 6 starts when stage 5 is `complete` or `failed` (every scope has finished pass
two and every map-correction top-up has finished).

Inputs: `ledger/5.md` and the other run-directory inputs `${CLAUDE_PLUGIN_ROOT}/skills/cca/codex-request.md`
lists (`audit-brief.md`, `common.md`, `claims.md`, the diffs and stats, the `pass2/`
files), and the live inputs: `live/findings.md`, each `live/carried/<id>.md` it names,
and its result copies (`${CLAUDE_PLUGIN_ROOT}/skills/cca/live.md`, "Derivation"). The
result copies are not hashed, as `live.md` says. Each other live input is recorded in
the stage entry with its hash, or `absent` when it does not exist; absent to present, or
present to absent, is a change that reruns the stage (`resume.md`, step 5). `live/findings.md`
exists only on a run resumed with a live finding result. A `_test.drop_ack` naming
`live/findings.md` applies like any other input.

Outputs: `codex/request.md`, `codex/inputs/*`, `codex/response.md`, `ledger/6.md`,
and, when the fallback answers several batches, `codex/request-<k>.md` and
`codex/response-<k>.md` for each batch `<k>` it answers, numbered from 2 (step 9).

## Steps

1. **Check the budget** first. If it has expired, stage 6 does not start and gets no
   entry; go to stage 8. Otherwise write the stage 6 entry as `running` with its input
   hashes.

2. **Settle the call parameters** and keep them for the stage entry:
   - model: `--codex-model`, else `gpt-6.1-sol`. Always the full id.
   - timeout in seconds: `--codex-timeout` when given (the command already rejected
     values outside 1 to 3,600), else by tier: low `1200`, medium `2400`, high `3600`.

3. **Decide who fills the role.**
   - With `--no-codex`, the fallback fills it from the start, with the swap reason
     "--no-codex": build the request (step 4), then go to step 11.
   - Otherwise check availability. Run `codex --version`; if it does not exit 0, swap
     to the fallback with the reason "codex --version failed". Run
     `claude plugin list --json` with Bash and take the `version` of the entry whose id
     starts with `codex-lite@`; it must be 0.7.0 or later. If the command fails, the
     entry is absent, or the version cannot be read, swap to the fallback with the
     reason "codex-lite not installed or version unreadable"; if it is older than 0.7.0,
     swap with the reason "codex-lite <version> is older than 0.7.0". On any swap here,
     build the request (step 4), then go to step 11. Record both versions in the stage
     entry. The orchestrator never runs the `codex` CLI for anything else.

4. **Build the request** from `ledger/5.md`, per `${CLAUDE_PLUGIN_ROOT}/skills/cca/codex-request.md`:
   1. Copy each input the template lists to `codex/inputs/<run-relative path>`, with the
      sentinel line the template gives as its first line and a new random token per copy;
      this includes `live/findings.md`, each `live/carried/<id>.md` it names, and its
      result copies, when they exist, so each is a request input with a sentinel. Only generated run-directory
      files get a sentinel; the originals are not changed. Audited source files never get
      a sentinel, are never copied, and are named by their read path and sha from the
      brief. Keep every path and token for the stage entry's `sentinels` map.
   2. Write `codex/request.md`, filling the template: the inputs, then the acknowledgment
      section, then the asks in the template's order (every blocker, high, and medium finding,
      every pass-two downgrade or drop, dropped findings to restore including dismissed
      ones, up to ten new findings, severity recalibration, a non-binding merge verdict
      per bundle), within the 3,000-word answer cap and two quoted lines per citation. Ask 1
      also covers each finding `live/findings.md` lists, judged with its live result, and
      names each carried one with its carried file. When `live/carried/` holds an `X<n>`,
      ask 4 numbers the additions after the highest carried `X<n>`: the carried ids are
      reserved, so an addition never reuses one. Asks 1 and 2 each end with the template's
      id slot: when step 4.3 splits the mandatory set, `for these ids: <the batch's ids>`
      (the first batch here, from `codex/batch-1.txt` by shell, step 4.3); otherwise
      `for every such finding`. It names each input copy by its absolute path, and each
      audited source by its absolute read path and sha from the brief.
   3. **Mandatory id set and batches.** Never take the id list into the conversation.
      Run `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh mandatory <run dir> >
      <run dir>/tmp/mandatory.txt` and, only on exit 0, `mv -f <run dir>/tmp/mandatory.txt
      <run dir>/ledger/mandatory.txt`. Its content, one id per line, sorted and unique,
      is the mandatory set: every `ledger/5.md` finding id whose state after pass two is
      blocker, high, or medium, every id that pass two downgraded or dropped, and every id
      `live/findings.md` lists (a carried id may have no section in `ledger/5.md`). It is
      one deduplicated set for the request, the follow-up, the fallback batches, and the
      completion check (step 10). An id that asks 1 and 2 both apply to (a downgrade of a
      high, say) gets one position, not two. Asks 1 and 2 require a position for each, and
      no mandatory id may be left unrequested in a run that completes. A nonzero exit
      fails stage 6 (the run will end `partial`). Count it with `wc -l`. The 3,000-word
      answer cap cannot hold more than 60 ids, so when the set has more, split it in id
      order by shell (`split -l 60`, or awk) into batch files `codex/batch-<k>.txt` of at
      most 60 ids, numbered from 1; each batch is the id list in the slot of asks 1 and
      2. Fill each request's `for these ids:` slot by shell from its batch file, for
      example `paste -sd, <batch file> | sed 's/,/, /g' >> <request file>`, never by
      typing ids.
      - Codex: `codex/request.md` carries the first batch and the one follow-up (step
        8) carries at most 60 positions in total: the first batch's ids still without a
        position come first, then the second batch's ids in order until 60 is reached.
        Every mandatory id that neither carries (the rest of the second batch, and
        any further batch) goes to the fallback (step 11), in batches of at
        most 60, one `cca:adversary` launch per batch with scope `second-opinion-<k>`,
        each with its own `codex/request-<k>.md` (built as in the next bullet),
        launched in step 8 once the follow-up is composed and before the follow-up call
        is made (step 9 gives the numbering). It is recorded as a
        partial swap: role second opinion, scope those batches, from Codex `<model>` to
        `cca:adversary`, reason "mandatory ids beyond the Codex request and follow-up".
        These batches fail stage 6 only when one of them fails after the ladder (step
        11).
      - Fallback (step 11): `cca:adversary` is launched once per batch, each launch
        with its own request, `codex/request.md` for the first batch and
        `codex/request-<k>.md` for batch `<k>` from 2, written at step 11. Each has
        the same content except its batch's ids in the slot and, for `<k>` from 2,
        only asks 1 and 2 (asks 3 to 6 and the merge verdicts are answered in the
        first request).
      - `batched` is true in the stage entry when more than one batch was requested
        (a Codex follow-up carried the second, or the fallback was launched for a
        further batch), else false.

5. **Check the session's repository.** codex-lite runs Codex from the top of the git
   repository that contains the session's directory, and the orchestrator cannot move
   it. Run `git rev-parse --show-toplevel` in the session's directory. If the session's
   directory is not in a git repository, send the request anyway; codex-lite refuses,
   and step 7 swaps. The request has one form, so the run directory's location and the
   request's size change nothing here: Codex reads the inputs and sources by the
   absolute paths the request names.

6. **Call Codex** with the Skill tool, skill `codex-lite:ask`, options first:

   ```
   --model <model> --timeout <timeout> Read "<absolute path of codex/request.md>" and answer as it asks.
   ```

   Record the model and timeout passed for this call. The call can take longer than a
   foreground command allows and move to the background. The fallback batches for ids
   neither the request nor the follow-up carries (step 4.3) are launched before the
   follow-up call (step 8); once a call is made, wait for its completion notification
   without polling or any other tool call.

7. **Parse the result.** codex-lite ends its output with a line `status: <value>`, where
   the value is `ok`, `failed`, `refused`, or `timeout`, and prints a line
   `thread <id>` when a thread started. Take the last `status:` line and the `thread`
   line. Then:

   | Status | Handling |
   |---|---|
   | `ok` | continue to step 8 |
   | `failed`, or no status line | retry once as a fresh call with the same arguments; on a second `failed` or missing status, swap to the fallback with the reason "codex failed twice" |
   | `refused` | do not retry; swap to the fallback, recording codex-lite's message as the reason |
   | `timeout` | swap to the fallback with the reason "codex timeout after <timeout> s" |

   A fresh retry is not a follow-up.

8. **Check acknowledgments.** Every input the request names must have its sentinel quoted
   in the answer. When `_test.drop_ack` names an input (by run-directory path, such as
   `ledger/5.md` or `live/findings.md`), treat that input's acknowledgment as missing for
   the first `times` checks, whatever the answer says. Also compute now, against the
   answer, the mandatory ids (step 4.3) that it leaves without a position, and whether a
   second batch of asks 1 and 2 is due. For Codex's answer, first save it verbatim in
   `codex/response.md` (step 9), since the missing ids are read from that file; a
   follow-up's output is appended to it later and never overwrites it. A fallback batch
   (step 11) saves nothing here: it already wrote its own `codex/response.md` or
   `codex/response-<k>.md`, which this check reads, and the batches are appended to
   `codex/response.md` only as step 11 says. Then compute the missing ids with
   `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh missing <run dir> >
   <run dir>/tmp/missing.txt`: it prints the mandatory ids with no provenance line in
   `codex/response*.md`, by the rules `check` uses. A nonzero exit fails stage 6. Count
   with `wc -l` and never read the list into the conversation; build the follow-up's id
   slots from that file by shell.
   - All inputs acknowledged, no mandatory id without a position, and no second batch
     due: continue to step 9.
   - Anything else (an input unacknowledged, a mandatory id without a position, or a
     second batch due): access or coverage is not confirmed. Send the one follow-up
     allowed, the Skill tool, `codex-lite:ask`, with `--model <model> --timeout
     <timeout> --resume <thread id>`. As the question it carries, together: the
     unacknowledged inputs in inline form (full content under their path and sentinel
     headers) with a request to acknowledge them and revise any answer that depended on
     them; and asks 1 and 2 for at most 60 ids in total, ending each ask with
     `for these ids: <id list>`: the first batch's ids still without a position, then
     the second batch's ids in order as far as 60 allows, the list built by shell from
     `tmp/missing.txt` and the batch files and appended to the follow-up file in the
     same `for these ids:` form (step 4.3; `batched` is then
     true). Second-batch ids that do not fit are not asked here; step 4.3 sends them to
     the fallback: launch those fallback batches now, before this follow-up call
     (step 11, numbered as step 9 says), so they run while Codex answers and a budget
     that expires during the call still lets them finish. Measure the follow-up in bytes
     (`wc -c`). The cap is 450,000 bytes, or `_test.inline_cap_bytes` when set. Over the
     cap, the follow-up is not sent and stage 6 fails as below; no diff is dropped. With
     no thread id, send it as a fresh call that carries only the follow-up's asks (the
     unacknowledged inputs inline, the missing positions, the second batch) plus
     `common.md`, `audit-brief.md`, and `ledger/5.md`, each named by its absolute path
     under `codex/inputs/`, not the whole request again. Handle its status as in step 7,
     except that a swap is replaced by stage 6 failing, since the first answer already
     exists.
   - Still unacknowledged after the follow-up: stage 6 fails. Keep the answer, list the
     unacknowledged inputs in `ledger/6.md` and the stage entry, naming as one possible
     cause that the inline text was altered in transit through the Skill argument, or
     that Codex could not open a path, and mark in `ledger/6.md` that no finding passes
     the review gate on stage 6's account. The run will end `partial`.

   There is at most one follow-up per run of stage 6. A mandatory position the request
   or the follow-up asked for and still missing after the follow-up is handled in step
   10. Ids neither carried are not part of the follow-up: step 11 launches them.

9. **Save the answer verbatim** in `codex/response.md`: the codex-lite output as
   returned, unchanged, written at step 8 before the missing ids are computed. A
   follow-up's output is appended after a line
   `--- follow-up, thread <id> ---`. The fallback batches of step 4.3 are known once
   step 8 has composed the follow-up, so launch them then, before the follow-up call
   (they are Agent launches, not Codex calls), and wait for them before step 10.
   Number them `<k>` from 2 upward in id order over the ids neither the request nor
   the follow-up carried, re-batched in at most 60; when the fallback fills the role,
   `<k>` is the batch number of the original split. That `<k>` names the request and
   response files, the agent scope `second-opinion-<k>`, and the `--- batch <k> ---`
   line.

10. **Check the mandatory positions, then write `ledger/6.md` once.** Before writing,
    take the ids step 10 requires, which are every mandatory id from step 4.3 (computed
    from `ledger/5.md` and `live/findings.md`; all of them are requested across the
    batches), and compare
    them with the finding ids the answer, with any follow-up appended, addresses with a
    position, by the same `ledger.sh missing` output to `tmp/missing.txt` (a nonzero
    exit fails stage 6; the list is counted with `wc -l`, never read). When an id has a position in more than one place, the later one replaces
    the earlier; both stay in `codex/response.md`. For Codex this is a check after the
    fact: the follow-up for missing positions was already sent in step 8, and step 10
    sends none. A mandatory id the request or the follow-up asked for, still without a
    position in the answer with the follow-up appended, fails stage 6: keep the answer, list the ids in
    `ledger/6.md` and under `missing_positions` in the stage entry, and mark in
    `ledger/6.md` that no finding passes the review gate on stage 6's account. For the
    fallback, whether it fills the role or only the batches Codex did not carry, a mandatory
    id of that launch's batch without a position fails the attempt (the ladder in step
    11). "seen, no position" applies only to ids outside the mandatory set.

    Write the position sections and the other parts first, then append `## Seen, no
    position` with the output of `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh
    seen <run dir> >> <run dir>/ledger/6.md`, redirected and never read (the script reads `ledger/6.md`, so the file must exist first).
    `ledger/6.md` is complete only then and is not rewritten after. Before marking stage
    6 complete, run `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/ledger.sh check <run dir>
    --through 6 --stage6 complete > <run dir>/tmp/check6.txt` and read only `wc -l` of
    that file and its first 50 lines (`head -n 50`). It covers one position per id, each position's
    provenance line in the response files, the mandatory set, the `## Seen, no position`
    list, and the `X<n>` additions. A nonzero exit fails stage 6 like a missing position:
    append its `ledger: ` lines to `ledger/6.md` under `## Stage failure` and list them in
    the stage entry, and mark that no finding passes the review gate on stage 6's account.

    `ledger/6.md` holds, in this order. Each part that is not a finding section sits
    under its own `## ` heading that is not a finding id (the names are in brackets),
    so that a finding section, which runs to the next `## ` heading, never takes it in
    (stage 7 slices the file by those headings):
    - who filled the role: `codex <model>` with the thread id, or `cca:adversary`
      (fallback) with its requested model, and any swap, whole or partial (the batches
      it covers), with its reason (`## Role`);
    - the acknowledgment table: each input, its sentinel, acknowledged or not
      (`## Acknowledgments`);
    - one section per finding id the answer addresses, whether it is in `ledger/5.md`
      or only in `live/findings.md` (a carried `X<n>` or `L<n>` may have a position here
      although its block is no longer in any ledger file):

      ```
      ## <finding id>
      - position: <verdict with its own evidence | position on the pass-two downgrade or drop | restore requested | severity recalibration to <severity>>
      - evidence: <as cited in the answer>
      - answer location: codex/response.md, <heading or line>
      ```

      Each of the three lines is nonempty; one section per id, the later position
      replacing the earlier. The check requires that some `codex/response.md` or
      `codex/response-<k>.md` has a line starting with the id and `:` (after leading
      spaces, `-`, `*`, `#`, and backticks); the answer location is a nonempty pointer for
      readers and is not checked.

    - Codex additions, each in the `common.md` schema (heading `### X<n>: <title>`)
      with `origin: codex` and an id `X<n>`. They are late additions;
    - the non-binding merge verdict per bundle, marked as such; it never replaces the
      report's verdict rules (`## Merge verdict (non-binding)`);
    - every `ledger/5.md` finding id that is not mandatory and has no position section
      above, listed as `- <id>` lines under "seen, no position" (`## Seen, no position`),
      from `ledger.sh seen`. A mandatory id is never listed so: with no position it fails
      the stage, as above;
    - when stage 6 failed, the missing positions or unacknowledged inputs and the mark
      that no finding passes the review gate on its account (`## Stage failure`).

11. **Fallback.** Launch `cca:adversary` with the Agent tool, in the background, never as
    a fork, with `model: fable`, once per batch of step 4.3 that the fallback answers
    (every batch when it fills the role; only the batches of ids that neither the Codex
    request nor its follow-up carried, step 4.3, a partial swap), all together, after first writing
    `codex/request-<k>.md` for each batch `<k>` from 2. Each launch is a separate agent
    in the stage entry, with scope `second-opinion-<k>` for batch `<k>` (scope
    `second-opinion` when it fills the role with one batch). The prompt holds the paths
    of `audit-brief.md`, `common.md`, and that batch's request (`codex/request.md` or
    `codex/request-<k>.md`, which the fallback reads by path), with the
    instruction to answer the request as it asks, within its caps, and write the answer
    to `codex/response.md` (batch `<k>` from 2: `codex/response-<k>.md`) ending with
    `status: complete`. Record a swap (role second opinion, from Codex `<model>` to
    `cca:adversary` on `fable`, reason; for the batches Codex did not carry, the partial swap
    of step 4.3 with its scope). Once every batch has succeeded, append each
    `codex/response-<k>.md` to `codex/response.md` (after Codex's answer and follow-up,
    in the partial case) after a line `--- batch <k> ---`. The ladder applies to each
    launch on its own:

    | Failure | Action |
    |---|---|
    | first | relaunch with `model: opus` |
    | second | stage 6 failed |

    The fallback failed when it returned an error or its file does not end with
    `status: complete`. A `_test.fail` entry with `role: fallback` and scope `any` or
    `second-opinion` (or that batch's `second-opinion-<k>`) makes its first `times`
    completions failures. On success, run the step 8 acknowledgment check and the
    step 10 mandatory-position check, for that batch's ids, on the fallback's answer.
    A `not read: <path>` or a missing sentinel quote for any input, or a mandatory id
    of its batch without a position, fails that attempt, so it follows the ladder
    above (relaunch on opus, then stage 6 failed). A batch that fails after the ladder
    fails the stage; the other launches still finish. No follow-up call exists for the
    fallback. When stage 6 fails for this reason, list the unacknowledged inputs in
    `ledger/6.md` and the stage entry as step 8's last bullet says, and the ids without
    a position under `missing_positions`. `batched` is true when more than one batch was
    requested (step 4.3), so every mandatory id is requested.
    When every batch passes both checks, write `ledger/6.md` from the answers as in
    step 10. Its additions also take `origin: codex` and ids `X<n>`, since they come
    from the second opinion, numbered after the highest carried `X<n>` (a carried id is
    reserved); only the first batch's answer carries additions.

12. **Stage completion.** Stage 6 is `complete` when an answer from Codex or the
    fallback is saved, every input is acknowledged by whoever filled the role, every id
    step 10 requires (every mandatory id, step 4.3) has a position, and `ledger/6.md` is
    written and passes `check --through 6 --stage6 complete`; otherwise `failed`, and the run will end `partial`.

13. **Read-only check.** Run the check in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and write
    `baseline/6-check.md`. codex-lite's own request and thread files in its data
    directory are allowed writes.

14. **Write the stage 6 entry last,** once the check has passed, per the preamble, with:
    status, inputs, outputs, agents (the fallback, if any, with tokens labeled "task
    notification, subagent_tokens; scope not documented"), swaps with reasons, and
    these stage 6 keys:

    ```json
    "codex_model": "gpt-6.1-sol",
    "codex_timeout": 1200,
    "sentinels": { "ledger/5.md": "<token>", "live/findings.md": "<token>" },
    "codex": { "called": true, "form": "path", "thread": "<id>", "status": "ok",
               "retried": false, "follow_up": false, "unacknowledged": [],
               "codex_version": "<text>", "codex_lite_version": "<text>" },
    "missing_positions": [],
    "batched": false
    ```

    `codex_model` and `codex_timeout` are the values passed on every call (the first
    call, a retry, and the follow-up all pass the same ones), or, when no call was made
    (`--no-codex` or Codex unavailable), the values settled in step 2,
    with `"called": false`. In `usage.md`, each Codex call has its wall-clock and tokens
    "not reported".

    `missing_positions` lists the mandatory ids still without a position at stage end:
    those the Codex request or follow-up asked for and left unanswered after the
    follow-up, and those of any fallback batch that failed after the ladder;
    `batched` is true when more than one batch of asks 1 and 2 was requested, by a Codex
    follow-up or by a further fallback launch (one agent per batch, scope
    `second-opinion-<k>`), else false.
    `codex.form` is always `path`.
