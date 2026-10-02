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
   when cca calls it; `git fetch` into remote-tracking refs, after the user approves it
   once per run; and, for a bundle with `head: working-tree`, the loose git objects that
   `working-tree.sh build` writes in the repo's object store (stage 1 step 1c, and resume
   step 3 when it rebuilds the head), which the report discloses. Nothing else. An ignored
   file written by a check run that an agent logged under its `runs:` heading is allowed
   and reported, never silently.
2. **Prevention and detection.** Agent tool lists exclude Edit and NotebookEdit. An
   agent with Bash runs only these commands: `git show`, `git log`,
   `git diff <base>...<head>`, `git grep`, `git ls-files`, `rg`, `ls`,
   `git hash-object --no-filters` (never `-w`) for the `consumed:` hashes, `cat` of an
   exported file with `tail -c`, `head -c`, `wc -c`, `sed '$d'`, and one `awk`
   line-numbering stage for a digester's byte range, and, when a question needs a run in
   a directly read tree, the repo's test or lint commands, which may write ignored build
   output. A diff always names two commits: a working-tree `git diff` refreshes the index
   even with `--no-optional-locks`, so it is never run. In a bundle with
   `head: working-tree`, `git grep` always names the head sha, since a plain `git grep` or
   an `rg` over `git ls-files` would miss the untracked files that are part of the head.
   The orchestrator's `git status` runs as `git -C <repo> --no-optional-locks status ...`,
   and the snapshot script sets `GIT_OPTIONAL_LOCKS=0`, so no status check rewrites the
   index. This is instruction, not enforcement: nothing blocks Bash mechanically. The
   orchestrator snapshots every audited repo in stage 1 and compares after every stage. A
   change to tracked files, untracked non-ignored files, refs, the index, stashes, or
   config, including an added or deleted file, stops the run `blocked`, unless an approved
   fetch caused it. A change among ignored files that no logged run accounts for stops it
   too. Not detected: an ignored file replaced with one of the same size and a restored
   modification time, changes inside `.git/` other than refs, stashes, and config, a
   change to a nested repository's refs other than its HEAD, its stashes, or its config, a
   change inside a repository that sits in an ignored directory, such as a linked
   worktree, other than an entry added or removed at its top level, and changes outside
   the audited repos. The user should not edit audited repos during a run, since their own
   edits trip the check too.
3. **No model, agent, or tool names** in anything external: commit messages, PR or
   ticket text, and drafted comments. The report is internal and may name them.
4. **No advisor tool**, in the orchestrator or any agent.
5. **Live data.** Credentials and live systems (databases, dashboards, production APIs)
   are used only when a question cannot be answered from code, and only after the user
   says yes to that access. Each access is logged in the report. A check not approved is
   listed in the report's Live checks section. An agent never asks for or uses live
   access itself; it writes a `live check` field, and the orchestrator asks the user. The
   result of a check the user ran comes back in a `--live` file (`live.md`), and its
   approval is recorded from that file, never asked for again.
6. **Evidence.** A claim is not a fact until evidence is cited (see Evidence).
7. **Disk first.** Every agent writes its output file before it reports back and
   returns only the path and a one-line status.
8. **Claims are not facts.** The session summary being audited, and every sentence in
   `claims.md`, is a claim to verify, never a source of truth.

## Evidence

Every piece of evidence names its repo and the commit it was read at. Four kinds:

- **Quote:** `repo@sha:path:line`, with the quoted lines.
- **Search:** the exact command, its scope, and its result, including an empty result.
  This is how absence is shown.
- **Run:** the exact command, where it ran, and the output, marked as cut where cut.
  Every run is logged under the agent's `runs:` heading.
- **Live result:** the result of an approved live check, fed back with `--live` and cited
  by its `live/` file and line (`live/results-<k>.md:<line>`, or the carried file for a
  finding the ledger no longer holds), and for a result kept as a file, by its copy
  `live/results-<k>/<line>.txt`. It counts as a run the approver made, so it can
  demonstrate a defect. It is evidence only after it has passed the review gate
  (`stages/7-converge.md`, step 4).

Forge evidence is a URL with a quote. A finding separates what the evidence
**demonstrates** from what it **infers**. The label `verified fact` requires that the
defect itself is demonstrated, by a quote plus a causal explanation, or by a run.
Otherwise the label is `unverified assumption` and the severity may not exceed `medium`.
`convention` marks a finding that rests on a ranked source's rule, not on broken
behavior.

A digest (`guidelines/digest-N.md`) or a map (`domain/<source>-map.md`) is a pointer,
not evidence. Cite the original document or source at its pinned sha.

