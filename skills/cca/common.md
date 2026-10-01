# Common rules for this run

This file is copied into the run directory as `common.md` in stage 1, with the header
below filled in. Every agent in the run reads it. It is the single home of the finding
schema, the evidence rules, and the output contract; stage files and agent definitions
cite it and do not restate it.

```
run id: <run-id>
run directory: <absolute path>
tier: low | medium | high
questions:
- <id>: <question>
```

## Hard rules

These hold for every stage, for the orchestrator and every agent.

1. **Read-only boundary.** During `/cca:audit` and `/cca:resume`, nothing changes an
   audited repo's tracked files, untracked non-ignored files, the index, branches, tags,
   stashes, config, or remotes. "Audited repo" means every bundle, reference, and source
   of truth. Allowed writes: the run directory; cca's data directory (`runs.json`);
   codex-lite's own request and thread files in codex-lite's data directory, written
   when cca calls it; and `git fetch` into remote-tracking refs, after the user approves
   it once per run. Nothing else. An ignored file written by a check run that an agent
   logged under its `runs:` heading is allowed and reported, never silently.
2. **Prevention and detection.** Agent tool lists exclude Edit and NotebookEdit. An
   agent with Bash runs only these commands: `git show`, `git log`, `git diff`,
   `git grep`, `git ls-files`, `rg`, `ls`, `git hash-object --no-filters` (never `-w`)
   for the `consumed:` hashes, `cat` of an exported file with `tail -c`, `head -c`,
   `wc -c`, `sed '$d'`, and one `awk` line-numbering stage for a digester's byte range,
   and, when a question needs a run, the repo's test or lint commands, which may write
   ignored build output. This is instruction, not enforcement: nothing blocks Bash
   mechanically. The orchestrator snapshots every audited repo in stage 1 and compares
   after every stage. A change to tracked files, untracked non-ignored files, refs, the
   index, stashes, or config, including an added or deleted file, stops the run
   `blocked`, unless an approved fetch caused it. A change among ignored files that no
   logged run accounts for stops it too. Not detected: an ignored file replaced with
   one of the same size and a restored modification time, changes inside `.git/` other
   than refs, stashes, and config, and changes outside the audited repos. The user
   should not edit audited repos during a run, since their own edits trip the check
   too.
3. **No model, agent, or tool names** in anything external: commit messages, PR or
   ticket text, and drafted comments. The report is internal and may name them.
4. **No advisor tool**, in the orchestrator or any agent.
5. **Live data.** Credentials and live systems (databases, dashboards, production APIs)
   are used only when a question cannot be answered from code, and only after the user
   says yes to that access. Each access is logged in the report. A check not approved is
   listed in the report's Live checks section. An agent never asks for or uses live
   access itself; it writes a `live check` field, and the orchestrator asks the user.
6. **Evidence.** A claim is not a fact until evidence is cited (see Evidence).
7. **Disk first.** Every agent writes its output file before it reports back and
   returns only the path and a one-line status.
8. **Claims are not facts.** The session summary being audited, and every sentence in
   `claims.md`, is a claim to verify, never a source of truth.

## Evidence

Every piece of evidence names its repo and the commit it was read at. Three kinds:

- **Quote:** `repo@sha:path:line`, with the quoted lines.
- **Search:** the exact command, its scope, and its result, including an empty result.
  This is how absence is shown.
- **Run:** the exact command, where it ran, and the output, marked as cut where cut.
  Every run is logged under the agent's `runs:` heading.

Forge evidence is a URL with a quote. A finding separates what the evidence
**demonstrates** from what it **infers**. The label `verified fact` requires that the
defect itself is demonstrated, by a quote plus a causal explanation, or by a run.
Otherwise the label is `unverified assumption` and the severity may not exceed `medium`.
`convention` marks a finding that rests on a ranked source's rule, not on broken
behavior.

A digest (`guidelines/digest-N.md`) or a map (`domain/<source>-map.md`) is a pointer,
not evidence. Cite the original document or source at its pinned sha.

A finding with a `live check` keeps `unverified assumption` and its cap until the check
has run. A missing rationale in the ticket or PR is not by itself a defect. The diff is
always the three-dot diff in `diffs/<bundle>.diff`; never compare base and head with a
two-dot diff, which shows the base's later changes as reversals on the head.

### Reading trees and searching

`audit-brief.md` maps each bundle, reference, and source of truth to the path to read
and the sha it is pinned at.

