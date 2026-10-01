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
      alone exceeds that is split by files in path order. A single file over the cap
      is a chunk of its own. Never split a file.
   4. Number chunks from 1 across all corpora in source order. For chunk `N`, write
      `guidelines/chunk-N.md`: the source name, its sha, its read path and mode from
      the brief, the file list with sizes, the chunk's total bytes, and the corpus's
      skipped binary files (in the corpus's first chunk only).
   The chunk's scope id is `digest-N`.
4. **Launch.** Queue one `cca:digester` per chunk (SKILL.md, Queue and Agent launch
   rules; digests launch after pass one). With `_test` `hold` naming stage 2, queue
   them but launch none until the named stage's initial agents have ended. The prompt
   gives the absolute paths of `audit-brief.md`, `common.md`, `claims.md`,
   `groups.md`, every `diffs/<bundle>.stat`, the chunk file
   `guidelines/chunk-N.md`, and the output file `guidelines/digest-N.md`, and says:
   read every file in the chunk in full; write a cited rule list with, for each rule,
   the rule text, its strength (`MUST`, `SHOULD`, or `MAY`), and
   `repo@sha:path:line`; and add a `potential finding:` line, naming the group,
   wherever a rule collides with a claim or the diff stat.
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
      and `baseline/2-check.md`; `output_hashes`.
   3. Print the stage boundary line. With `_test` `expire_budget_after_stage: 2`, the
      budget expires now.
   4. Tell the barrier: go to the barrier step of `${CLAUDE_PLUGIN_ROOT}/skills/cca/stages/4-pass-one.md`
      for any group whose pass-one report is already complete.

A failed stage 2 counts as satisfied for the barrier, so the run goes on; its coverage
loss (the chunks never digested) is recorded and the run ends `partial`.