A finding with a `live check` keeps `unverified assumption` and its cap until a live
result for it has passed the review gate. A missing rationale in the ticket or PR is not
by itself a defect. The diff is always the three-dot diff in `diffs/<bundle>.diff`; never
compare base and head with a two-dot diff, which shows the base's later changes as
reversals on the head.

### Reading trees and searching

`audit-brief.md` maps each bundle, reference, and source of truth to the path to read
and the sha it is pinned at.

- **Directly read tree** (the repo's own checkout, at the pinned sha with no tracked
  changes): search with `git -C <repo> grep <pattern> <sha>`, or with `rg` over the
  files `git -C <repo> ls-files` lists. Never search the working tree with a plain `rg`,
  which also sees untracked and ignored files. Do not follow a symlink outside the
  repo. A citation to an untracked, ignored, or outside path is invalid evidence, except
  as the next item says.
- **Working-tree bundle** (`head: working-tree`; the brief's mode is
  `direct (working tree)`): the head is a commit built from the working tree, with no
  ref, so it holds the modified files and the untracked files that are not ignored.
  Search it only with `git -C <repo> grep <pattern> <head sha>`, never with `rg` over
  `git ls-files`, which misses the untracked files. The files the brief lists as
  untracked at audit time are part of the head and valid evidence, cited at the head sha
  as `repo@sha:path:line`; an ignored or outside path is still invalid. When the brief
  lists a path as flagged at audit time, the bundle is read from an export of its head
  instead (mode `export`), which holds the untracked files too and each flagged path at
  its index version, not the local file. A flagged path in a submodule is absent, as
  every submodule path is.
- **Exported tree** (`<run dir>/trees/<name>/`): tracked files only, at the pinned sha.
  The export of a working-tree bundle's head also holds the files the brief lists as
  untracked at audit time, which are valid evidence as the item above says.
  A symlink is a regular file holding its target; do not resolve it. Submodules are
  listed in the brief and absent. Git LFS files are their pointer files. Cite as
  `repo@sha:path:line` with the repo-relative path, not the export path. No test or lint
  command runs in an export, whether or not it needs installed dependencies; mark that
  question "not run".
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

## Claim kinds

Every claim in `claims.md` has a kind. For a handoff, the kind comes from the handoff's
own script, never from judgment. For prose, the first rule that applies types the
sentence:

1. `verification`: says something was checked, tested, verified, confirmed, reproduced, or
   passes.
2. `decision`: states a choice made or rejected, a deferral, or who decided.
3. `scope`: says what belongs in or out of the bundle, or ranks a ticket for inclusion.
4. `status`: a work item's type, state, iteration, owner, or links.
5. `code`: any other checkable statement about code, data, or behavior.

A claim's target in `claims.md` is a group id from `groups.md`, or `hygiene`. Every
`scope` and `status` claim targets `hygiene`; the stage files say which scope receives
those claims.

## Claims list

Each claim assigned to the scope in `claims.md`:

```
## Claims
- claim <n>: true | false | not verified; <finding id, or evidence>
```

`not verified` gives the reason, such as "needs a live check". A `verification` claim uses
these lines instead:

```
- claim <n>: true, reproduced; <the run or quote that reproduces the stated result>
- claim <n>: false, contradicted; <evidence>
- claim <n>: not verified, not reproduced; <why: not run, no access, needs a live check, budget expired, exported tree, or setup differs>
```

A `verification` claim is `true` only when you reproduced the stated result yourself, by a
run, or by a quote when the stated result is a fact of the code at the pinned sha. A quote
of other text saying it was checked is not a reproduction. `false` needs counter-evidence.
A run under a different setup than the stated check needs is not counter-evidence: another
directory, a missing environment variable, service, or account, or another environment
than the one the statement names. The claim is then `not verified, not reproduced`, and
the reason names what differs. Reproducing a result does not show that the build session
ran its stated check; the report says so once in its Claims section.

## Env claims

An env claim is a `verification` claim whose check part, the text after the first
`; check: ` of its entry, starts with `env: ` (`env: <name>; <check>`, as `handoff.md`
defines it). The rule is mechanical: stage 1 adds no marker to `claims.md`. The check
ran against the environment `<name>`, which the audit cannot reach, so a run here is a
run against another environment. Pass one writes it
`not verified, not reproduced; needs a live check: env <name>`, never `true` or `false`
from a run here. The report lists each env claim by claim number in its Live checks
section, with its environment and command, and `claims-verdicts.md` gives it the verdict
`not reproducible here` until a live result settles it (`live.md`).

## Decisions

Every scope writes `## Decisions` after `## Claims`: one line for every `decision` claim
assigned to the scope, by claim number, or `none` when the scope has none.

