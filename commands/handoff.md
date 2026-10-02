---
description: "Write a typed handoff from a build session, for /cca:audit to read as claims. Use when the user asks for a cca handoff, or types /cca:handoff. Inputs are an optional manifest JSON file and prompt inputs (repo paths, PR and ticket ids, exported ticket files). Flags are --out <path>, --verdicts <claims-verdicts.md>, and --memory <dir>. It writes one file and never edits tracked files, commits, or posts anything."
argument-hint: '[<manifest.json>] [<inputs...>] [--out <path>] [--verdicts <claims-verdicts.md>] [--memory <dir>]'
allowed-tools: Read, Write, Bash(git -C * rev-parse *), Bash(git -C * log *), Bash(git -C * merge-base *), Bash(git -C * symbolic-ref *), Bash(git -C * check-ignore *), Bash(git -C * status *), Bash(git -C * --no-optional-locks status *), Bash(git -C * hash-object --no-filters *), Bash(git check-ignore *), Bash(gh pr view *), Bash(gh issue view *), Bash(date *), Bash(sh *handoff.sh check *), Bash(sh *handoff.sh claims *), Bash(sh *memory.sh find *)
---

You write one handoff file for the session's work, from the record only. Do the steps below in order. The only file you write is the handoff, in step 6. You never edit a tracked file, commit, push, or post to a forge.

1. Parse the arguments shown between the markers below. They are what the user typed after the command. Split them into a manifest, inputs, and flags with these rules.

<user-text>
"$ARGUMENTS"
</user-text>

   - A flag is a token that starts with `--`. Accepted flags: `--out`, `--verdicts`, and `--memory`. Reject any other flag.
   - Each flag takes exactly one value, the next token, which must not start with `--`. Reject a missing value. Reject a flag given twice.
   - `--out`: a path. Without it, out is `default`.
   - `--verdicts`: a path to an existing file. Without it, verdicts is `none`.
   - `--memory`: a path to an existing directory, the build session's memory files. It
     needs `--verdicts`: without it, stop with `cca: --memory needs --verdicts`. Without
     `--memory`, memory is `none`.
   - A token that is not a flag or a flag value is positional. The manifest is the first positional token that ends in `.json` and has no scheme prefix. A scheme prefix is a name of two or more characters followed by `:` at the start of the token, such as `file:` or `github:`. A single letter followed by `:/` or `:\`, such as `C:/`, is a Windows drive letter, not a scheme, so that token is a path. Without such a token, manifest is `none`. A `.json` token with a scheme prefix is an input. A second positional token ending in `.json` is also an input.
   - Every other positional token is an input, kept verbatim in the order typed: a repo path, a PR or ticket id (`github:owner/repo#n`, `#n`, `file:<path>`, or a forge URL), or a file path. Quoted text stays one token.
   - With no manifest and no input, the bundle is the session's own repository and its current branch.

   Validate cheaply. Relative paths in the prompt are relative to the session's directory; relative paths inside the manifest are relative to the manifest's directory.
   - The manifest, when given, exists and parses as a JSON object. Check with the Read tool.
   - Every repo path the manifest names (each `bundles[].repo`) and every input that names an existing directory is a git checkout: `git -C <path> rev-parse --git-dir` succeeds.
   - Every `file:<path>` input names an existing file. The `--verdicts` file exists, and the `--memory` directory exists.
   - `--out` does not name an existing directory.

   Reject the request with one short line that names the offending token or path, such as `cca: unknown flag --bogus` or `cca: --out needs a value`, if any rule fails. When you reject, run no other command and write no file.

2. With `--verdicts`, read that file first, before anything else. For each `claim` line under a claims file that is a handoff, find the handoff source item it names. Compare the file hash in the line's `## ` heading with `git hash-object --no-filters` of that file as it is now. Then run `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/handoff.sh claims <that file>` and compare the entry's `text:` sub-line (the whole rest of that line) with the text field (the sixth, tab-separated) of the output line whose ref equals the line's handoff ref. Both must match.
   - A line that matches, about a ticket of the bundles settled in step 3, is applied in step 5.
   - A line that does not match, a line about a prose claims file, and a `contested` line are listed as reconciliation work and not applied.
   - A `not reproducible here` line is an env claim (a check tagged `env: <name>;`) that no live result has settled. It is not a recheck request and not a correction: apply nothing for it, and keep the claim's entry as written. To settle it, run the check against that environment and feed the result back with `/cca:resume <run-id> --live <file>`.
   - With `--memory`, run `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/memory.sh find <verdicts> <dir>` and keep its output: one line per match, tab-separated, `claim <n>`, the key, and a file path, or `none` when no file holds the key; or `claim <n>`, `-`, `no key` for a `false` entry with no key. On exit 2, print its message and stop. The memory files are never edited; step 7 lists them as work for the user.

