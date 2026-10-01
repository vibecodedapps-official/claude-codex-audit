# Stage 6: second opinion (Codex through `codex-lite:ask`)

The orchestrator's procedure for stage 6. The preamble in `${CLAUDE_PLUGIN_ROOT}/skills/cca/SKILL.md` and the
run's `common.md` apply throughout. The request's content, order, answer cap, sentinel
form, inline form, and acknowledgment rule are in `${CLAUDE_PLUGIN_ROOT}/skills/cca/codex-request.md`; this
file says how to build, send, and handle it.

Stage 6 starts when stage 5 is `complete` or `failed` (every scope has finished pass
two and every map-correction top-up has finished).

Inputs: `ledger/5.md` and the other run-directory inputs `${CLAUDE_PLUGIN_ROOT}/skills/cca/codex-request.md`
lists (`audit-brief.md`, `common.md`, `claims.md`, the diffs and stats, the `pass2/`
files).

Outputs: `codex/request.md`, `codex/inputs/*`, `codex/response.md`, `ledger/6.md`, and
`codex/request-inline.md` when the inline form is built.

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
   1. Copy each input the template lists to `codex/inputs/<run-relative path>`, with
      the sentinel line the template gives as its first line and a new random token per
      copy. Only generated run-directory files get a sentinel; the originals are not
      changed. Audited source files never get a sentinel, are never copied, and are
      named by their read path and sha from the brief. Keep every path and token for the
      stage entry's `sentinels` map.
   2. Write `codex/request.md` in path form, filling the template: the inputs, then the
      acknowledgment section, then the asks in the template's order (every blocker and
      high, every pass-two downgrade or drop, dropped findings to restore including
      dismissed ones, up to ten new findings, severity recalibration, a non-binding
      merge verdict per bundle), within the 3,000-word answer cap and two quoted lines
      per citation. Asks 1 and 2 each end with the template's id slot: when step 4.3
      splits the mandatory set, `for these ids: <first batch>`; otherwise `for every
      such finding`. When the run directory is inside the session's repository root
      (step 5), it names each copy by its path relative to that root; otherwise by its
      absolute path, which only the fallback uses.
   3. **Mandatory id set.** From `ledger/5.md`, collect every finding id at severity
      blocker or high, and every finding id that pass two downgraded or dropped. Asks 1
      and 2 require a position for each. When the set has more than 60 ids, it may not
      fit the 3,000-word answer cap: split asks 1 and 2 in id order into a first batch
      (the first 60 ids) and a second batch (the rest). The request carries the first
      batch; the second batch goes in the one follow-up (step 8), a Codex follow-up.
      `batched: true` goes in the stage entry only when a Codex follow-up carries the
      second batch. With the fallback (it has no follow-up), `batched` is false and
      every mandatory id past the first batch is listed in `ledger/6.md` as `not
      requested`. The same holds for any id past a second batch of 60 ids. Ids listed
      as `not requested` stay provisional. The mandatory set for the checks in steps 8,
      10, and 11 is the ids actually requested.

5. **Choose the form.** Find the session's repository root with
   `git rev-parse --show-toplevel` in the session's directory. codex-lite runs Codex
   from that root, and the orchestrator cannot move it.
   - Run directory inside that root: send the path form.
   - Run directory outside it: build the inline form, `codex/request-inline.md`, which
     carries the full content of every `codex/inputs/` file under a header with its
     run-directory path and its sentinel, diffs included unless the inline cap below
     drops them, so it names no file Codex must open. Audited source files are not
     inlined. The inline request travels as the Skill tool argument, which codex-lite
     rewrites to its own request file, so a large inline request is slow and may be
     altered in transit.
   - Session directory not in a git repository: send the path form anyway; codex-lite
     refuses, and step 7 swaps.

   **Inline cap.** Measure the inline request's size in bytes (`wc -c`). The cap is
   450,000 bytes, or `_test.inline_cap_bytes` when set. Over the cap, first reduce the
   request by dropping the diffs (`codex/inputs/diffs/*.diff`; Codex can regenerate them
   from the shas in the brief with the three-dot form the brief gives), re-write
   `codex/request-inline.md` without them, and measure again; record
   `inline_reduced: true` in the stage entry. A dropped diff is removed from the
   request's input list, from its acknowledgment section, and from the set the step 8
   check expects; in its place the request gives, per bundle, the command to regenerate
   it, `git -C <repo> diff <base>...<head>` with the shas from the brief (the form
   `1-orient.md` uses for `diffs/<bundle>.diff`). Still over the cap after that, the
   request is not sent: swap to the fallback (step 11), which reads inputs by path, with
   the reason "request too large for inline form". The brief already notes that a run
   directory inside the session's repo avoids the inline form.

