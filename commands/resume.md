---
description: "Resume a cca audit run by id, rerunning from the first stage that is incomplete or whose inputs changed, or from a named stage, and reusing every earlier stage whose inputs are unchanged. Use when the user asks to resume or rerun a cca audit, or types /cca:resume. Takes a run id, an optional --from <stage> (1 to 8), and an optional --live <file> of approved live check results. To start a new audit, use /cca:audit."
argument-hint: '<run-id> [--from <stage>] [--live <file>]'
allowed-tools: Bash(git -C * rev-parse *), Bash(git -C * status *), Bash(git -C * --no-optional-locks status *), Read, Skill
---

You are a thin forwarder for the cca orchestrator. Do the steps below in order. Write no file, in any step.

1. Parse the arguments shown between the markers below. They are what the user typed after the command.

<user-text>
"$ARGUMENTS"
</user-text>

   - A flag is a token that starts with `--`. The accepted flags are `--from` and `--live`, each given at most once. Each takes exactly one value, the next token, which must not start with `--`. Reject any other flag, a missing value, and any other value.
   - `--from`: a stage number, a whole number from 1 to 8. Without it, from is `none`.
   - `--live`: a path to an existing file of approved live check results. Without it, live is `none`. A live file answers the findings of a finished run, so reject `--live` together with `--from` 1 to 5.
   - There must be exactly one positional token, the run id. It is made only of letters, digits, `.`, `_`, and `-`. Reject no run id, more than one positional token, and any other character.

2. Validate cheaply. Read `${CLAUDE_PLUGIN_DATA}/runs.json` with the Read tool. It must exist, parse as JSON, and hold an entry whose `run_id` equals the run id. With `--live`, the file exists: check it with the Read tool, and do not judge its content. Do not check anything else here: the orchestrator checks the run directory, its stages, the bundle heads, and the live file against the report.

   Reject the request with one short line that names the offending token, such as `cca: unknown flag --bogus`, `cca: --from must be 1 to 8, got 9`, `cca: --live cannot be used with --from 1 to 5`, `cca: --live file not found: <path>`, or `cca: run <run-id> not found in runs.json`, if any rule in step 1 or step 2 fails. When you reject, run no other command, write no file, and do not load the skill.

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
  live: none | <file>
```

4. Invoke the Skill tool with skill `cca:cca` and that same block as the args. Then follow the skill. Do not interpret the request or act on it yourself. The flags other than `run-id`, `from`, and `live` are placeholders here: the orchestrator takes the run's own settings from its run directory.
