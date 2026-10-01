---
description: "Act on items of a finished cca audit report that the user approves by id: make local commits for the approved fixes after confirmation and checks, never pushing or editing tickets unless told to per item. Use when the user asks to act on or apply cca report items, or types /cca:act. Takes a run id, one or more item ids (C1, C2, ...), and an optional --per-item for one commit per item."
argument-hint: '<run-id> <item-id...> [--per-item]'
allowed-tools: Bash(git -C * rev-parse *), Bash(git -C * status *), Read, Skill
---

You are a thin forwarder for the cca orchestrator. Do the steps below in order. Write no file, in any step.

1. Parse the arguments shown between the markers below. They are what the user typed after the command.

<user-text>
"$ARGUMENTS"
</user-text>

   - A flag is a token that starts with `--`. The only accepted flag is `--per-item`, which takes no value. Without it, per-item is `false`. Reject any other flag.
   - The first positional token is the run id. It is made only of letters, digits, `.`, `_`, and `-`. Reject any other character.
   - Every later positional token is an item id: `C` followed by a whole number from 1 up, such as `C3`. A token may also be a comma-separated list of item ids with no spaces. An id given twice is listed once. Reject any other token.
   - There must be a run id and at least one item id.

2. Validate cheaply. Read `${CLAUDE_PLUGIN_DATA}/runs.json` with the Read tool. It must exist, parse as JSON, and hold an entry whose `run_id` equals the run id. Do not check anything else here: the orchestrator checks the report, its revision, the item ids, and each repo's checkout.

   Reject the request with one short line that names the offending token, such as `cca: unknown flag --bogus`, `cca: not an item id: X4`, or `cca: run <run-id> not found in runs.json`, if any rule in step 1 or step 2 fails. When you reject, run no other command, write no file, and do not load the skill.

3. State the parsed invocation to the user as this block, with every flag at its effective value. List the item ids in the order typed.

```
command: act
manifest: none
inputs: none
flags:
  effort: auto
  no-codex: false
  codex-model: gpt-6.1-sol
  codex-timeout: default
  models: none
  questions: default
  claims: none
  budget: none
  max-agents: 8
  run-id: <id>
  items: <id>[, <id>...]
  per-item: true | false
  from: none
```

4. Invoke the Skill tool with skill `cca:cca` and that same block as the args. Then follow the skill. Do not interpret the request or act on it yourself: approval, checks, and commits happen in the skill, and only for the items listed. The flags other than `run-id`, `items`, and `per-item` are placeholders here.