3. Settle the bundles, base first, one bundle per repo. The bundles are those the manifest names, else the repo paths among the inputs, else the session's own repository. Per bundle, the base is the first of:
   - the manifest bundle's `base`;
   - the PR's base branch: for GitHub, `gh pr view <id> --json baseRefName`;
   - the repository's default branch, proposed to the user, who must confirm it.

   Never use the branch's upstream tracking ref as the base. Name each bundle as stage 1 does: the repo directory's base name, lowercased, with `-2`, `-3` added in list order when two bundles share it, and slugged when it does not fit `^[a-z0-9][a-z0-9._-]*$`. State the bundles to the user, each with its repo, PR, branch, and base, before gathering anything.

4. Gather the record. Read `${CLAUDE_PLUGIN_ROOT}/skills/cca/handoff.md` with the Read tool: it holds the format, the rules, and "Writing a handoff". Then, per bundle, the merge-base and `git -C <repo> log --format='%H%n%B' <merge-base>..<head>`. Per ticket, the forge fields and comments: `gh issue view` for GitHub, with `closedByPullRequestsReferences` among its `--json` fields, or the exports given. And the session's own checkpoint record: the plan reviews, the options offered, and the answers given. Nothing else is a source.

5. Write the handoff from the record only, in the format of `${CLAUDE_PLUGIN_ROOT}/skills/cca/handoff.md`.
   - Write each bundle's `repo` as an absolute path.
   - Fill `parent` and `links` from the record only. From an export, its `links` (and a parent link, or a parent in `fields`). For a GitHub ticket, the PRs in `closedByPullRequestsReferences` as `closed by` links, and no parent, since gh has no parent field. When the record says nothing, leave both keys out; when it shows no links, write `links: none`.
   - Keep each decision's recorded status. A deferral stays `deferred` or `deferred to <owner>`; it is never rewritten as taken.
   - Where the record shows no alternative was weighed, write `options: none recorded`, and for a taken decision `status: default taken`. Never invent an option, a reason, or an owner.
   - `decided_by` follows rule 11: `person: <name>` only when the record names that person, `role: <role>` when it names a role but no person, `checkpoint (recommended option taken)` for a checkpoint choice on the recommended option, else `not recorded`. A model, agent, or tool is never `decided_by`.
   - A statement the session checked goes under `verified`, with the exact check, or `not recorded`. Where the statement depends on it, the check also names its directory, environment variables, services or accounts, and the environment it ran against.
   - Apply the step 2 matches: a `false` statement is corrected, using the entry's `correction:` sub-line, or dropped. A recheck request, a `not verified` line on a `verification` claim, stays, with its `check:` updated when the session has rechecked it. A `not reproducible here` line changes nothing.
   - No credentials, tokens, or secrets anywhere in the file. Text that names a model, agent, or tool is rewritten without the name.

6. Choose the output path, the first of:
   - `--out`, which must lie outside every repo or be ignored by its repo (`git -C <repo> check-ignore -q <path>`), and must not name an existing file: when it does, stop and say so, so an earlier handoff is never overwritten;
   - `<scratch>/cca/handoff-<YYYY-MM-DD-HHMM>.md` in the session's repository, local time, where `<scratch>` is chosen as stage 1 D2 chooses it: the manifest's `scratch` key (inside the repo and ignored), else `scratch/`, `tmp/`, or `.scratch/` when it exists and is ignored, else `.cca/` when it is ignored. When that file exists, add `-2`, then `-3`, and so on before `.md`, as stage 1 does for run ids, so an earlier handoff is never overwritten.

   With neither, stop and ask for `--out`. Write that one file with the Write tool, and no other file.

7. Check it: `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/handoff.sh check <path>`, with `${CLAUDE_PLUGIN_ROOT}` resolved to the plugin's absolute path. On exit 1, fix each error line it prints in the file and run it again, at most three runs. If it still fails, say so, print the remaining error lines, and stop. When it passes, print:
   - the path;
   - the corrections applied from `--verdicts`, or `none`;
   - the reconciliation list from step 2, or `none`;
   - with `--memory`, the memory reconciliation work from step 2, grouped by claim: per claim, each key with the files that hold it, `no file holds it` for `none`, and `no key to search for` for `no key`; or `none` when the output was empty. No file in the directory was edited;
   - the next command: `/cca:audit <manifest or inputs> --claims <path>`.
