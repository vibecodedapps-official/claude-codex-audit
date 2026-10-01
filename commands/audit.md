---
description: "Run a read-only, adversarial audit of a finished bundle of pull requests, in one or many repos, and stop at a report. Use when the user asks for a cca audit, or types /cca:audit. Inputs are an optional manifest JSON file and prompt inputs (repo paths, PR and ticket ids, exported ticket files). Flags are --effort low|medium|high, --no-codex, --codex-model <id>, --codex-timeout <seconds>, --models role=model,..., --questions <file>, --claims <file> (repeatable), --budget <minutes>, and --max-agents <n>. To rerun a run from a stage, use /cca:resume; to act on reported items, use /cca:act."
argument-hint: '[<manifest.json>] [<inputs...>] [--effort low|medium|high] [--no-codex] [--codex-model <id>] [--codex-timeout <seconds>] [--models role=model,...] [--questions <file>] [--claims <file>]... [--budget <minutes>] [--max-agents <n>]'
allowed-tools: Bash(git -C * rev-parse *), Bash(git -C * status *), Read, Skill
---

You are a thin forwarder for the cca orchestrator. Do the steps below in order. Write no file, in any step.

1. Parse the arguments shown between the markers below. They are what the user typed after the command. Split them into a manifest, inputs, and flags with these rules.

<user-text>
"$ARGUMENTS"
</user-text>

   - A flag is a token that starts with `--`. Accepted flags: `--effort`, `--no-codex`, `--codex-model`, `--codex-timeout`, `--models`, `--questions`, `--claims`, `--budget`, `--max-agents`. Reject any other flag.
   - `--no-codex` takes no value. Every other flag takes exactly one value, the next token, which must not start with `--`. Reject a missing value.
   - Only `--claims` may be repeated. Reject any other flag given twice.
   - `--effort`: one of `low`, `medium`, `high`. Without it, effort is `auto`.
   - `--codex-model`: a full Codex model id, made only of letters, digits, `.`, `_`, and `-`. Without it, codex-model is `gpt-6.1-sol`.
   - `--codex-timeout`: a whole number of seconds from 1 to 3600. Without it, codex-timeout is `default` (the tier sets it).
   - `--models`: a comma-separated list of `role=model` pairs with no spaces. A role is one of `digester`, `mapper`, `auditor`, `adversary`, `merger`, each at most once. A model is one of `opus`, `sonnet`, `haiku`, `fable`. Without it, models is `none`.
   - `--questions`: a path to an existing file. Without it, questions is `default`.
   - `--claims`: a path to an existing file. Each use adds one file. Without it, claims is `none`.
   - `--budget`: a whole number of minutes, 0 or more. Without it, budget is `none`.
   - `--max-agents`: a whole number, 1 or more. Without it, max-agents is `8`.
   - A token that is not a flag or a flag value is positional. The manifest is the first positional token that ends in `.json` and has no scheme prefix. A scheme prefix is a name of two or more characters followed by `:` at the start of the token, such as `file:` or `github:`. A single letter followed by `:/` or `:\`, such as `C:/`, is a Windows drive letter, not a scheme, so that token is a path. Without such a token, manifest is `none`. A `.json` token with a scheme prefix, such as `file:./exports/APP-1.json`, is an input. A second positional token ending in `.json` is also an input, like any other.
   - Every other positional token is an input, kept verbatim in the order typed: a repo path, a PR or ticket id (`github:owner/repo#n`, `#n`, `file:<path>`, or a forge URL), or a file path. Quoted text stays one token.
   - There must be a manifest or at least one input.

2. Validate cheaply. Relative paths in the prompt are relative to the session's directory; relative paths inside the manifest are relative to the manifest's directory.
   - The manifest, when given, exists and parses as a JSON object. Check with the Read tool.
   - Every repo path the manifest names (each `bundles[].repo`, `references[].path`, `sources_of_truth[].path`, and `groups[].repo`) is a git checkout: `git -C <path> rev-parse --git-dir` succeeds.
   - Every input that names an existing directory is a git checkout, checked the same way. Every `file:<path>` input names an existing file.
   - Every `--questions` and `--claims` file exists. Check with the Read tool.

   Reject the request with one short line that names the offending token or path, such as `cca: unknown flag --bogus` or `cca: --codex-timeout must be 1 to 3600, got 0`, if any rule in step 1 or step 2 fails. When you reject, run no other command, write no file, and do not load the skill. Do not check anything else here: the orchestrator validates the manifest in full.

3. State the parsed invocation to the user as this block, with every flag at its effective value. List each input on its own line as `- <token>`, in the order typed; with no inputs, write `inputs: none` on one line instead. Paths are written as the user typed them.

```
command: audit
manifest: <path> | none
inputs:
- <token>
flags:
  effort: auto | low | medium | high
  no-codex: true | false
  codex-model: gpt-6.1-sol | <id>
  codex-timeout: default | <seconds>
  models: none | role=model,...
  questions: default | <file>
  claims: none | <file>[, <file>...]
  budget: none | <minutes>
  max-agents: 8 | <n>
  run-id: none
  items: none
  per-item: false
  from: none
```

4. Invoke the Skill tool with skill `cca:cca` and that same block as the args. Then follow the skill. Do not interpret the request, plan the audit, or act on it yourself: the skill does all of that.
