# Handoff format

A handoff is the build session's typed record of a bundle of work: per ticket, its fields,
the problem, the decision, the commits, and what the session says it verified; per
decision, its rationale, options, who decided, where it is recorded, and its status; per
ticket raised during the work, how confident the session is that it belongs in the bundle.
`/cca:handoff` writes one. `/cca:audit` reads one given as a claims file (`--claims` or the
manifest's `claims`), checks it with `${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/handoff.sh`,
and turns every item into a typed claim. A handoff is a set of claims to verify, never a
source of truth.

This file is the single home of the format. `commands/handoff.md`,
`skills/cca/stages/1-orient.md`, and `skills/cca/scripts/handoff.sh` follow it.

## Layout

A handoff is a UTF-8 markdown file. LF or CRLF line endings are accepted: one CR before each
LF is removed before parsing, and line numbers stay physical. A UTF-8 byte order mark at
the start of the first line is ignored. Every value sits on one line and holds no tab.

```
---
cca-handoff: 1
generated: <ISO 8601 time>
---

# Handoff: <title>

## Bundles

- <bundle name>: repo <path>; pr <id or none>; branch <branch>; base <base ref>

## Tickets

### <ticket id>
- type: <work item type>
- state: <state>
- iteration: <iteration path, or none>
- owner: <assigned person, or none>
- bundles: <bundle name>[, <bundle name>...]
- problem: <the problem or gap>
- decision: <the solution that was decided>
- commits:
  - <bundle name> <sha>: <what the commit does and why, one line>
- verified:
  - <a statement the build session says it checked>; check: <the command, query, or evidence, or not recorded>

## Decisions

### D<n>
- ticket: <ticket id>
- decision: <the decision>
- rationale: <why, or not recorded>
- options:
  - chosen: <option>
  - rejected: <option>; why: <reason>
- decided_by: person: <name> | role: <role> | checkpoint (recommended option taken) | not recorded
- recorded_at: commit <sha> | url <URL> | checkpoint: <where in the session> | not recorded
- status: taken | default taken | deferred | deferred to <owner>

## Raised tickets

### R<n>
- ticket: <ticket id>
- type: <work item type>
- state: <state>
- iteration: <iteration path, or none>
- owner: <assigned person, or none>
- bundles: <bundle name>[, <bundle name>...] | none
- summary: <one sentence>
- rank: <whole number; 1 is the highest confidence it belongs in this bundle>
- in_bundle_confidence: include | lean include | lean defer | defer
- reason: <why>
```

## Rules

1. The frontmatter is the first block: a `---` line, then exactly two keys, `cca-handoff: 1`
   and `generated:` with a non-empty value, then a `---` line. A `cca-handoff:` value other
   than `1` is an error ("unsupported handoff version").
2. The four `## ` sections appear once each, in this order: `## Bundles`, `## Tickets`,
   `## Decisions`, `## Raised tickets`. A section with no items holds the single line
   `none`, except `## Bundles`, which never holds `none` and needs at least one bundle,
   since every other item refers to one. A `# ` title line is allowed once, after the
   frontmatter and before `## Bundles`.
3. A bundle name is the cca bundle name: the repo directory's base name, lowercased, with
   `-2`, `-3` added in list order when two bundles share it. It matches
   `^[a-z0-9][a-z0-9._-]*$`, so it holds no space, comma, or semicolon; a base name that
   does not fit is slugged (each run of other characters becomes one `-`). Bundle names are
   unique. A `## Bundles` line is split from the right: the last `; base `, then the last
   `; branch ` before it, then the last `; pr ` before that. What follows `: repo ` up to
   that point is the path, which may hold any character but a tab. The path, pr, branch,
   and base are not empty; pr is `none` when the bundle has no PR. A relative path is
   relative to the handoff file's directory; `/cca:handoff` writes absolute paths.
4. Item headings: tickets `### <ticket id>`, the id as the forge or export writes it, such
   as `APP-1`, `AB#4567`, or `github:owner/repo#12`; spaces and colons are allowed, and the
   id is the whole rest of the line after `### `. Decisions are `### D<n>` and raised
   tickets `### R<n>`, `<n>` a whole number from 1. Ids are unique within their section.
   Ticket ids are unique across the whole handoff: when two repos have a ticket with the
   same short id, both are written in their qualified form (such as
   `github:owner/app#12`). The `ticket` values in `## Raised tickets` are unique too, and
   none is an id in `## Tickets`. Every name in a `bundles:` value is a bundle from
   `## Bundles`, named once per value; a ticket in `## Tickets` lists at least one, and a
   raised ticket lists at least one or says `none`.
5. Item keys are `- <key>: <value>` at column 0, each listed key exactly once, in the order
   listed above, with no other key. Values are not empty. A list key (`commits`,
   `verified`, `options`) has an empty value followed by at least one entry indented exactly
   two spaces (`  - `), or the value `none` (`options` takes `none recorded` instead of
   `none`).
6. A commit entry is `  - <bundle name> <sha>: <text>`. The bundle is one of the ticket's
   `bundles`; the sha is 7 to 40 lowercase hex digits; the text is not empty. Within one
   ticket, two entries with the same bundle do not name the same commit: neither sha is a
   prefix of the other. One commit may appear under two tickets.
7. A verified entry is split at the first `; check: `; both parts are not empty. The check
   part says how the statement was checked, or `not recorded`.
8. An options entry starts `chosen: ` or `rejected: `. A rejected entry is split at the
   first `; why: `, both parts not empty. At most one entry is `chosen:`. When `status` is
   `taken` or `default taken` and options are listed, exactly one is `chosen:`.
9. A decision's `ticket` resolves to a `### ` id in `## Tickets` first, else to the `ticket`
   value of an item in `## Raised tickets`; with neither, it is an error.
10. `status` is `taken`, `default taken`, `deferred`, or `deferred to <owner>` with a
    non-empty owner. `in_bundle_confidence` is `include`, `lean include`, `lean defer`, or
    `defer`. Ranks are distinct whole numbers from 1. `decided_by` is one of
    `person: <name>`, `role: <role>` (each with a non-empty value),
    `checkpoint (recommended option taken)`, or `not recorded`. `recorded_at` is one of
    `commit <sha>` (7 to 40 lowercase hex digits), `url <URL>`, `checkpoint: <where>` (each
    with a non-empty value), or `not recorded`.
11. `decided_by` is `person: <name>` only when the record names that person, and
    `role: <role>` when it names a role but no person. A model, agent, or tool is never
    `decided_by`. A choice taken at a checkpoint on the recommended option is
    `checkpoint (recommended option taken)`.
12. Blank lines are allowed anywhere. Any other line that fits none of the shapes above is
    an error.
13. A claim's text, the sixth field `claims` prints, is at most 8,000 bytes. A claim is read
    as one line, and a reader cannot page within a line, so a longer one is an error, never
    a truncation. A decision's claim joins its keys (decision, rationale, options,
    decided_by, recorded_at, status), so long options count against the cap.

