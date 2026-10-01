---
description: "Resume a cca audit run by id, rerunning from the first stage that is incomplete or whose inputs changed, or from a named stage, and reusing every earlier stage whose inputs are unchanged. Use when the user asks to resume or rerun a cca audit, or types /cca:resume. Takes a run id and an optional --from <stage> (1 to 8). To start a new audit, use /cca:audit."
argument-hint: '<run-id> [--from <stage>]'
allowed-tools: Bash(git -C * rev-parse *), Bash(git -C * status *), Read, Skill
---

You are a thin forwarder for the cca orchestrator. Do the steps below in order. Write no file, in any step.

1. Parse the arguments shown between the markers below. They are what the user typed after the command.

<user-text>
"$ARGUMENTS"
</user-text>

   - A flag is a token that starts with `--`. The only accepted flag is `--from`, given at most once. It takes exactly one value, the next token: a stage number, a whole number from 1 to 8. Without it, from is `none`. Reject any other flag, a missing value, and any other value.
   - There must be exactly one positional token, the run id. It is made only of letters, digits, `.`, `_`, and `-`. Reject no run id, more than one positional token, and any other character.

2. Validate cheaply. Read `${CLAUDE_PLUGIN_DATA}/runs.json` with the Read tool. It must exist, parse as JSON, and hold an entry whose `run_id` equals the run id. Do not check anything else here: the orchestrator checks the run directory, its stages, and the bundle heads.

   Reject the request with one short line that names the offending token, such as `cca: unknown flag --bogus`, `cca: --from must be 1 to 8, got 9`, or `cca: run <run-id> not found in runs.json`, if any rule in step 1 or step 2 fails. When you reject, run no other command, write no file, and do not load the skill.

3. State the parsed invocation to the user as this block, with every flag at its effective value.

```
command: resume
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
  items: none
  per-item: false
  from: none | <stage>
```

4. Invoke the Skill tool with skill `cca:cca` and that same block as the args. Then follow the skill. Do not interpret the request or act on it yourself. The flags other than `run-id` and `from` are placeholders here: the orchestrator takes the run's own settings from its run directory.
