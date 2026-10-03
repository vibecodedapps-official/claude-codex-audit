# Live check results

A live check is a query or command that only a live system or another environment can
answer. The audit never runs one itself (`common.md`, hard rule 5). It lists each in the
report, the user runs the approved ones, and `/cca:resume <run-id> --live <file>` feeds
the results back. This file is the single home of the report's Live checks blocks, the
`--live` file format, its validator, the imports and the files derived from them, and the
rules that turn a result into a finding's label or a claim's verdict. The validator and
the bookkeeping are `${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/live.sh`, which follows
this file; the resume procedure that calls it is in
`${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/resume.md`, step 4.

## Ids

A live entry names one of:

- a finding id of a Live checks block: `<scope>-F<n>`, `<scope>-P<n>`, or `<scope>-T<n>`
  from `ledger/5.md` (a merged group's id reads `g1+g2-F3`), a second-opinion addition
  `X<n>`, or a late addition `L<n>`;
- `claim <n>`, an environment claim of `claims.md` (see "Env claims" in `common.md`).

It never names `C<n>`: stage 7 keeps `C<n>` stable only for the same ledger files, so a
rerun can renumber it. Stage 5 never reruns under `--live`, so the `ledger/5.md` ids
survive. A rerun of stage 6 or 7 regenerates `X<n>` and `L<n>`, so a result for one of
those carries the finding with it (see "Carried findings").

## The report's Live checks blocks

Report section 9 holds one block per live check, so every value is a whole line. A block
starts at a heading `#### live <finding id>` or `#### live claim <n>` and runs to the
next line that starts with one or more `#` and a space:

```
#### live <finding id> | live claim <n>
- item: C<n> | claim <n>
- query: <the query or command, exactly as the check states it>
- where: <where it runs>                  (finding)
- env: <name>                             (env claim)
- results: <what each result changes>     (finding)
- status: not run: not approved | run, approved by <who> at <time>: <result>; derived: <derived>; <reviewed | under review: <what it lacks>>
```

The `where` and `results` lines are the finding's own `live check` field, split at its
semicolons. An env claim has `env` in place of `where` and `results`; its `query` is the
check part of the verified entry after its `env: <name>; ` tag. The `#### live ` headings
do not match the work-items validator's `#### C<n>: ` item headings. The `status` line
reads `not run: not approved` until a result is imported; after that it gives the
approver and time from the result, the result itself, what was derived from it
("Derivation", below), and `reviewed`, or `under review: <what it lacks>` while the
live review has not completed (`stages/7-converge.md`, step 4).

## The `--live` file

```
---
cca-live: 1
run: <run id>
report: sha256:<hex>
---

## <finding id> | claim <n>
- query: <the query or command run>
- env: <name>                     (a claim entry only, the environment it ran against)
- where: <where it ran>
- result: <the result, one line>   (or result_file: <path>, below)
- approved_by: <the person who approved the access>
- approved_at: <time, starting YYYY-MM-DD>
```

- `run` is the report's run id (the heading `# cca audit report: <run-id>`), and
  `report` is the report's revision line, `sha256:<hex>`, so a result answers one report.
- Values are one line each, with no tab. Lines end in LF or CRLF; a leading byte order
  mark is ignored. A value of any length is one value.
- At least one entry. Each id once. The keys of an entry, once each and in the order
  shown; `env` is required on a claim entry and not allowed on a finding entry.
- `query` is the check as it ran. `where` is free text for the location. For a claim,
  the derivation reads `env`, not `where`.
- A result that is more than one line, such as the rows a query returns, goes in a file:
  `- result_file: <path>` in place of `- result:`, at the same position. An entry has
  exactly one of the two. The path is relative to the directory of the `--live` file
  and is written to stay under it: not absolute, no drive letter, and no `..` component.
  The test is on the path as written: a symlink in that directory is followed, and a
  file beside the `--live` file, such as an `.env`, is accepted. A copy goes to Codex and
  into the report, so read a `--live` file someone else wrote before you import it, and
  keep it in a directory that holds only its results. Leading spaces of the path are
  ignored. The file is kept byte for byte, so it may hold any text; it must not be
  empty.

## What `check` validates

`sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/live.sh check <file> <report.md>` prints
`live: ok` and exits 0, or prints one line per error, `live <file>:<line>: <message>`,
in line order, to stdout and exits 1. It exits 2, with one line `live: <what failed>` on
stderr, on a usage error, an unreadable file or report, no `sha256sum` or `shasum`, or a
report that lacks its first line `revision: sha256:<hex>` or its heading
`# cca audit report: <run-id>`. It checks:

- The report itself: the SHA-256 of every byte after its first line (`tail -n +2`, as
  stage 8 computes it) equals its revision line. If not, the one line
  `live <report>:1: the revision line does not match the SHA-256 of the report body` is
  printed and nothing else is judged, since an edited body cannot pass under its old
  revision.
- The frontmatter: version 1 (`unsupported live version`), `run` equals the report's run
  id (`run '<x>' is not the report's run '<id>'`), and `report` equals its revision
  (`report '<x>' is not the report's revision 'sha256:<hex>'`). Also
  `missing frontmatter: the first line must be ---`, `frontmatter is not closed` (at the
  first entry heading when the closing `---` is missing),
  `missing frontmatter key '<key>'`, `duplicate frontmatter key '<key>'`,
  `unknown frontmatter key '<key>'`, and `frontmatter key '<key>' has an empty value`.
- Each heading names a `#### live <id>` block of the report:
  `'<id>' is not a live check of the report`. Also `duplicate id '<id>'` and
  `heading has no id`.
- The entry's `query` equals the block's `query` exactly, after removing trailing
  spaces, since a result of another query settles nothing:
  `query does not match the report's query for '<id>'`.
- A claim entry's `env` equals the block's `env` exactly:
  `env '<x>' does not match the report's env '<y>'`.
- Keys: `missing key '<key>'` (at the entry's heading; for the result,
  `missing key 'result' or 'result_file'`), `unknown key '<key>'`,
  `duplicate key '<key>'`, `key '<key>' is out of order`,
  `keys 'result' and 'result_file' are both given`,
  `key 'env' is not allowed on a finding entry`, `key '<key>' has an empty value`, and
  `approved_at must start with YYYY-MM-DD`.
- Lines: `tab in line`, `unrecognized line`, and `no entries` (at the last line).
- A `result_file` path that is absolute, has a drive letter, or has a `..` component:
  `result_file '<path>' is not a relative path under the live file's directory`.
- Each `result_file`, only when nothing above found an error, so the lines stay in line
  order: `result_file '<path>' is not a readable file` (missing, unreadable, or not a
  regular file) and `result_file '<path>' is empty`, at the `result_file` line.

## Imports and their state

Everything is under `<run dir>/live/`. The results files are the record of what was
imported; no separate log of imports is kept, so there is no gap between a file and its
record.

- `live/results-<k>.md` is an import once it exists under that name. `<k>` is one more
  than the highest `<k>` present, compared as a number (`results-10.md` follows
  `results-9.md`). Results files are never moved or deleted, so a committed `<k>` is never
  reused, and an approval's `source`, `live/results-<k>.md:<line>` (the line of the
  entry's `## ` heading), names one file for the life of the run. A copy named
  `live/results-<k>.md.pending` was never committed and has no approval: nothing reads
  it, `import` and `retire` remove it, and its number may be taken again.
- `live/results-<k>/` holds the import's result files, when an entry has a `result_file`:
  `<line>.txt` is the copy for the entry whose `## ` heading is at `<line>`, so the copy
  of the result at source `live/results-<k>.md:<line>` is `live/results-<k>/<line>.txt`.
  `SHA256SUMS` lists each copy as `<hex>  <line>.txt`, in line order, hashed from the
  copy. The kept `.md` still names the user's path; the copy is the record. The
  directory is committed with its `.md`: a `live/results-<k>.pending/` directory, or a
  `live/results-<k>/` without its `live/results-<k>.md`, was never committed, and
  `import` and `retire` remove it. Like the results files, the copies are never moved,
  changed, or deleted.
- `live/retired.md` is append-only: one line `<k> retired <time>: <reason>` per import
  whose findings or claims a rerun replaced, `<k>` a number without a leading zero. An
  import is **active** when it exists and is not retired. Any other line in the file
  makes every mode that reads it exit 1 with
  `live: live/retired.md:<line>: not a retirement record`.
- `live/findings.md` (finding ids), `live/claims.md` (`claim <n>` ids), and
  `live/carried/<id>.md` are state rebuilt from the active imports; none is a source of
  truth. A derived file is `## <id>` sections in winner order (below), LF only, every line
  ending in LF (the last included), no blank line. A section is `## <id>`,
  `- source: <source>`, `- earlier: <source>, <source> | none`, then one or more
  derivation lines, none empty or starting `## `. A section runs to the line before the
  next `## ` line or the end of the file, so sections concatenate byte for byte. A
  derived file is never created empty: with no section it is removed.
- A malformed derived file makes `active` and `assemble` exit 1, since it is state. Each
  error is one line, in line order, `findings.md` before `claims.md`:
  `live: live/<name>.md:<line>: <message>; delete the file to rebuild it`, where
  `<message>` is one of `carriage return`, `empty line`, `no final newline`,
  `line before the first section`, `section '<id>' twice`,
  `line 2 of a section must be '- source: <source>'`,
  `line 3 of a section must be '- earlier: <sources>'`, or `no derivation lines` (at the
  section's heading, reported when the section ends). Deleting the file is the repair: the
  next reconcile rebuilds it from the imports.
- The **winner** of an id is its entry in the active import with the highest `<k>`;
  `earlier` lists the entries of the lower `<k>` in increasing order. Winner order is the
  order of each id's first appearance across the active imports, in `<k>` then line
  order. A winner is `kept` when the derived file already holds a section for the id with
  the same `- source:` line, `changed` when the section names another source, and `new`
  when there is no section or no file.

## Carried findings

A rerun of stage 6 or 7 regenerates `X<n>` and `L<n>`, so an id with a result could name
another finding afterwards. A result for `X<n>` or `L<n>` therefore carries the finding
in `live/carried/<id>.md`, written once and never changed: the first reconciliation that
meets an active result for the id runs `live.sh carry`, which copies the finding's block
verbatim from the ledger file that holds it (`ledger/6.md` for `X<n>`, `ledger/7.md` for
`L<n>`). Later results for the same id reuse that file, since after the first rerun the
ledger holds only a position or verdict for the id. When the file is missing and the
ledger no longer holds the block, `carry` exits 1 and resume stops with its line.

The id is reserved. On the rerun, stage 6 numbers its additions after the highest carried
`X<n>`, and the late adversary after the highest carried `L<n>`. A carried finding goes
through the live review like any other (`stages/6-second-opinion.md`,
`stages/7-converge.md`): stage 6 gives it a position, the late adversary a verdict, and
the merger absorbs it. Retiring the imports moves `live/carried/` away with the derived
files, since the rerun that retires them may regenerate those ids.

## The modes

The orchestrator runs each mode as
`sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/live.sh <mode> ...` (the resolved absolute
path), and never edits anything under `live/` itself. All modes run under `LC_ALL=C`, so
listings and sorting are byte order. A usage error, an unreadable input, or any failed
operation (`cp`, `mkdir`, `mv`, `rm`, a temp file write, `jq`) exits 2 with one line
`live: <what failed>` on stderr. Exit 1 is a validation or state error a mode names, one
line each on stdout, leaving the committed imports, `live/retired.md`, the carried files,
the derived files, and `stages.json` unchanged. The only writes an exit 1 may leave are
`import`'s: the uncommitted files and directories it removed, and a `live/` it created,
empty.
`assemble` and `carry` write nothing at all on exit 1. Files are written only through a
temp file in the target's directory and a rename. Resume stops, with the script's lines,
on any nonzero exit, before it supersedes or reruns anything. A rerun after a failure
completes the work, so recovery is running resume again.

- `import <file> <report.md> <run dir>`. Removes what an earlier import left
  uncommitted (`live/results-*.md.pending`, and the result directories above); checks
  `live/retired.md`, the derived files, and the result copies of the active imports, as
  `active` does, and exits 1 with those lines on a failure, before it writes anything
  else; copies the
  file to `live/results-<k>.md.pending`, creating `live/` when missing; runs the `check`
  logic on the copy, its lines naming `<file>` as given and each `result_file` resolved
  against `<file>`'s directory; on exit 1 removes the copy and prints the lines. On exit
  0, when an entry has a `result_file`, it copies each file to
  `live/results-<k>.pending/<line>.txt`, tests each copy again (a file emptied since the
  check gives `result_file '<path>' is empty` and exit 1, removing both pending copies),
  writes `SHA256SUMS` from the copies, and renames the directory to `live/results-<k>/`.
  Then it renames the file to `live/results-<k>.md` and prints
  `live: imported live/results-<k>.md`. That last rename is the commit point, and the
  bytes validated are the bytes kept. A missing run directory is exit 2. So is a missing
  `jq` (`live: jq not found`), checked before anything is written, since the reconcile that
  follows runs `active`, which needs it.
- `active <run dir>`. Read only; prints nothing when `live/` is missing. Tab-separated
  lines, in this order:
  - `approve<TAB><source><TAB><id><TAB><approved_by><TAB><approved_at>` for each entry of
    each active import, in `<k>` then line order, whose source is not the `source` of an
    `approvals` entry of kind `live` in `stages.json` (read with `jq`; a missing
    `stages.json` counts as no approvals, and `jq` failing on one that exists is exit 2);
  - `carry<TAB><id><TAB>ledger/<6|7>.md` for each winning `X<n>` or `L<n>` with no
    `live/carried/<id>.md`, in winner order;
  - `winner<TAB><id><TAB><source><TAB><earlier><TAB><kept|new|changed>` for each id in
    winner order; `<earlier>` is the sources, `, `-separated, or `none`.
  A malformed `live/retired.md` or derived file is exit 1. So is a result copy that does
  not hold up, for each active import with a `result_file` entry, in `<k>` order:
  `live: live/results-<k>/SHA256SUMS is missing`,
  `live: live/results-<k>/SHA256SUMS does not list the result files of live/results-<k>.md`
  (it must list exactly `<line>.txt` for each such entry, in line order),
  `live: live/results-<k>/<line>.txt is missing`, or
  `live: live/results-<k>/<line>.txt does not match live/results-<k>/SHA256SUMS`.
  `assemble` and `import` run the same checks first, so a retried `--live` never commits
  another import over broken state. A retired import is not checked. To recover, resume with
  `--from 5` or earlier, which retires the imports, then import the results again.
- `carry <run dir> <id>`. `<id>` is `X<n>` or `L<n>` (anything else is a usage error,
  exit 2). Cuts the block that starts at the line beginning `### <id>: ` in `ledger/6.md`
  (`X`) or `ledger/7.md` (`L`) and runs to the next `## ` line or `### <word>: ` line (the
  cut `stages/7-converge.md` step 7.2 uses; `### ` subheadings without a colon stay
  inside), and writes it to `live/carried/<id>.md`, creating `live/carried/`. Exit 1,
  writing nothing: `live: live/carried/<id>.md exists`, or
  `live: no block for <id> in ledger/<n>.md`.
- `assemble <run dir> <entries dir>`. Reads the orchestrator's new and changed entries,
  one `*.md` file each (a missing directory holds none). An entry is LF only: a first
  line `## <id>`, then one or more lines, none empty or starting `## `, `- source:`, or
  `- earlier:`; a missing final LF is added when it is written. It exits 1 and writes
  nothing, with these lines, the entry files in byte order of name and each file's errors
  in line order, then the winner errors in winner order (`<f>` is the entry file's name):
  - `live: <f>:1: first line must be '## <id>'`
  - `live: <f>:<line>: carriage return`, `empty line`, `line starts with '## '`,
    `line starts with '- source:'`, `line starts with '- earlier:'`
  - `live: <f>: no derivation lines`
  - `live: <f>: '<id>' is not a new or changed winner`
  - `live: <f>: '<id>' is also in <earlier f>`
  - `live: no entry for '<id>'` (a `new` or `changed` winner)
  - `live: live/carried/<id>.md is missing` (an `X<n>` or `L<n>` winner)
  Otherwise it builds `live/findings.md` and `live/claims.md`, each in winner order: a
  `kept` id's section copied byte for byte from the current file; a new or changed id's
  written as `## <id>`, the winner's `- source:` and `- earlier:` lines, then the entry's
  lines. A current section whose id wins nothing is dropped. A file is written only when
  its bytes change and removed when it has no section. It prints
  `live: <kept|wrote|removed|absent> live/findings.md`, then the same for
  `live/claims.md`, then removes `<entries dir>`. After a failure between the two files,
  the next `active` reports the written file's ids `kept` and the rest as before, so a
  rerun finishes the job.
- `retire <run dir> <dest dir> <reason>`. The reason is one line and not empty (else
  exit 2). First reads and checks `live/retired.md`, and on a malformed line exits 1
  having changed nothing. Then removes what an import left uncommitted, as `import`
  does; creates
  `<dest dir>` when there is something to move (and exits 2 if a name already exists
  there); appends `<k> retired <time>: <reason>` (time from `date -u +%Y-%m-%dT%H:%M:%SZ`)
  to `live/retired.md` for each active import, in `<k>` order, through a temp copy and a
  rename; then moves `live/findings.md`, `live/claims.md`, and `live/carried/`, those
  present, into `<dest dir>`. The results files and `live/retired.md` stay, so every
  approval's source still resolves. Prints `live: retired <k>` per import, then
  `live: moved live/<name>` per move. Each step is idempotent: a rerun after a failure
  appends nothing for an import already retired and moves what is left, possibly into the
  next `superseded/<k>/live/`, so every moved file stays under `superseded/`.

## Reconciling

Resume reconciles on every resume, with or without `--live`, when `live/` exists
(`stages/resume.md`, step 4.4). The order is fixed, so no entry lists its own source, a
later result never loses to an earlier one, a claim-only import leaves `live/findings.md`
byte for byte as it was, and a derived file deleted by hand is rebuilt from the imports:

1. `live.sh active <run dir>`.
2. Record each `approve` line in `stages.json` `approvals`: kind `live`, target the id,
   decision `approved`, time `approved_at`, plus `by` (the approver) and `source`. The
   script lists only sources not yet recorded, so a repeat records nothing.
3. `live.sh carry <run dir> <id>` for each `carry` line.
4. Remove `<run dir>/tmp/live-entries/` if present. For each `new` or `changed` winner,
   derive its entry from the winning result ("Derivation") and write it to a file there,
   named by the winner's number (`1.md`, `2.md`, ... in winner order), holding `## <id>`
   and the derivation lines. A `kept` winner gets none.
5. `live.sh assemble <run dir> <run dir>/tmp/live-entries`.

The orchestrator runs no query itself.

## Derivation

The orchestrator derives each entry from the finding's own `live check` field ("what each
result changes"). The validator has already matched the query and, for a claim, the
environment. The result is the entry's `result` line, or for a `result_file` entry the
whole copy `live/results-<k>/<line>.txt`, read in full (in slices when it is large),
never the user's original file.

- A finding: exactly one stated outcome matches the result. A result that shows the
  defect gives `verified fact` at the severity that outcome names (else the finding's
  own); one that shows it absent gives `dropped`. Write the derivation as one line, for
  example `verified fact, high: <why the result shows it>` or `dropped: <why>`.
- None or several stated outcomes match, or `where` names another place than the check:
  `unchanged: no stated outcome matches` (or `unchanged: ran elsewhere`).
- An env claim: the result shows the stated result: `true, reproduced`; it contradicts it:
  `false, contradicted`; else `not verified, not reproduced` with the reason.
- Every finding entry goes to review. A live check exists because the finding is an
  `unverified assumption`, so a conclusive result changes its label, and the gate
  (`stages/7-converge.md`, step 4) keeps the finding provisional until the live review has
  completed.

Each entry line cites its basis as `live result, approved by <who> at <time>`, with the
source, and for a `result_file` entry the copy's path, `live/results-<k>/<line>.txt`. A
derivation is a proposal for the reviewers, never a verdict.

A copy is a reviewer input. The **result copies** of a derived file are the copies of
its sections' `- source:` entries that have one. Each review of a live result gets the
result copies of the derived files it reads, so it judges the result itself, not a
summary of it: the second opinion (stage 6) those of `live/findings.md`, and the late
adversary (stage 7) those of `live/findings.md` and `live/claims.md`. Stage 8 reads them
for the report. The merger does not get them: it merges the positions the reviews gave,
and the derivation lines name each copy. They are not hashed as stage inputs: a copy
never changes, `active` checks it against `SHA256SUMS` before any reconcile, and a new
result changes the `- source:` line, which the derived file's hash already covers.