## Writing a handoff

These rules are for the writer (`/cca:handoff`, or a person writing one by hand).

- Write from the record only: the commit bodies, the forge fields and comments, and the
  session's own checkpoint record. Never invent an option, a reason, or an owner.
- Where the record shows no alternative was weighed, write `options: none recorded`, and
  for a taken decision `status: default taken`. Keep a deferral's status: a deferred
  decision stays `deferred` or `deferred to <owner>`.
- A checkpoint choice the audit should count as weighed is recorded where the audit can
  read it, in a commit body or a ticket comment, and named in `recorded_at`. The audit
  cannot open a `checkpoint:` pointer.
- Put a statement the session checked under `verified`, with the exact check. The audit
  marks it `true` only when it reproduces the result itself.
- No credentials, tokens, or secrets anywhere in the file.

## Claims

`handoff.sh claims <file>` turns a valid handoff into one claim per line, six fields
separated by one tab: `<kind>`, `<ref>`, `<bundle>`, `<ticket>`, `<line>`, `<text>`. Items
are in file order, and within an item the claims are in this order:

| Item | Kind | Ref | Bundle | Text |
|---|---|---|---|---|
| ticket `<id>` | `status` | `tickets/<id>/fields` | first of its `bundles` | `<id>: type <type>; state <state>; iteration <iteration>; owner <owner>` |
| | `code` | `tickets/<id>/problem` | first of its `bundles` | the `problem` value |
| | `code` | `tickets/<id>/decision` | first of its `bundles` | the `decision` value |
| each commit entry | `code` | `tickets/<id>/commit/<bundle>/<sha>` | that entry's bundle | `<bundle> <sha>: <text>` |
| each verified entry, `<k>` from 1 | `verification` | `tickets/<id>/verified/<k>` | first of its `bundles` | the whole entry |
| decision `D<n>` | `decision` | `decisions/D<n>` | first bundle of its ticket, or `none` | `<decision> \| rationale: <rationale> \| options: <entries joined with "; "> \| decided_by: <decided_by> \| recorded_at: <recorded_at> \| status: <status>` |
| raised ticket `R<n>` | `scope` | `raised/R<n>` | its first bundle, or `none` | `<ticket>: <summary> \| rank <rank>, <in_bundle_confidence>: <reason>` |
| | `status` | `raised/R<n>/fields` | its first bundle, or `none` | `<ticket>: type <type>; state <state>; iteration <iteration>; owner <owner>` |

`<ticket>` is the ticket id (for a decision, its `ticket` value). `<line>` is the line of the
item's `### ` heading, or of the entry for a commit or verified entry. When `options` is
`none recorded`, the decision text says `options: none recorded`.

`handoff.sh commits <file>` prints `<bundle>`, `<sha>`, `<ticket>`, `<line>` per commit
entry, tab-separated, in file order. Stage 1 uses it to seed the review groups.

## Example

```
---
cca-handoff: 1
generated: 2026-09-01T11:00:00Z
---

# Handoff: deactivate users

## Bundles

- app: repo ./app; pr none; branch feature; base main

## Tickets

### APP-1
- type: Story
- state: Active
- iteration: none
- owner: Developer
- bundles: app
- problem: Removing a user deletes the record, so its history is lost.
- decision: Add a deactivate command that keeps the row and sets its status to inactive.
- commits:
  - app 9c5f77c: add the status column migration so every row has a status.
- verified:
  - The test suite runs with one test skipped; check: sh run-tests.sh

## Decisions

### D1
- ticket: APP-1
- decision: Whether a deactivated user can be reactivated is left for later.
- rationale: not recorded
- options: none recorded
- decided_by: not recorded
- recorded_at: not recorded
- status: deferred

## Raised tickets

none
```