```
## Decisions
- claim <n> (<handoff ref or none>): <class>; resolution: <taken | open deferral | settled later by <record>>; alternatives weighed: <yes, <evidence> | no>; authority: <person: <name> | role: <role> | checkpoint | not recorded>; tracked by: <where | nothing>; work depends on it: <yes, <why> | no>; reversibility: <reversible | hard to reverse | contract change>; recommendation: <text>; finding: <finding id or none>
```

Read three dimensions from the record, then the class follows.

- Resolution: `taken` (status `taken` or `default taken`), `open deferral` (status
  `deferred` or `deferred to <owner>`), or `settled later` (a deferral that a later
  commit, comment, ticket field, or document shows decided; treat it as `taken`, with that
  record as `recorded_at`).
- Authority: `person: <name>`, `role: <role>`, `checkpoint`, or `not recorded`. For a
  deferral, the owner in `deferred to <owner>`, judged the same way.
- Evidence: alternatives weighed, or not. Weighed means you read, in a record you can open
  (a commit body in a bundle, a ticket or PR comment in the forge data, or a document at a
  pinned sha), at least one alternative with the reason it was not taken. The handoff's own
  `rejected: ...; why:` lines are claims, not that record: a `recorded_at` you opened and
  found to support them counts; a `checkpoint:` pointer or `not recorded` cannot be opened,
  so the entry says `alternatives weighed: no (not in a readable record)`.

Class, the first that holds:

1. `stale deferral`: an open deferral with no `person:` owner, or that nothing in the forge
   data or the repos tracks (no ticket, comment, or document names it as open).
2. `needs <owner>`: an open deferral with a `person:` owner that the record tracks; or a
   taken decision whose reversibility is `hard to reverse` or `contract change` and whose
   authority is not `person:`. `<owner>` is the deferral's owner, else the person or role
   the tickets or threads name for it, else `owner (not recorded)`.
3. `default taken`: a taken decision without alternatives weighed.
4. `evidenced`: a taken decision with alternatives weighed.

Every decision lands in exactly one class: an open deferral is 1 or 2; a taken decision is
2, 3, or 4. A prose claims file's decision sentences are classed the same way, from what
the record shows.

## Scope

A scope that holds `hygiene` claims (`hygiene`, `tests-hygiene`, `combined`) also writes
`## Scope` after `## Decisions`: one line for every `scope` claim, or `none` when there is
none.

```
## Scope
- claim <n> (<handoff ref or none>): introduced by the bundle: <yes | no | partly>, <evidence against the merge-base>; fix inside the bundle's repos: <yes | no, <repo>>; cost: <small | medium | large>, <why>; recommendation: <include | defer>, <reason>; handoff ranking: <rank and confidence, or none>; facts disagree with the handoff: <yes, <what the handoff states that the evidence contradicts> | no>; recommendation differs from the handoff: <yes | no>; finding: <finding id or none>
```

Decision and scope entries are report items, not findings. They never enter `ledger/5.md`,
`ledger/6.md`, or `ledger/7.md`, have no review gate, and never change the verdict counts.
An entry the auditor did not write is `not assessed`, and one the adversary left without a
line is `not challenged`; neither fails a scope. The agents still write every entry and
line.
When an entry shows a defect (a `stale deferral` or `needs <owner>` the bundle's work
depends on, or a scope fact that ships a regression), file a separate Q4 finding and name it
in the entry's `finding:` field. A defect the adversary finds first is a pass-two addition
(`<group>-P<n>`). Those findings go through the gate like any other.

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

At every tier, after `## Map corrections`, the adversary writes three challenge sections:

```
## Claims challenged
- claim <n>: upheld | overturned to <true, reproduced | false, contradicted | not verified, not reproduced>; evidence: <...>
## Decisions challenged
- claim <n>: agree | disagree, <class>; evidence: <...>
## Scope challenged
- claim <n>: agree | disagree, <what differs>; evidence: <...>
```

`## Claims challenged` has a line for every `verification` claim the report marks true, and
may add any other claim the adversary finds misjudged. `## Decisions challenged` and
`## Scope challenged` have a line for every entry of the report's `## Decisions` and
`## Scope`. Each heading is present, with `none` only when the report gives nothing to
challenge under it. A `disagree` line names the class or the field it disputes. Challenge
lines are not findings and are not in the ledger files.

## Output contract

Every agent:

1. Writes one output file, at the path its prompt names, and no other file. A pass-one
   file holds, in order, its findings, `## Verified OK`, `## Claims`, `## Decisions`,
   and, in a scope that holds `hygiene` claims, `## Scope`. A pass-two file holds its
   verdicts, `## Verified OK challenged`, `## Coverage gaps`, `## Map corrections`,
   `## Claims challenged`, `## Decisions challenged`, and `## Scope challenged`.
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
