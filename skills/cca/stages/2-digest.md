# Stage 2: digest

Runs alongside stages 3 and 4, from the moment stage 1 completes. Agents:
`cca:digester`, one per chunk of about 450 KB. The digests are pointers for auditors:
auditors cite the original document at its pinned sha, never the digest.

## Steps

1. **Applicability.** When `audit-brief.md` lists no source of truth classed as a
   document corpus, write the stage 2 entry with status `not_applicable`, no outputs,
   and no agents, and stop here. The stage counts as satisfied for the barrier and is
   listed in Coverage.
2. **Entry.** Write the stage 2 entry as `running`, with inputs: the hashes of
   `audit-brief.md`, `common.md`, `claims.md`, and `groups.md`, the hash of every
   `diffs/<bundle>.stat`, the pinned sha of each document corpus, and
   `plugin_version`.
3. **Chunk each corpus.** For each document corpus `<source>`, at its pinned sha:
   1. List its tracked files with sizes: `git -C <repo> ls-tree -r -l --full-tree
      <sha>`.
   2. List its text files: `git -C <repo> grep -I -l -e "" <sha>` (paths come back as
      `<sha>:<path>`). A file in the tree but not in this list, with a size above 0, is
      binary: skip it and list it. Symlinks, submodules, and LFS pointers are listed
      as the brief records them and not chunked.
   3. Walk the text files in path order, grouped by directory. Add whole directories
      to the current chunk while it stays at or under 450,000 bytes. A directory that
      alone exceeds that is split by files in path order. A single text file over
      450,000 bytes is not one chunk: split it into byte ranges, each its own chunk and
      never combined with other files. A range is a chunk entry of the form
      `<path> bytes <start>-<end>` (0-based, end exclusive), at most 450,000 bytes. Walk
      the file from `start` 0: when the rest of the file is 450,000 bytes or fewer,
      `end` is the file size; otherwise `end` is `start` plus the byte count up to and
      including the last LF within the next 450,000 bytes, so no line is split.
      Compute every range boundary and line count from a file on disk, never through
      the model's output. An exported tree's file is measured in place, at
      `<run dir>/trees/<name>/<path>`, with no copy. For a directly read tree,
      materialize the file once, by shell redirect (`git -C <repo> show <sha>:<path>
      > <run dir>/tmp/<source slug>/<path>`), and measure that copy. Below, `<file>`
      is the file measured. The `tmp/` directory is run state, never an input or output
      of a stage: remove each copy once the chunk files for its ranges are written
      (3.4), and remove `<run dir>/tmp/` on every exit of step 3, including a stop or
      failure part way through. Measure the count with
      `tail -c +<start+1> <file> | head -c 450001 | sed '$d' | wc -c`. If that
      prints 0 (one line longer than the cap), cut at `start` plus 450,000 and mark
      the range `line split`. The next range starts at `end`.
   4. Number chunks from 1 across all corpora in source order. For chunk `N`, write
      `guidelines/chunk-N.md`: the source name, its sha, its read path and mode from
      the brief, the file list with sizes, the chunk's total bytes, and the corpus's
      skipped binary files (in the corpus's first chunk only). For a byte-range chunk,
      the file list has the one entry `<path> bytes <start>-<end>`, and the file also
      gives the range's first line number (the count of LF in bytes 0 to `start`, plus
      1: `head -c <start> <file> | wc -l`, plus 1), its line count
      (`tail -c +<start+1> <file> | head -c <end-start> | wc -l`, plus 1 when the
      range's last byte is not an LF, so an unterminated final line counts), and the
      file's total size. Then remove the `tmp/<source slug>/` copy, where one was made,
      of each file whose chunk files are all written.
   The chunk's scope id is `digest-N`. Keep the list of files split by range, with
   each file's ranges, for the stage 2 entry (step 6.2).
4. **Launch.** Queue one `cca:digester` per chunk (SKILL.md, Queue and Agent launch
   rules; digests launch after pass one). With `_test` `hold` naming stage 2, queue
   them but launch none until the named stage's initial agents have ended. The prompt
   gives the absolute paths of `audit-brief.md`, `common.md`, `claims.md`,
   `groups.md`, every `diffs/<bundle>.stat`, the chunk file
   `guidelines/chunk-N.md`, and the output file `guidelines/digest-N.md`, and says:
   read every file in the chunk in full, or for a byte-range chunk the range the chunk
   file names, read in slices of at most 24000 bytes (a Bash result is cut near 30,000
   characters), and end `status: failed at byte <offset>`, never `complete`, if the
   range was not read to its end; write a cited rule list with, for each rule, the
   rule text, its strength (`MUST`, `SHOULD`, or `MAY`), and `repo@sha:path:line`; and
   add a `potential finding:` line, naming the group, wherever a rule collides with a
   claim or the diff stat.
5. **On each completion.** Apply `_test` `fail` for role `digester` at scope
   `digest-N` or `any`. Read the output: its last line must be `status: complete`.
   On failure, apply the failure table (relaunch same model; relaunch on fable as a
   swap; then the scope fails). Record the agent in the entry. On success, hash the
   file with `git hash-object --no-filters guidelines/digest-N.md` and record it in the
   entry's `output_hashes` map (`"guidelines/digest-N.md": "<hash>"`). These are the
   final digest hashes the stage 4 reconciliation barrier compares with each pass-one
   report's `consumed:` list.
6. **End.** When every chunk is complete or failed:
   1. Run the read-only check (SKILL.md, Read-only check), which writes
      `baseline/2-check.md`.
   2. Write the stage 2 entry: status `complete` when every chunk completed, else
      `failed`, with the failed chunks and their files in a `failed_scopes` list;
      outputs: every `guidelines/chunk-N.md`, every completed `guidelines/digest-N.md`,
      and `baseline/2-check.md`; `output_hashes`; and `split_files`, a list with one
      object per file split by range: `{ "source": "<source>", "path": "<path>",
      "bytes": <size>, "ranges": ["<start>-<end>", ...], "chunks": [<N>, ...] }`, or an
      empty list. Stage 8 lists every `split_files` entry in the report's Coverage
      section (step 6.11 of `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/8-report.md`).
   3. Print the stage boundary line. With `_test` `expire_budget_after_stage: 2`, the
      budget expires now.
   4. Tell the barrier: go to the barrier step of `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/4-pass-one.md`
      for any group whose pass-one report is already complete.

A failed stage 2 counts as satisfied for the barrier, so the run goes on; its coverage
loss (the chunks never digested) is recorded and the run ends `partial`.