- **Directly read tree** (the repo's own checkout, at the pinned sha with no tracked
  changes): search with `git -C <repo> grep <pattern> <sha>`, or with `rg` over the
  files `git -C <repo> ls-files` lists. Never search the working tree with a plain `rg`,
  which also sees untracked and ignored files. Do not follow a symlink outside the
  repo. A citation to an untracked, ignored, or outside path is invalid evidence.
- **Exported tree** (`<run dir>/trees/<name>/`): tracked files only, at the pinned sha.
  A symlink is a regular file holding its target; do not resolve it. Submodules are
  listed in the brief and absent. Git LFS files are their pointer files. Cite as
  `repo@sha:path:line` with the repo-relative path, not the export path. A check run
  that needs installed dependencies cannot run here; mark that question "not run".
- **Read by `git show`** (an export over 1 GB the user declined): read with
  `git -C <repo> show <sha>:<path>`. Only agents with Bash are assigned to it.

## Finding schema

Each finding uses exactly this block:

```
### <group>-F<n>: <one-line title>
- severity: blocker | high | medium | low | note
- question: Q1 | Q2 | Q3 | Q4 | <custom id>
- label: verified fact | unverified assumption | convention
- claims: <claim numbers tested, or none>
- evidence: <quote, search, or run, per Evidence>
- demonstrated: <what the evidence shows>
- inferred: <what follows from it but is not shown>
- what the code does:
- what breaks, and for whom:
- recommended change: <repo> <path> <change>
- alternatives: <each weighed, and the one recommended>
- live check: <query>; <where it runs>; <what each result changes>; or none
- work-item impact: <ticket, acceptance criterion, or none>
```

Ids and origin tags:

- Pass one: `<group>-F<n>`. A barrier top-up appended to `pass1/<group>.md` continues
  the numbering under a `## Top-up` heading.
- A new finding raised by a pass-two adversary is `<group>-P<n>` and adds the line
  `- origin: pass2` after the title.
- A finding written by a top-up auditor after a map correction, in
  `pass2/<group>-topup.md`, is `<group>-T<n>` and adds `- origin: topup`.
- A finding the second opinion adds is `X<n>` and adds `- origin: codex`; one the late
  adversary raises is `L<n>` and adds `- origin: late`.

Every finding with an origin line is a **late addition**.

## Verified OK list

Items checked and found sound, each with evidence:

```
## Verified OK
- <group>-OK<n>: <what was checked>; evidence: <quote, search, or run>
```

## Claims list

Each claim assigned to the group in `claims.md`:

```
## Claims
- claim <n>: true | false | not verified; <finding id, or evidence>
```

`not verified` gives the reason, such as "needs a live check".

## Pass-two verdicts

An adversary gives each finding exactly one verdict, with evidence:

- `survives`: the finding stands as written.
- `downgraded`: the finding stands at a lower severity or a weaker label; give both.
- `reworded`: the defect is real but the title, scope, or reasoning is wrong; give the
  corrected text.
- `dropped`: the finding is wrong; give the counter-evidence.

```
### verdict on <finding id>: survives | downgraded | reworded | dropped
- severity: <old> -> <new> | unchanged
- label: <old> -> <new> | unchanged
- evidence: <quote, search, or run>
- reason:
```

After the verdicts, a pass-two adversary attacks the Verified OK list as the tier
allows (`## Verified OK challenged`, one line per item with its result), then writes
`## Coverage gaps` and `## Map corrections`: map file, line, what is wrong, and the
source quote that shows it, or `none`.

## Output contract

Every agent:

1. Writes one output file, at the path its prompt names, and no other file.
2. Lists every command it ran under a `runs:` heading, one per line: the command, the
   directory it ran in, and the exit status. `runs: none` when there were none.
3. Lists every digest and map file it read under a `consumed:` heading, one per line:
   the run-directory path and its hash from `git hash-object --no-filters <file>`.
   `consumed: none` when there were none.
4. Ends the file with the line `status: complete`, as its last line.
5. Returns only the output path and one line of status.

The merger alone may add an optional `opened:` heading, before `consumed:`, listing
each ledger file or section it opened (the path and the reason, one per line). It is not a
`runs:` entry, since the merger has no shell and `runs:` stays command, directory, and
exit status, or `none`.

A file without `status: complete` as its last line is a failed output, whatever the
agent returned.

```
runs:
- git -C /abs/app grep -n "limit" 1a2b3c4; /abs/app; exit 0
consumed:
- guidelines/digest-1.md 9f8e7d6c5b4a39281706f5e4d3c2b1a098765432
status: complete
```