6. **Call Codex** with the Skill tool, skill `codex-lite:ask`, options first:

   ```
   --model <model> --timeout <timeout> Read <path of codex/request.md relative to the repo root> and answer as it asks.
   ```

   In inline form, the argument after the options is the full text of
   `codex/request-inline.md`. Record the model and timeout passed for this call. The
   call can take longer than a foreground command allows and move to the background:
   wait for its completion notification, do not poll, and use no other tool meanwhile.

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

8. **Check acknowledgments.** Every input the request names must have its sentinel
   quoted in the answer. When `_test.drop_ack` names an input (by run-directory path,
   such as `ledger/5.md`), treat that input's acknowledgment as missing for the first
   `times` checks, whatever the answer says.
   Also compute now, against the answer, the mandatory ids (step 4.3) that it leaves
   without a position, and whether a second batch of asks 1 and 2 is due.
   - All inputs acknowledged, no mandatory id without a position, and no second batch
     due: continue to step 9.
   - Anything else (an input unacknowledged, a mandatory id without a position, or a
     second batch due): access or coverage is not confirmed. Send the one follow-up
     allowed, the Skill tool, `codex-lite:ask`, with `--model <model> --timeout
     <timeout> --resume <thread id>`. As the question it carries, together: the
     unacknowledged inputs in inline form (full content under their path and sentinel
     headers) with a request to acknowledge them and revise any answer that depended on
     them; the mandatory ids without a position, with a request for their positions;
     and the second batch of asks 1 and 2, ending each ask with `for these ids: <the
     second batch's id list>`, when step 4.3 left one for Codex (then `batched` is
     true). Apply the inline cap to this follow-up. Over it, first drop the diffs from
     it and re-measure as in step 5 (record `inline_reduced: true`); a dropped diff no
     longer needs acknowledgment, and the follow-up gives its three-dot regeneration
     command in its place, as in step 5. Still over the cap, the follow-up is not
     sent and stage 6 fails as below. With no thread id, send it as a fresh call
     carrying the whole request in the form step 5 chose (path form: the same `Read
     <path>` instruction; inline form: the whole inline text), plus the follow-up's
     asks. Handle its status as in step 7, except that a swap is replaced by stage 6
     failing, since the first answer already exists.
   - Still unacknowledged after the follow-up: stage 6 fails. Keep the answer, list the
     unacknowledged inputs in `ledger/6.md` and the stage entry, naming as one possible
     cause that the inline text was altered in transit through the Skill argument, and mark in
     `ledger/6.md` that no finding passes the review gate on stage 6's account. The run
     will end `partial`.

   There is at most one follow-up per run of stage 6. A mandatory position still missing
   after it is handled in step 10.

9. **Save the answer verbatim** in `codex/response.md`: the codex-lite output as
   returned, unchanged. A follow-up's output is appended after a line
   `--- follow-up, thread <id> ---`.

