# Stage 9: act (`/cca:act`, gated)

The orchestrator's procedure for `/cca:act <run-id> <item-id...> [--per-item]`. This is
the only write phase. The read-only boundary of `/cca:audit` does not apply here, but
every write below needs the user's yes first, and hard rule 3 applies: no commit message,
ticket or PR text, or drafted comment names a model, agent, or tool.

Act takes the run id and the item ids the user approved. It never widens the list. It
never uses the exports under `trees/`; changes go to the user's checkout on the bundle's
branch.

Inputs: the run's entry in `${CLAUDE_PLUGIN_DATA}/runs.json`, `report.md`,
`converged.md`, `manifest.json`, `audit-brief.md`, `stages.json` (the audited bundle
shas), and `act/log.md` when it exists.

Output: `act/log.md`, appended to, never rewritten. Every action, check result, and
commit sha is logged there (step 7).

## Steps

1. **Bind the approval.**
   1. Find the run in `runs.json`. Stage 8 wrote `report.md` as the line
      `revision: sha256:<hex>`, one LF, then the body bytes. Recompute the revision over
      the same bytes, with Bash, never through the Read tool's text:
      `tail -n +2 report.md | sha256sum`. Compare it with the hex on the first line
      (`head -n 1 report.md`). If they differ, the report was edited: stop and say
      so.
   2. Every item id must name an item in the report. An unknown id stops act; no id is
      added.
   3. Show each approved item: id, title, severity, gate, disposition, tickets, repo,
      files, and recommended change, with the report revision. Say when an item is
      `provisional`, `contested`, or `dismissed`. Ask the user to confirm.
   4. Log the approval: run id, revision, item ids, `--per-item`, time. The approval is
      bound to that run, that revision, and those items. Before each commit in step 5,
      recompute the revision; if it differs from the approved one, stop.

2. **Check each affected repo** (each repo an approved item's recommended change names):
   - `git -C <repo> rev-parse --abbrev-ref HEAD` equals the bundle's branch;
   - `git -C <repo> status --porcelain --untracked-files=no` is empty: no modified
     tracked file and no staged change.

   If not, stop and say what differs. Nothing is stashed, reset, cleaned, or checked
   out. Untracked files do not stop act: list them
   (`git -C <repo> status --porcelain --untracked-files=all`, the `??` lines) in
   `act/log.md`, and never stage them.

3. **Detect drift.** Take the audited head sha of the bundle from `stages.json`. List
   `git -C <repo> rev-list <audited head>..HEAD`. Commits that `act/log.md` records as
   made by act are expected. Any other commit is drift, and so is an audited head that
   is not an ancestor of `HEAD` (`git merge-base --is-ancestor`). Show the drift
   (`git log --oneline` for those commits) and ask before going on. Log the answer.

   A bundle with `head: working-tree` has an audited head that no branch ever held, so
   drift is decided by the committed tree, not by ancestry. Take `head_tree` from
   `stages.json`. Let `B` be the parent of the earliest act commit that `act/log.md`
   records for this run and that is an ancestor of `HEAD`, or `HEAD` when there is none.
   Drift is `B`'s tree (`git -C <repo> rev-parse B^{tree}`) differing from `head_tree`,
   or any commit in `git -C <repo> rev-list B..HEAD` that act did not log. An unchanged
   clean `HEAD` audited as is, and a rewritten history with the same tree, are not
   drift. On drift, say that the committed tree differs from the audited one, show
   `git -C <repo> log --oneline -5 B`, and ask, as above. Log the answer.

4. **Baseline checks.** Before the first change in each repo, run the repo's required
   checks (from its `AGENTS.md`, `CLAUDE.md`, `README.md`, CI config, or package
   scripts) and the checks that cover the approved items. Record each command, where it
   ran, its exit status, and its failures in `act/log.md` as the baseline, including
   failures already present.

5. **Group and commit.**
   1. Group approved items by ticket and repo, from each item's work-item impact. An
      item with more than one ticket goes to the first listed, noted in the log. Items
      with no ticket form one group each. With `--per-item`, every item is its own group.
      Order groups by ticket order in the manifest, then item id.
   2. For each group, one at a time, in each repo it touches:
      1. Record `git -C <repo> ls-files --eol -- <files>` for each file the group will
         touch.
      2. Make the group's change in the checkout.
      3. Compare `git ls-files --eol` again: a file's working-tree line endings
         (`w/crlf`, `w/lf`, mixed) must be what they were. If an edit changed them,
         restore the original endings before staging.
      4. Stage the group's change. When no other approved group touches the same file,
         the working tree holds only this group's hunks. When another group touches one
         of these files, stage only this group's hunks from a byte-exact patch: write
         it with a shell redirect, not a file-writing tool, so bytes and line endings
         pass unchanged
         (`git -C <repo> diff --binary --no-color --no-ext-diff -- <file> > <run dir>/act/patches/<group>.patch`,
         keeping only this group's hunks), check it with `git apply --cached --check`,
         then run `git -C <repo> apply --cached <patch>`. If this group's hunks
         overlap or touch another group's hunks, stop and ask. After staging, confirm
         with `git ls-files --eol` that the index line endings of each file are
         unchanged.
      5. Rerun the checks that cover the change, then the repo's required checks. Checks
         run after each commit's staging, not once at the end.
      6. Compare each result with the baseline. A check that passed at baseline and now
         fails is **introduced**: say so and do not offer the commit until the user
         decides. A failure present at baseline is **preexisting**: report it; it is not
         act's to fix.
      7. Show the staged diff (`git diff --cached`) and both results against the
         baseline, and ask before the commit.
      8. On yes, recompute the report revision (step 1.4), write the message to
         `<run dir>/act/msg-<group>.txt`, and run `git -C <repo> commit -F <file>`. The
         message follows the repo's convention, read from `git log` of that repo, and
         names no model, agent, or tool, with no trailer that does. No hook is skipped;
         if a hook fails, stop and report it.
      9. Log the commit sha, repo, branch, group, ticket, and item ids.

6. **No push and no forge edits.** Never push, and never edit tickets or PRs, until the
   user says to for that item. Work-item fixes and decision comments from the report are
   shown as drafts. The operations in `work-items.jsonl` are drafts too, like the
   work-item fixes: act applies none of them.
   When the user says to post one for an item, post that one only, with
   its text free of model, agent, and tool names, and log it with its URL.

7. **`act/log.md`.** Append one entry per action, in order:

   ```
   - <time> <repo> <action>: <command or decision>; <result or exit status>
   ```

   Actions: `approve`, `check-repo`, `drift`, `baseline`, `stage`, `check`, `commit`,
   `push`, `post`, `stop`. A commit entry reads
   `- <time> <repo> commit <sha> on <branch>: items <ids>; ticket <id or none>`. A later
   `/cca:act` on the same run reads these entries to tell act's own commits from drift.

When act stops for any reason, print what was committed, what was not, and why.
