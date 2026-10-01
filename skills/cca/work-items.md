# Work-items format

`work-items.jsonl` is the audit's plan for changes to tickets and pull requests, written by
stage 8 into the run directory. It is a plan, never an action: cca 0.2 applies none of it.
A person, or a forge adapter, applies it. A ticket that does not exist yet is named by a
placeholder, so a later operation can refer to it.

This file is the single home of the format. `skills/cca/stages/8-report.md` and
`skills/cca/scripts/work-items.sh` follow it.

## Layout

One JSON object per line, ids `W1`, `W2`, ... in order, with no gap. Every object has:

| Key | Value |
|---|---|
| `run` | the run id, as in the report's first heading `# cca audit report: <run-id>` |
| `id` | `W<n>` |
| `op` | one of the operations below |
| `target` | the forge id a person or adapter can act on (see Targets) |
| `items` | a non-empty array of report item ids (`C<n>`) or claim references (`claim <n>`) |
| `reason` | why, in one or two sentences |

`target_url` is optional and holds the forge URL when one is known (`url` from the forge
data or the export). The file carries no report revision: it is validated before the
report is hashed, and a resume that rewrites the report supersedes the file with it.

## Operations

| `op` | Fields | `target` |
|---|---|---|
| `create` | `key`, `type`, `title`, `description`, optional `fields` (object), optional `links` (array of `{ "type", "to" }`) | `$new:<key>`, its own key |
| `set_field` | `field`, `value` | forge id or `$new:<key>` |
| `set_state` | `value` | forge id or `$new:<key>` |
| `add_link` | `link_type`, `to` (forge id or `$new:<key>`) | forge id or `$new:<key>` |
| `add_comment` | `text` | forge id or `$new:<key>`, ticket or PR |
| `set_description` | `text` | forge id or `$new:<key>` |
| `set_acceptance_criteria` | `text` | forge id or `$new:<key>` |
| `set_pr_description` | `text` | PR forge id |

The keys of `fields`, and `set_field`'s `field`, are the forge's own field names as the
forge or its export writes them. The adapter maps them to its API, including fields that
differ by work item type.

## Targets and placeholders

- A forge id is `owner/repo#n` for GitHub, or the export's `id` for an exported ticket or
  pull request.
- `$new:<key>` is a placeholder for a ticket a `create` operation makes. `create` keys
  are unique. A `create` line's `target` is `$new:<its key>`.
- Every other `$new:<key>`, in `target`, in `to`, or in `links[].to`, names a `create` on
  an earlier line. A placeholder never refers forward.
- Text in `title`, `description`, `text`, `value`, and `reason` names no model, agent, or
  tool (hard rule 3 in `common.md`).

## Validator

```
sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/work-items.sh check <file> <report body> <claims.md>
```

With `jq`, it checks that:

- every line parses as one JSON object;
- the common keys and the operation's fields are present, with the right types;
- ids run `W1` upward with no gap;
- every placeholder rule above holds, and `set_pr_description` targets a PR forge id, not
  a placeholder;
- `run` equals the run id in the first heading of the report body;
- every `C<n>` in `items` is an item heading `#### C<n>: ` in the report body;
- every `claim <n>` in `items` is a `claim` line in `claims.md`.

It prints `work-items: ok` and exits 0, or prints one line per error,
`work-items <file>:<line>: <message>`, and exits 1. It exits 2 on a usage error, and with
`work-items: jq not found` when `jq` is missing.

## What stage 8 does with the result

Stage 8 runs the validator on `report.body.tmp`, before the report is hashed, and records
the result in the report's Coverage section.

- Exit 0: Coverage says `work-items: ok`.
- Exit 1: the file is kept, Coverage lists the errors, and the file is marked not ready for
  an adapter. The report is not changed to fit the file.
- Exit 2: the file is kept, and Coverage says it was not validated, with the script's
  message.

Stage 9 (`/cca:act`) applies none of these operations. They are drafts, like the report's
work-item fixes.