10. **Check the mandatory positions, then write `ledger/6.md` once.** Before writing,
    take the mandatory id set from step 4.3 (computed from `ledger/5.md`; every
    mandatory id when the set was not split, else the ids listed in the "for these ids"
    slots of the request and the follow-up) and compare it with the finding ids the
    answer, with any follow-up appended, addresses with a position. For Codex this is a
    check after the fact: the follow-up for missing positions was already sent in step
    8, and step 10 sends none. A mandatory id still without a position in the answer
    with the follow-up appended fails stage 6: keep the answer, list the ids in
    `ledger/6.md` and under `missing_positions` in the stage entry, and mark in
    `ledger/6.md` that no finding passes the review gate on stage 6's account. For the
    fallback, a mandatory id without a position fails the attempt (the ladder in step
    11). "seen, no position" applies only to ids outside the mandatory set.

    `ledger/6.md` holds, in this order:
    - who filled the role: `codex <model>` with the thread id, or `cca:adversary`
      (fallback) with its requested model, and any swap with its reason;
    - the acknowledgment table: each input, its sentinel, acknowledged or not;
    - one section per `ledger/5.md` finding id the answer addresses:

      ```
      ## <finding id>
      - position: <verdict with its own evidence | position on the pass-two downgrade or drop | restore requested | severity recalibration to <severity>>
      - evidence: <as cited in the answer>
      - answer location: codex/response.md, <heading or line>
      ```

    - Codex additions, each in the `common.md` schema with `origin: codex` and an id
      `X<n>`. They are late additions;
    - the non-binding merge verdict per bundle, marked as such; it never replaces the
      report's verdict rules;
    - every `ledger/5.md` finding id the answer does not address, listed as "seen, no
      position" when it was in the request and not mandatory, and every mandatory id left
      out of the request by step 4.3, listed as `not requested`.

11. **Fallback.** Launch `cca:adversary` with the Agent tool, in the background, never as
    a fork, with `model: fable`. The prompt holds the paths of `audit-brief.md`,
    `common.md`, and `codex/request.md` (path form, which the fallback reads by path),
    with the instruction to answer the request as it asks, within its caps, and write
    the answer to `codex/response.md` ending with `status: complete`. Record a swap
    (role second opinion, from Codex `<model>` to `cca:adversary` on `fable`, reason).
    Ladder:

    | Failure | Action |
    |---|---|
    | first | relaunch with `model: opus` |
    | second | stage 6 failed |

    The fallback failed when it returned an error or its file does not end with
    `status: complete`. A `_test.fail` entry with `role: fallback` and scope `any` or
    `second-opinion` makes its first `times` completions failures. On success, run the
    step 8 acknowledgment check and the step 10 mandatory-position check on the
    fallback's answer. A `not read: <path>` or a missing sentinel quote for any input, or
    a mandatory id without a position, fails that attempt, so it follows the ladder
    above (relaunch on opus, then stage 6 failed). No follow-up call exists for the
    fallback. When stage 6 fails for this reason, list the unacknowledged inputs in
    `ledger/6.md` and the stage entry as step 8's last bullet says, and the ids without
    a position under `missing_positions`. With the fallback `batched` is false, and
    every mandatory id past the first batch is `not requested` (step 4.3). When both
    checks pass, write `ledger/6.md` from its answer as in step 10. Its additions also
    take `origin: codex` and ids `X<n>`, since they come from the second opinion.

12. **Stage completion.** Stage 6 is `complete` when an answer from Codex or the
    fallback is saved, every input is acknowledged by whoever filled the role, every
    mandatory id has a position, and `ledger/6.md` is written; otherwise `failed`, and
    the run will end `partial`.

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
    "sentinels": { "ledger/5.md": "<token>" },
    "codex": { "called": true, "form": "path", "thread": "<id>", "status": "ok",
               "retried": false, "follow_up": false, "unacknowledged": [],
               "codex_version": "<text>", "codex_lite_version": "<text>" },
    "missing_positions": [],
    "batched": false,
    "inline_reduced": false
    ```

    `codex_model` and `codex_timeout` are the values passed on every call (the first
    call, a retry, and the follow-up all pass the same ones), or, when no call was made
    (`--no-codex`, Codex unavailable, or the inline cap), the values settled in step 2,
    with `"called": false`. In `usage.md`, each Codex call has its wall-clock and tokens
    "not reported".

    `missing_positions` lists the mandatory ids still without a position at stage end;
    `batched` is true only when a Codex follow-up carried the second batch of asks 1 and
    2; with the fallback it is false;
    `inline_reduced` is true when the inline request or the follow-up was reduced by
    dropping diffs.
