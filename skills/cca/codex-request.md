# Codex request template

Stage 6 builds `<run dir>/codex/request.md` from this template, from `ledger/5.md`.
The same request, unchanged, is what the second-opinion fallback reads when Codex is
swapped out.

## Inputs and sentinels

The request's inputs are these run-directory files:

- `audit-brief.md`
- `common.md`
- `claims.md`
- every `diffs/<bundle>.diff` and `diffs/<bundle>.stat`
- `ledger/5.md` (every finding with its original text and every pass-two verdict,
  including dropped findings)
- every `pass2/<group>.md` and `pass2/<group>-topup.md` (for the coverage gaps)
- `live/findings.md` and each `live/carried/<id>.md` it names, when `live/findings.md`
  exists: the findings that a live result answers, with their derivations, and the text
  of each carried finding (`live.md`)
- the result copies of `live/findings.md` (`live/results-<k>/<line>.txt`, `live.md`,
  "Derivation"), when it has any: a result kept as a file, which you read in full

Audited source files are never inputs; the request points at them by the absolute read
paths and shas in `audit-brief.md`. The live files are generated run-directory files, so
each gets a sentinel copy like the others; an input that does not exist is not listed.

Every generated run-directory file the request names starts with a sentinel line.
Audited sources never get one. Stage 1 to 5 outputs are not changed to add one;
instead, for each input, write a copy under `codex/inputs/<run-relative path>` whose
first line is the sentinel and whose remaining bytes are the input's, and name only
the copies. The sentinel line is:

```
cca-sentinel: <run-relative path> <token>
```

`<token>` is 16 random hexadecimal characters, new for each copy (for example from
`od -An -N8 -tx1 /dev/urandom`, spaces removed). Record every path and token in the
stage 6 entry's `sentinels` map, so the acknowledgment check can compare them.

## Forms

The request has one form. It names every input copy by its absolute path, and every
audited source by its absolute read path and sha from `audit-brief.md`, so Codex opens
each one itself, wherever the run directory is. It carries no inline content and has no
size cap, and no diff is dropped from it. An input Codex cannot open is caught by the
acknowledgment rule below.

The follow-up after a missing acknowledgment is the only inline text. It carries the
unacknowledged inputs in this layout, as stage 6 step 8 describes:

```
===== input: codex/inputs/<run-relative path> =====
cca-sentinel: <run-relative path> <token>
<content>
===== end: codex/inputs/<run-relative path> =====
```

When the follow-up would exceed 450,000 bytes (or `_test` `inline_cap_bytes`), it is
not sent and stage 6 fails. No diff is dropped from it.

## Request

Fill `<...>` and keep the order of the asks.

```
# Second opinion for audit <run-id>

You are giving an independent second opinion on an audit of a bundle of changes. Read
only; change no file. The audit's rules, evidence kinds, and finding schema are in
common.md; use them. The session summary and every sentence in claims.md are claims to
verify, not facts.

## Inputs

<one line per input copy, "- <absolute path of the copy under codex/inputs/>">

Audited sources, read at the pinned shas in audit-brief.md:
<one line per bundle, reference, and source of truth: name, absolute read path, sha,
mode>

## Acknowledge your inputs first

Begin your answer with a section "## Acknowledgments" that quotes, for every input
above, its first line exactly as you read it (the line starting "cca-sentinel:").
An input you could not open is listed as "not read: <path>".

## Asks, in this order

1. For each finding at severity blocker, high, or medium, and each finding
   `live/findings.md` lists, judged with its live result: your verdict (agree,
   disagree, or change severity), with your own evidence, not the auditor's; <"for
   these ids: <id list>" when stage 6 split the mandatory set (more than 60 ids), else "for every such
   finding">. A finding that has a file under `live/carried/` is carried: its text is in
   that file, and the ledger may no longer hold it.
2. For each finding pass two downgraded or dropped: your position, with evidence;
   <"for these ids: <id list>" when stage 6 split the mandatory set (more than 60
   ids), else "for every such finding">.
3. Dropped findings you would restore, each with the reason and evidence.
4. Up to ten findings no reviewer raised, each in the finding schema from common.md,
   under a heading `### X<n>: <title>` with ids X1, X2, and so on, and the line
   "- origin: codex". <When
   `live/carried/` holds an `X<n>`: "Number them after the highest carried X<n>, which
   is reserved for the carried finding", with the first number filled in.>
5. Severity recalibration: any finding whose severity you would change, from and to,
   with the reason.
6. A non-binding merge verdict per bundle (not ready, merge after fixes, or ready to
   merge). It is non-binding and never replaces the report's verdict rules.

Also consider the coverage gaps the pass-two reports list.

## Answer format

- Begin each position line with the finding id and a colon (a leading "- " is fine).
  Per finding, one line: "<finding id>: <agree | disagree | restore | recalibrate
  <from> -> <to>>; <evidence>; <reason>".
- Evidence per common.md: quote (repo@sha:path:line), search, or run, naming the repo
  and commit.
- At most 3,000 words in total, and at most two quoted lines per citation.
- End with the per-bundle non-binding merge verdicts.
```

## Acknowledgment rule

After the answer, compare each input's sentinel with the `## Acknowledgments` section.
A sentinel not quoted exactly means access to that input is not confirmed. Retry once,
carrying the unacknowledged inputs inline. If any input is still unacknowledged, stage 6
fails: the findings it covered do not pass the review gate on its account, and the run
ends `partial`. With `_test` `drop_ack`, treat the named input's acknowledgment as
missing in the first `times` answers. Stage 6 also checks that the answer gives a
position for every blocker, high, or medium finding and every pass-two downgrade or drop
(asks 1 and 2); one still missing after the one follow-up fails the stage the same way.
An id that both asks cover gets one position. The ids checked are every mandatory id:
when the set was split into batches of at most 60, the request carries the first batch and the follow-up at most 60 positions
(missing first-batch ids first, then second-batch ids), every id neither carries being
answered by the fallback in batches of at most 60, one launch each; without Codex the fallback is
launched once per batch. Each request has its own ids in the "for these ids" slot.
A request for a batch after the first, which only the fallback receives, keeps the
inputs, the acknowledgments, and asks 1 and 2 alone. The live ids (every finding
`live/findings.md` lists) are part of the mandatory set, and so of its batching.
