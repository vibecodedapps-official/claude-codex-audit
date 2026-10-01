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

Audited source files are never inputs; the request points at them by the read paths
and shas in `audit-brief.md`.

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

- **By path.** When the run directory is inside the session's repository, the request
  names each input copy by its path relative to that repository's root, and Codex
  opens them.
- **Inline.** When the run directory is outside the session's repository, and in the
  retry after a missing acknowledgment, the request carries the full content of every
  input copy, each under a header with its run-directory path, sentinel line first,
  diffs included, so it names no file Codex must open:

  ```
  ===== input: codex/inputs/<run-relative path> =====
  cca-sentinel: <run-relative path> <token>
  <content>
  ===== end: codex/inputs/<run-relative path> =====
  ```

  When the inline request would exceed 450,000 bytes (or `_test` `inline_cap_bytes`),
  the diffs are dropped from it first and it is measured again. A dropped diff is no
  longer an input or acknowledged; the request gives, per bundle, the command to
  regenerate it from the shas in the brief, `git -C <repo> diff <base>...<head>`. If it
  is still over, it is not sent. Stage 6 is swapped to the fallback, which reads the
  inputs by path, with the reason `request too large for inline form`.

## Request

Fill `<...>` and keep the order of the asks.

```
# Second opinion for audit <run-id>

You are giving an independent second opinion on an audit of a bundle of changes. Read
only; change no file. The audit's rules, evidence kinds, and finding schema are in
common.md; use them. The session summary and every sentence in claims.md are claims to
verify, not facts.

## Inputs

<by path: one line per input copy, "- <path relative to the repository root>">
<inline: every input copy, in the inline form>

Audited sources, read at the pinned shas in audit-brief.md:
<one line per bundle, reference, and source of truth: name, read path, sha, mode>

## Acknowledge your inputs first

Begin your answer with a section "## Acknowledgments" that quotes, for every input
above, its first line exactly as you read it (the line starting "cca-sentinel:").
An input you could not open is listed as "not read: <path>".

## Asks, in this order

1. For each finding at severity blocker or high: your verdict (agree, disagree, or
   change severity), with your own evidence, not the auditor's; <"for these ids: <id
   list>" when stage 6 split the mandatory set (more than 60 ids), else "for every
   such finding">.
2. For each finding pass two downgraded or dropped: your position, with evidence;
   <"for these ids: <id list>" when stage 6 split the mandatory set (more than 60
   ids), else "for every such finding">.
3. Dropped findings you would restore, each with the reason and evidence.
4. Up to ten findings no reviewer raised, each in the finding schema from common.md,
   with ids X1, X2, and so on, and the line "- origin: codex".
5. Severity recalibration: any finding whose severity you would change, from and to,
   with the reason.
6. A non-binding merge verdict per bundle (not ready, merge after fixes, or ready to
   merge). It is non-binding and never replaces the report's verdict rules.

Also consider the coverage gaps the pass-two reports list.

## Answer format

- Per finding, one line: "<finding id>: <agree | disagree | restore | recalibrate
  <from> -> <to>>; <evidence>; <reason>".
- Evidence per common.md: quote (repo@sha:path:line), search, or run, naming the repo
  and commit.
- At most 3,000 words in total, and at most two quoted lines per citation.
- End with the per-bundle non-binding merge verdicts.
```

## Acknowledgment rule

After the answer, compare each input's sentinel with the `## Acknowledgments` section.
A sentinel not quoted exactly means access to that input is not confirmed. Retry once,
in the inline form. If any input is still unacknowledged, stage 6 fails: the findings
it covered do not pass the review gate on its account, and the run ends `partial`.
With `_test` `drop_ack`, treat the named input's acknowledgment as missing in the first
`times` answers. Stage 6 also checks that the answer gives a position for every
blocker or high finding and every pass-two downgrade or drop (asks 1 and 2); one still
missing after the one follow-up fails the stage the same way. The ids checked are
every mandatory id when the set was not split, else the ids listed in the "for these
ids" slots of asks 1 and 2 in the request and the follow-up.
