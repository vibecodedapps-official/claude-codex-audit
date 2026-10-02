# Stage 1: orient

The orchestrator runs this stage alone. Sections A to D happen before stage 1 proper: a
stop there ends the command with one message, and nothing is written except as
sections C and D say. Their labels are fixed, but they run in this order: A, B, D1 to
D4 (the run directory exists before any PR is read), C, then D5 to D7. Steps 1 to 10
follow the stage's rule numbers. Order matters: the read-only baseline (step 1b) is
taken right after the approved fetch, before any export or other stage 1 work, so
everything after it is checked. A bundle with `head: working-tree` has its head built in
step 1c, right after the baseline, for the same reason.

## A. Normalize the inputs

1. Read the manifest, when `manifest` is not `none`. Relative paths in it are relative
   to the manifest's directory. Relative paths in the prompt inputs and flags are
   relative to the session's directory. Under `/cca:resume` with stage 1 as the first
   rerun stage, the invocation block's `manifest: none` and `inputs: none` are ignored:
   rebuild the inputs from the run directory's `manifest.json` `source` key (the
   manifest path, the prompt inputs, and the flags it recorded in A3), and do A2
   onward with those. When the manifest file `source` names no longer exists, stop with
   one line saying so.
2. Merge the prompt inputs into it:
   - A GitHub PR URL or `github:owner/repo#n` naming a PR adds a bundle with that `pr`.
     Its `repo` is the session's repository when that repository has a GitHub remote
     for `owner/repo`, else the manifest bundle with that remote; if neither, stop:
     `no local clone for <id>; add it to the manifest`.
   - An issue URL, `github:owner/repo#n` naming an issue, `#n`, or `file:<path>` adds a
     ticket to the only bundle. With more than one bundle, stop and ask which bundle it
     belongs to.
   - A directory that is a git checkout adds a bundle with that `repo`; it still needs
     a PR or a branch and a base.
   - `--claims` files are added to `claims`. `--questions` replaces `questions`.
     `--models` entries override the manifest's `models` entry for the same role.
   An input that disagrees with a manifest entry for the same bundle (another branch,
   base, or PR) stops the run and shows both.
3. Normalize:
   - Every path to an absolute path. Every repo path must be a git checkout
     (`git -C <path> rev-parse --show-toplevel`); store the top level.
   - `scratch`: when the manifest has it, an absolute path, relative to the manifest's
     directory like every manifest path. D2 checks it.
   - Bundle names: the repo directory's base name, lowercased, with `-2`, `-3` added
     when two bundles share it. `<bundle>` in file names below is this name.
     References and sources of truth keep their `name`, slugged the same way.
   - Ticket and PR ids to `github:owner/repo#n` or `file:<absolute path>`. A short id
     such as `#159` is accepted only when the bundle's repo has exactly one GitHub
     remote (`git -C <repo> remote -v`); otherwise stop with
     `<id>: write it as github:owner/repo#n or file:<path>`.
   - `ticket_token`: an optional bundle key. A string becomes a one-element list. The
     saved manifest keeps the list; step 8.1 reads it for the bundle's exported tickets.
   - `head`: an optional bundle key, kept in the saved manifest. Its only value is
     `working-tree`, which makes the bundle's head a commit built from the repo's working
     tree (step 1c). It is a manifest key only, with no flag. A.4 validates it.
   - `sources_of_truth`: when the manifest lists it, it replaces the default order.
     Otherwise the default order is: legacy source code, then a guidelines corpus
     (each only when supplied, as a reference named `legacy` or a source entry), then
     the audited repos' own docs (`AGENTS.md`, `CLAUDE.md`, `README.md`, `docs/`), then
     ticket text.
   - `questions`: `default` is Q1 to Q4 below. A questions file is a markdown list of
     `id: question` lines; a line `extends: default` keeps the four and adds the
     file's.
     - `Q1` best practice: does the change follow the ranked sources and the repo's
       own conventions?
     - `Q2` semantic drift: does the code do what the ticket and the claims say, no
       more and no less?
     - `Q3` technical debt: what does the change leave for later, and is that
       recorded?
     - `Q4` decision quality: were the choices the change made the right ones, which
       alternatives existed, and which does the auditor recommend, with the reason?
   - `models`: the merged role-to-model map, for roles digester, mapper, auditor,
     adversary, and merger.
   - `_test`: kept as given.
   - `source`: the manifest file's absolute path (or `none`), the prompt inputs, and
     the flags as the invocation block gave them, with relative paths made absolute
     against the session's directory, so resume can merge them again from any
     directory.
4. A bundle needs a repo, a PR or a branch or both, and a base. A bundle whose `pr` is
   a `file:` export must also give `branch` and `base`. A bundle with no resolvable
   base is rejected: stop with `bundle <name>: no base`. A bundle whose `ticket_token`
   is not a string or a non-empty array of strings, or has an entry that does not hold
   `{n}` exactly once and at least one other character, is rejected: stop with
   `bundle <name>: ticket_token must hold {n} once`. A bundle whose `head` is anything but
   `working-tree` is rejected: stop with `bundle <name>: head must be working-tree`. A
   `working-tree` bundle needs a `branch`, or a PR whose `headRefName` names it, and that
   branch must be checked out: `git -C <repo> rev-parse --abbrev-ref HEAD` (which prints
   `HEAD` for a detached head) equals it. Otherwise stop before stage 1:
   `bundle <name>: head working-tree needs <branch> checked out, found <x>`. With a
   manifest `branch` the check runs here; for a GitHub PR bundle without one it runs in
   section C, step 3, against `headRefName`. Right after that check, for each
   `head: working-tree` bundle, run
   `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/working-tree.sh check <repo>` with the
   resolved absolute script path. It runs the refusal checks of step 1c and nothing else:
   it writes nothing and runs no filter, hook, or program. Exit 1 or 2 stops before
   stage 1, showing the script's lines (on stderr). The refusals are thus checked before
   step 1b's baseline, whose `git status` could otherwise run a filter.
5. Select each audited repo's remote once (bundles, references, and sources of truth);
   every `<remote>` below is this one. For every GitHub PR bundle, however it was
   declared, it is the remote whose URL names the PR's owner and repo
   (`git -C <repo> remote -v`, compared with the `url` field in
   `forge/<bundle>/pr.json`); when none matches, `origin` when the repo has it;
   otherwise the repo's only remote. `pr.json` is read in section C, after D4, so for a
   PR bundle this selection is settled at section C, before step 1a. For every other
   repo it is `origin` when the repo has it, else the repo's only remote, selected
   lazily: only when step 1a needs a fetch from that repo. A repo with several remotes,
   none of them matched or named `origin`, stops the run at that point with one line
   naming the repo and its remotes. A repo with no remote has none selected, so it can
   fetch nothing.

## B. Parse exported forge files

For every `file:` ticket or PR, read the file. It is markdown with a frontmatter block,
or JSON.

1. A ticket requires `id`, `url`, `title`, `state`, and `description`, and may have
   `acceptance_criteria`, `fields` (name and value), `links`, and `comments` (author,
   date, text). A PR requires `id`, `url`, `title`, and `body`, and may have `reviews`
   and `threads` (file, line, comments). Every file requires the provenance keys
   `source`, `exported_by`, and `exported_at`.
2. In the markdown form, the text after the frontmatter block, when not empty, is the
   ticket's `description` or the PR's `body` if the frontmatter does not set that key.
3. A missing required key stops the run before stage 1 with exactly
   `export <path>: missing <key>`, naming the first missing key in the order above,
   with the path as the manifest gave it. Check every export before stopping, and show
   one line per missing key.
4. Keep a list of missing optional keys, one line per file and key, for the brief's
   "not in export" section.
5. The manifest's `forge_exports` key records the command and date that produced the
   exports. Never run that command.

A claims file may be a handoff, written in the format of
`${CLAUDE_PLUGIN_ROOT}/skills/cca/handoff.md`. After the export checks:

6. Run `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/handoff.sh detect <file>` on each
   claims file, with the resolved absolute script path. Exit 0 means the file is a
   handoff: it has a `cca-handoff:` key, whatever its value, so a malformed or newer one
   fails in the next step instead of being read as prose. Exit 1 means a prose claims
   file. Exit 2 stops the run before stage 1, naming the file.
7. For each handoff, run `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/handoff.sh check
   <file>`. On exit 1, stop the run before stage 1 and show the script's lines, one per
   error, as for export errors. Check every handoff before stopping. Exit 2 stops the
   run too, naming the file.
8. Map each handoff to the manifest. A handoff bundle maps to a manifest bundle when its
   `repo`, resolved against the handoff's directory, has the same top level, else when
   the names are equal. A handoff ticket id maps to a manifest ticket when it equals the
   normalized id, the export's `id`, or, for GitHub, the issue number in the bundle's
   repo. A handoff claim that names a mapped bundle or ticket takes the manifest's name
   in `claims.md` (Steps, step 7). An unmapped bundle or ticket is listed in the
   brief's Handoff section, and its claims keep the handoff's names.

## C. Resolve PRs and check for disagreement

1. For a `github:` PR, read it once: create `forge/<bundle>/` in the run directory
   (D4 made it) and run the `gh pr view` command of step 2, whose output the shell
   redirects to `forge/<bundle>/pr.json`. The output never passes through the model:
   a tool result cannot carry a large output, and the Write tool would re-serialize
   it. Under `/cca:resume`, when `forge/<bundle>/pr.json.new` exists (resume step 3
   wrote it with the same command) and its `url` field names this bundle's owner, repo,
   and PR number, rename it to `forge/<bundle>/pr.json` and query nothing; when the
   `url` differs (the manifest changed the bundle's PR), remove the file and query as
   on a new run. Read every PR field below from that file with `jq`, for example
   `jq -r .headRefOid forge/<bundle>/pr.json`. When `gh` is missing or not
   authenticated, or `jq` is missing, stop and say the PR needs `gh` and `jq`, or an
   exported file. A stop anywhere in this section removes what it wrote: on a new run,
   the run directory (it holds only `forge/` files at that point, and `runs.json` is
   written at D6, after this section); under `/cca:resume`, the `forge/<bundle>/pr.json`
   files this section wrote or renamed.
2. When the manifest gives a `branch` that is not the PR's `headRefName`, or a `base`
   that is not the PR's `baseRefName` (`<remote>/<name>` and `<name>` are equal), stop
   before stage 1 and show both values.
3. The bundle's head is the PR's `headRefOid` for a GitHub PR, else the sha the
   `branch` resolves to. For a GitHub PR, settle A5 here, from `url` in `pr.json`
   (a repo with no remote stops the run: `bundle <name>: no remote`). Its base ref is
   `<remote>/<baseRefName>` for a GitHub PR, else the `base` ref. Its base sha, the
   pinned base, is the sha that ref resolves to locally after step 1a (and its fetch,
   when one was approved); step 3 resolves it. The PR's `baseRefOid` is GitHub's cached
   base at the PR's last sync, not the live branch tip, so it is never the pinned
   base; the brief records it for information only, as the base as GitHub last
   evaluated it. For a bundle with `head: working-tree`, the head is instead the commit
   step 1c builds, and step 1a fetches no head for it. For a GitHub PR, `headRefOid` is
   recorded for information only, and the brief says so when it differs from the local
   `HEAD`. The checked-out branch check of A.4 runs here for a bundle that has no
   manifest `branch`, against `headRefName`, and then so does the `working-tree.sh check`
   of A.4, still before step 1b.

## D. Run directory, run id, and state files

D1 to D4 run after section B and before section C; D5 to D7 run after section C.
Under `/cca:resume` (first rerun stage 1), skip D1 to D4 and D6: reuse the existing
run directory, run id, and `runs.json` entry. Do D5, since `manifest.json` is a
stage 1 output. In D7, keep `approvals` and every stage's `superseded` records
(including the move records resume made for stage 1 outputs when the stage 1 entry was
missing), and only rewrite the stage 1 entry as `running` with its inputs.

1. The **primary repo** is the session's repository if it is one of the bundles,
   otherwise the first bundle.
2. `<scratch>` is the first match of:
   1. the manifest's `scratch` key, when it has one: the path must lie inside the primary
      repo's top level and `git -C <primary> check-ignore -q <scratch>/` must succeed;
      then `<scratch>` is that path, created with `mkdir -p` when missing. Otherwise stop
      before stage 1 with `scratch <path>: not an ignored path inside <primary repo>`.
      With the key present, rules 2 to 4 are not tried. Under `/cca:resume`, the run
      keeps its recorded directory even when `scratch` changed;
   2. `scratch/`, `tmp/`, or `.scratch/` in the primary repo, when the directory exists
      and `git -C <primary> check-ignore -q <dir>/` succeeds;
   3. `.cca/` in the primary repo, when `git -C <primary> check-ignore -q .cca/`
      succeeds;
   4. `${CLAUDE_PLUGIN_DATA}/runs/`.
3. The run id is `<YYYY-MM-DD-HHMM>-<slug>`, local time. The slug is the first
   bundle's name followed by its PR number, or its branch name when it has no PR, both
   as the manifest or the prompt input gave them (no `gh` call), lowercased, with runs
   of characters outside `a-z0-9` turned into one `-`, at most 40 characters. For a
   bundle whose PR is a `file:` export, the PR part is the export's `id` (section B)
   or, failing that, the bundle's `branch`, never the file path. When
   `${CLAUDE_PLUGIN_DATA}/runs.json` already has that id or `<scratch>/cca/<run-id>/`
   exists, add `-2`, then `-3`, and so on.
4. Create `<scratch>/cca/<run-id>/`. This is the run directory.
5. State the merged, normalized manifest to the user as a fenced JSON block and save
   it as `manifest.json` in the run directory.
6. Add the run to `${CLAUDE_PLUGIN_DATA}/runs.json` with `state: running` (read the
   array, or start one; write a temporary file beside it; rename).
7. Write `stages.json` with `plugin_version` `0.3.0`, empty `approvals`, and a stage 1
   entry with status `running` and inputs: the hashes of `manifest.json`, each claims
   file, the questions file, and every `file:` ticket or PR export, and
   `plugin_version`. Step 10 adds the shas and `forge_hashes` to the final entry.

## Steps

### 1. Fetch approval and baseline

a. For each audited repo (bundles, references, sources of truth), decide which refs
   are missing or stale: a ref is missing when
   `git -C <repo> rev-parse --verify <ref>^{commit}` fails; a bundle's head is stale
   when the PR's `headRefOid` is not the sha of any local ref, or is not present
   (`git -C <repo> cat-file -e <sha>^{commit}` fails); a GitHub PR bundle's base is
   missing when `<remote>/<baseRefName>` does not resolve locally. A present base ref
   may be behind the branch, and nothing but a fetch can tell, so the base fetch below
   is always part of the question for every GitHub PR bundle, and for every bundle
   whose `base` is a remote-tracking ref `<remote>/<branch>`; a run with such a bundle
   therefore always asks once. On decline, the local base ref is used as is and the
   brief records "base: local ref, refresh declined", which the report's Coverage
   repeats. Ask the user once, listing each repo, remote, the refs involved, and the
   exact fetch commands below, for approval to `git fetch`. Record the answer in `stages.json`
   `approvals` with kind `fetch`, target `<repo name>:<remote>`, the decision, the
   time, `commands`, the exact fetch commands actually run, and `resolved`, a map from
   each bare name to the kind the check found (`tag` or `branch`), one entry per repo
   and remote.
   For each missing bare name, the question lists the check
   `git -C <repo> ls-remote --tags <remote> refs/tags/<name>` (a printed line means it
   is a tag) and both candidate fetch commands: the tag refspec if it is a tag, the
   branch refspec otherwise. Nothing contacts a remote before approval; on approval,
   run the `ls-remote` check first, then the matching fetch. The approval for a bare
   name covers the check and either candidate command for that name; under
   `/cca:resume`, the recorded `resolved` kind picks the candidate, so resume matches
   it against `commands` without contacting the remote.
   On approval, run only these fetches (and the `ls-remote` check), which take no tags
   and write remote-tracking refs only. `--refmap=` (empty) keeps a configured fetch
   refspec of the remote, such as `+refs/tags/*:refs/tags/*`, from also writing its own
   destination; `--no-tags` alone does not stop that:
   - for a GitHub PR bundle whose head is missing or stale:
     `git -C <repo> fetch --no-tags --refmap= <remote> +refs/pull/<n>/head:refs/remotes/<remote>/pr/<n>/head`
   - for a GitHub PR bundle, always, and for any bundle whose `base` is a
     remote-tracking ref `<base remote>/<baseRefName>`, where `<base remote>` is the
     remote the ref itself names (a configured remote of the repo, whether or not it
     is the selected one, present ref or not), else the selected remote:
     `git -C <repo> fetch --no-tags --refmap= <base remote> +refs/heads/<baseRefName>:refs/remotes/<base remote>/<baseRefName>`
     (a second remote is listed in the same question with target
     `<repo name>:<base remote>`)
   - for a missing ref that is a 40-hex sha:
     `git -C <repo> fetch --no-tags --refmap= <remote> +<sha>:refs/remotes/<remote>/cca/<sha>`;
     when the remote refuses (not every server serves arbitrary shas), stop `blocked`
     naming the sha, and resolve it as `<remote>/cca/<sha>` from then on;
   - for a missing ref `<name>` that is a tag on the remote:
     `git -C <repo> fetch --no-tags --refmap= <remote> +refs/tags/<name>:refs/remotes/<remote>/tags/<name>`,
     and resolve it as `<remote>/tags/<name>` from then on;
   - for any other missing ref: when the ref is `<other>/<branch>` and `<other>` is a
     configured remote of the repo (`git -C <repo> remote`), split it there and run
     `git -C <repo> fetch --no-tags --refmap= <other> +refs/heads/<branch>:refs/remotes/<other>/<branch>`
     (when `<other>` is not the selected remote, the question lists it, under the same
     approval, with target `<repo name>:<other>`); a prefix that is not a configured
     remote makes the whole ref a bare branch name that contains a slash. When it is a
     bare `<branch>`, fetch the same refspec from the repo's selected
     remote and resolve the ref as `<remote>/<branch>` from then on, since the fetch
     never writes a local branch.

   A bundle with `head: working-tree` takes no head fetch, and the stale-head test does
   not apply to it: its head does not exist until step 1c. Its base fetch is as above.

   Every ref that resolves under another name is recorded as one mapping line in the
   brief's Read paths: `<ref as given> -> <remote>/<branch>`,
   `<ref as given> -> <remote>/tags/<name>`, or `<sha> -> <remote>/cca/<sha>`. Resume
   resolves each ref through these lines before `rev-parse`. A ref that still cannot
   be fetched stops the run `blocked` naming it, before step 1b.

   A remote configured with `remote.<name>.prune` may also delete stale remote-tracking
   refs; `--prune` is never added, and this is accepted as part of the approved fetch.
   After fetching, verify with `git -C <repo> cat-file -e <sha>^{commit}` that each
   pinned head sha exists, and with `git -C <repo> rev-parse --verify <ref>^{commit}`
   that every other fetched ref, and for a GitHub PR its base ref
   `<remote>/<baseRefName>`, now resolves; if one does not, stop `blocked` naming the
   sha or ref. On decline, a bundle whose head or base still does not resolve stops the
   run `blocked` with the reason. Under `/cca:resume`, a recorded approval covers only
   the commands in its `commands` list. When the planned commands for a repo and
   remote are all in one recorded list for that target, they are not asked again.
   Otherwise ask once, as above, listing the new commands, and record a new approval
   entry.
b. Take the read-only baseline now, before any other work. For each audited repo
   `<name>`, with `baseline/` created in the run directory first, run
   `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/readonly.sh snapshot <repo> <run dir> <run dir>/baseline/<name>`
   with the resolved absolute script path. It writes `baseline/<name>.marker` (its own
   marker, created first) and `baseline/<name>.status`, `.refs`, `.stash`, `.config`,
   `.hashes`, and `.ignored`. A repo that appears in more than one role is snapshotted
   once. A non-zero exit ends the run `blocked`, since the boundary cannot be checked;
   show the script's message.
c. For each bundle with `head: working-tree`, build its head now, right after the
   baseline, so the stage's read-only check covers any edit made between the baseline and
   the build. Run
   `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/working-tree.sh build <repo>` with the
   resolved absolute script path. It builds a commit from the working tree in a temporary
   index copied from the repo's own, so the repo's index, refs, and files are untouched,
   and a file staged despite an ignore rule is kept; its only writes to the repo are git
   objects. It runs the same refusal checks as A.4's `check` first. Exit 0 prints, on
   stdout, `head <sha>`, `parent <sha>`, `tree <sha>`, and one `untracked <path>` line per
   untracked file that is not ignored; keep all four. The head commit has no ref, and the
   same working tree and `HEAD` give the same sha. Exit 1 is a refusal (a missing `HEAD`
   commit, a repo or checked-out submodule with no index file, a sparse checkout,
   skip-worktree or assume-unchanged paths, unmerged paths, a dirty submodule or an
   untracked nested repository, a Git LFS or program filter, or a path git prints quoted):
   the script writes one line per reason on stderr, before it writes anything; end the run
   `blocked` and show those lines. Exit 2 (usage, not a work tree, or a git step failed;
   one line on stderr) ends the run `blocked` the same way.

### 2. Forge data

For each bundle, save under `forge/<bundle>/`:

- `pr.md`: title, body, state, reviews, and review threads (file, line, comments),
  rendered from `pr.json` and `pr-threads.json` below (`pr.json` is raw, so the author
  of a review or comment is its `author.login`). For an export, copy its content.
- `<ticket>.md` for each ticket in the bundle, and each ticket the PR's
  `closingIssuesReferences` names: text, state, acceptance criteria, fields, links,
  comments, rendered from the ticket's `.json` below (for a GitHub ticket, the pull
  requests that close it, from `closed_by`, are listed under links). For an export, copy
  its content.

Every saved `.md` file starts with a provenance block: the source (`gh`, or the export's
`source`, `exported_by`, and `exported_at`), and the time it was read. When no forge
was queried for a bundle, the brief says so.

For a GitHub PR or issue, the `gh` calls below write their output by shell redirect,
unchanged (never through the model), beside the rendered files. The hashed content is
a fixed projection of the fields, not the raw JSON, because viewer-dependent fields
such as `viewerDidAuthor` and reactions, would otherwise change the hash and
invalidate stage 1 on resume under another login; the head and base shas are left out
because resume step 3 compares them first and stops on a change. Resume runs these
identical
commands and the same `jq` projection.

- `forge/<bundle>/pr.json`, the one `gh pr view` call, unprojected (section C runs it
  and parses it; no second call is made):
  `gh pr view <n> -R <owner>/<repo> --json number,url,title,body,state,headRefName,headRefOid,baseRefName,baseRefOid,closingIssuesReferences,reviews,comments > forge/<bundle>/pr.json`
- `forge/<bundle>/pr.hash.json`, the hashed form of the PR, a `jq` projection of
  `pr.json` that leaves out `baseRefOid`, `headRefOid`, and the viewer-dependent
  fields:
  `jq '{number,url,title,body,state,headRefName,baseRefName,closingIssuesReferences: [.closingIssuesReferences[] | {number, url}],reviews: [.reviews[] | {author: .author.login, state, body, submittedAt}], comments: [.comments[] | {author: .author.login, body, createdAt}]}' forge/<bundle>/pr.json > forge/<bundle>/pr.hash.json`
- `forge/<bundle>/pr-threads.json`, the review threads:
  `gh api --paginate repos/<owner>/<repo>/pulls/<n>/comments --jq '.[] | {id, path, line, original_line, commit_id, body, user: .user.login, created_at, updated_at, in_reply_to_id}' > forge/<bundle>/pr-threads.json`
- `forge/<bundle>/<ticket>.json`, one per GitHub ticket:
  `gh issue view <n> -R <owner>/<repo> --json number,url,title,body,state,labels,comments,closedByPullRequestsReferences --jq '{number,url,title,body,state,labels: [.labels[].name], closed_by: [.closedByPullRequestsReferences[] | {number, url}], comments: [.comments[] | {author: .author.login, body, createdAt}]}' > forge/<bundle>/<ticket>.json`

Hash `pr.hash.json`, `pr-threads.json`, and each `<ticket>.json` with
`git hash-object --no-filters <file>`; the threads and ticket files are hashed as
written (their `--jq` output is already the projection), and `pr.json` itself is never
hashed. Step 10 records the hashes in the stage 1 entry's inputs as `forge_hashes`, a
map from run-relative path (such as `forge/<bundle>/pr.hash.json`) to hash. Exports
(`file:` tickets and PRs) have no `.json` file and no entry in `forge_hashes`; their
content hashes are in D7.

### 3. Shas

For each bundle, record:

- head sha and base sha (both from step C3: the head is the PR's `headRefOid` for a
  GitHub PR, else what the `branch` ref resolves to; the base is what the base ref
  resolves to, for a GitHub PR `<remote>/<baseRefName>`, always with
  `git -C <repo> rev-parse <ref>^{commit}` after step 1a (and its fetch, when one was
  approved), never the PR's `baseRefOid`). Wherever the steps below write `<base>` and
  `<head>`, use these shas. For a bundle with `head: working-tree`, the head is the
  `head` sha step 1c printed, and its `parent` and `tree` shas are recorded too (step
  10.6 puts them in the stage 1 inputs);
- merge-base sha: `git -C <repo> merge-base <base> <head>`;
- commits on the base since the merge-base: `git -C <repo> log --oneline <head>..<base>`;
- files changed on both sides since the merge-base: the intersection of
  `git -C <repo> diff --name-only <base>...<head>` and
  `git -C <repo> diff --name-only <head>...<base>`.

For every reference and source of truth with a `path`, record its pinned sha:
`git -C <path> rev-parse <ref>^{commit}`.

### 4. Diffs

For each bundle, write:

- `diffs/<bundle>.diff`: `git -C <repo> diff <base>...<head>`.
- `diffs/<bundle>.stat`: `git -C <repo> diff --numstat <base>...<head>`, one file per
  line with added and deleted counts (`-` for binary files).

Always three dots. A two-dot diff is never used, because it shows changes on the base
as reversals on the head.

### 5. Stacks

When one bundle's base sha, or base ref, is another bundle's head, record the stack in
order. The brief states the combined state under audit: each bundle at its head, with
stacks read in order, each bundle's diff taken against the bundle below it.

### 6. Readable trees

For every bundle at its head sha, and every reference and source of truth at its
pinned sha, decide how agents read it:

1. **Direct**: when `git -C <repo> rev-parse HEAD` is that sha,
   `git -C <repo> --no-optional-locks status --porcelain --untracked-files=no` is empty,
   and `git -C <repo> ls-files -v` shows no path flagged `S`, `h`, or `s` (skip-worktree
   or assume-unchanged). Agents read the
   checkout and search per the direct-read rules in `common.md`. A bundle with
   `head: working-tree` is direct when `git -C <repo> rev-parse HEAD` is the `parent`
   sha step 1c printed and no path is flagged `S`, `h`, or `s`; its modified and
   untracked files are part of the head, so the status condition does not apply. Its
   mode in the brief is `direct (working tree)`, and agents search it with
   `git -C <repo> grep <pattern> <head sha>` (`common.md`).
2. **Export**: otherwise. First size it: the sum of blob sizes from
   `git -C <repo> ls-tree -r -l --full-tree <sha>`. Over 1 GB (1,073,741,824 bytes),
   ask the user first and record the answer in `approvals` with kind
   `export-over-1gb`. If declined, the repo is read with `git -C <repo> show
   <sha>:<path>`, and only agents with Bash may be assigned to it (every role but the
   merger). Otherwise export it:
   0. Remove `<run dir>/trees/<name>/` if it exists (`rm -rf`, inside the run directory
      only), so no file from an earlier export remains.
   1. List the tree: `git -C <repo> ls-tree -r -z --full-tree <sha>` into
      `trees/<name>.lstree`. Each entry is `<mode> <type> <object>\t<path>`, NUL
      terminated.
   2. Write every entry under `<run dir>/trees/<name>/` from one
      `git -C <repo> cat-file --batch` stream, with a script saved as
      `trees/<name>.export.sh` in the run directory and run with `sh`. The script
      reads the entry list, sends each blob's object id to `cat-file --batch`, and
      for each reply header `<oid> <type> <size>` copies exactly `<size>` bytes with
      `head -c <size>` into the file and discards the one newline that follows.
      Where `head -c` may read ahead (non-GNU `head`), write each blob instead with
      `git -C <repo> cat-file blob <oid> > <file>`.
   3. By mode:
      - `100644`: a regular file.
      - `100755`: a regular file with the executable bit.
      - `120000` (a symlink): a regular file holding the blob's content, which is the
        link target. List it in the brief. Never dereference it.
      - `160000` (a submodule): list its path and commit in the brief; do not export.
   4. A blob whose content starts with `version https://git-lfs.github.com/spec/v1`
      is a Git LFS pointer and is exported as the pointer file. List these in the
      brief and say the content is the pointer, not the object.
   5. A path containing a newline is not exported and is listed in the brief.
   `cat-file` reads objects only, so no checkout filter, smudge or process driver, or
   attribute runs. Never use `git archive` (it honors `export-ignore` and
   `export-subst`) or `git checkout-index` (it runs configured filters, which can reach
   the network or write outside the run directory), and never check out, switch, or
   add a worktree.

The brief maps each name to the path agents must read, the sha, and the mode (`direct`,
`direct (working tree)`, `export`, or `git show`). An export holds tracked files only, so
no test or lint command runs in an export, whether or not it needs installed dependencies;
a check run is done only in a directly read tree, and otherwise the question is marked
"not run".

Classify each source of truth with a `path` for stages 2 and 3: count the tracked files
at the pinned sha by extension; when more than half are documents (`.md`, `.mdx`,
`.markdown`, `.txt`, `.rst`, `.adoc`, `.asciidoc`, `.html`, `.htm`, `.pdf`), it is a
**document corpus**, else a **code base**. Record the class and the counts in the brief.

### 7. Claims

Write `claims.md` from every claims file, numbered from 1 across all files, in file
order. One claim per line, in these shapes:

```
<n>. [claim:<kind>] <bundle>/<ticket or none> <source file>:<line> (<handoff ref>): <text> -> <target>
<n>. [claim:<kind>] <bundle>/<ticket or none> <source file>:<line>: <text> -> <target>
<n>. [other] <bundle or none>/<ticket or none> <source file>:<line>: <text> -> none
```

The first shape is for a handoff's claims, the second for a prose claims file's, the
third for a prose sentence that is not a claim. `<ticket>` is the manifest's normalized
id when the handoff id maps to one (section B, step 8), else the handoff's id.
`<target>` is a group id from `groups.md`, or `hygiene`; step 9 appends it.

The kinds, and for prose the typing rule (the first that applies, in this order):

1. `verification`: says something was checked, tested, verified, confirmed, reproduced,
   or passes.
2. `decision`: states a choice made or rejected, a deferral, or who decided.
3. `scope`: says what belongs in or out of the bundle, or ranks a ticket for inclusion.
4. `status`: a work item's type, state, iteration, owner, or links.
5. `code`: any other checkable statement about code, data, or behavior.

A handoff's claims come from
`sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/handoff.sh claims <file>`: one claim per
output line, never split further, with the kind, ref, bundle, ticket, line, and text
the script gives (never a kind chosen by judgment). The handoff's other lines are not
listed. A prose claims file keeps the sentence split: every sentence, in file order,
with a kind by the rule above for a checkable statement about the work, and `other` for
anything else. Headings, list items, and table cells count as sentences. Nothing is
dropped; a sentence split across lines takes its first line. Tag each with the bundle
and ticket it concerns, or `none`.

### 8. Groups

Map every changed file in every bundle's `.stat` to a review group in `groups.md`.
Group ids are lowercase slugs: a ticket's group is `<bundle>-<ticket number or file
name>`; the fixed groups are `unticketed` and `cross-cutting`.

With a manifest `groups` key, it replaces the derivation, the extraction, and the
merge: each entry is a group named by its `name`; its globs are relative to the entry's
`repo`; a file matching two entries goes to both with a note; changed files no entry
matches go to `unticketed`. Skip to the format below.

Otherwise derive, per bundle:

1. A ticket's commits are those whose message names the ticket's id token: for a GitHub
   issue `github:owner/repo#n`, `owner/repo#n`, and `#n` when the issue is in the bundle's
   repo; for an exported ticket, its `id`, or, when the bundle has `ticket_token`, each
   pattern with `{n}` replaced by the `id` as written, in place of the bare `id`. A
   pattern is a literal template, never a regex: every character but `{n}` stands for
   itself, so `.` in `ticket.{n}` is a dot. A GitHub ticket keeps its own tokens. A token
   matches only when the character before it, if any, and the character after it, if any,
   are neither a letter nor a digit; for a pattern, the whole token is the unit, so the
   rule applies outside it.
   Before a GitHub token the character is also not `-`, `_`, `.`, or `/`, since those join
   owner and repo names. So `#12` does not match `#123`, `owner/app#12` does not match
   `other-owner/app#12`, and `APP-1` does not match `APP-10`, `APP-1a`, or `XAPP-1`, but
   it matches in `feature/APP-1`. With the pattern `#{n}`, a commit `fix(#4567 #4568)` is
   both tickets' commit, and `build 4567 passed` and `AB#4567` are neither's (the letters
   before `#` break the boundary); `AB#{n}` matches `AB#4567`; `[{n}]` matches only the
   bracketed `[4569]`. In a bundle with one ticket, every commit is that ticket's. The
   commits a handoff lists for the ticket are also its commits: run
   `sh ${CLAUDE_PLUGIN_ROOT}/skills/cca/scripts/handoff.sh commits <file>` (one
   `<bundle>`, `<sha>`, `<ticket>`, `<line>` per line, tab-separated) and match each sha
   by prefix among the bundle's commits from the merge-base to the head
   (`git -C <repo> log --format=%H <merge-base>..<head>`). A handoff commit that matches
   no commit or more than one, and a commit whose message names another ticket than the
   handoff gives, is noted in the brief's Handoff section. Groups follow the union of
   both sets.
2. A ticket's group holds the changed files that the PR description, the commit
   messages, or the ticket text name (by path or by file name), and every changed file
   touched by any of that ticket's commits. A file touched by several tickets' commits
   goes to each of those groups, with a note naming the tickets.
3. Files no ticket explains go to `unticketed`.
4. A file whose mapping is uncertain is listed in both groups with a note saying why.
5. **Extraction.** A file present in more than two derived groups moves to
   `cross-cutting`, and stays listed in each former group with the note
   `moved to cross-cutting`.
6. **Merge.** After extraction, two ticket groups merge when each has more than half of
   its remaining files in the other. Check pairwise in ticket order, once; a merged
   group is not checked again. The merged group's id joins both with `+`, and the brief
   records the merge.

Format:

```
## <group id>: <ticket id or entry name, or unticketed or cross-cutting>
- <bundle>:<path> (+<added> -<deleted>) [note]
```

Write the `unticketed` and `cross-cutting` sections only when they have at least one
file. Every changed file appears in at least one group. The tests, work-item hygiene, and
cross-bundle interaction specialists of stage 4 are scopes, not groups.

A `head: working-tree` bundle's head commit, `cca: working tree`, names no ticket. In a
bundle with more than one ticket, a file that only that commit changes is matched to a
ticket by name (rule 2) or goes to `unticketed`. The brief says so.

### 9. Claim assignment

Append ` -> <target>` to every `claim` line in `claims.md`:

1. Every `scope` and `status` claim goes to `hygiene`, which is not a group. Stage 4
   gives the `hygiene` claims to the `hygiene` scope at high, to `tests-hygiene` at
   medium, and to `combined` at low.
2. A `code`, `decision`, or `verification` claim goes to the group whose files it
   concerns; a claim about a `cross-cutting` file goes to `cross-cutting`.
3. Such a claim that names no file goes to its ticket's group when that group exists in
   `groups.md`; else to the first group in `groups.md` that holds a file of the
   claim's bundle; else to the first group in `groups.md`.
4. Never assign a claim to a group that is absent from `groups.md` or has no files.

`other` lines get ` -> none`. Before finishing the stage, check that every `claim`
line names `hygiene` or a group present in `groups.md` with at least one file, so each
claim has a scope that stage 4 schedules; reassign any that does not by rule 3.

### 10. Brief, common, tier, and the end of the stage

1. **Tier.** Count bundles, distinct tickets, and changed lines (added plus deleted
   across every `.stat`; binary files count 0 and are noted). The tier is the first
   row whose conditions all hold:
   - `low`: 1 bundle, 1 ticket, under 500 changed lines;
   - `medium`: up to 3 bundles, up to 5 tickets, under 5,000 changed lines;
   - `high`: anything else.
   `effort` other than `auto` overrides it. Write the tier and the reason, with the
   counts, or "set by --effort". At low, the brief notes that one auditor covers the
   ticket, tests, and work-item hygiene with the same checklist, a departure from
   separate specialists.
2. **Stage applicability.** Stage 2 is applicable when at least one source of truth is
   a document corpus, stage 3 when at least one is a code base. Record both in the
   brief.
3. **`audit-brief.md`**, with these sections: Scope (bundles, repos, PRs, tickets);
   Tier and reason; Bundles (head, base, merge-base, base commits since the merge-base,
   files changed on both sides, stack, the `ticket_token` patterns when the bundle has
   them; the head sha is recorded as `headRefOid` for a GitHub PR, and the pinned base sha
   is the local sha of `<remote>/<baseRefName>`; for a GitHub PR also `baseRefOid`,
   labeled "base as GitHub last evaluated it", for information only; resume compares the
   head and the pinned base; a `head: working-tree` bundle also gets its `parent` sha, its
   `tree` sha, that the head is a built commit with no ref, the files "untracked at audit
   time" one per line (part of the head, but possibly left out of the user's own commit),
   the groups note of step 8, and for a GitHub PR the `headRefOid` and, when it differs
   from the local `HEAD`, a line saying so); Combined state; Sources of truth (the order
   used, each with its sha and class, and whether it replaced the default); References
   (each with its sha); Read paths (name, path, sha, mode; plus each ref mapping line from
   step 1a); Export notes (symlinks with targets, submodules, LFS pointers, skipped paths,
   declined exports); Forge (queried or not, per bundle; "not in export" keys); Questions;
   Stage applicability; Run directory (its path, and whether it is inside the session's
   repository); Test injection (the `_test` key, when present); Handoff (each handoff file
   with its hash and that it passed `handoff.sh check`, its claim counts by kind, the
   bundle and ticket mapping notes of section B, and the commit notes of step 8; "none"
   when no claims file is a handoff); Claims (a statement that every claim is assigned to
   a scope that stage 4 schedules, with the count per kind and per target); Corrections
   (filled in stage 5).
4. **`common.md`**: read the template `${CLAUDE_PLUGIN_ROOT}/skills/cca/common.md` with
   the Read tool and write the copy to `common.md` in the run directory with the Write
   tool (not `cp`), filling its header: run id, run directory, tier, and the question
   list.
5. Run the read-only check (SKILL.md, Read-only check), which writes
   `baseline/1-check.md`.
6. Write the stage 1 entry: status `complete`, outputs `manifest.json`,
   `audit-brief.md`, `common.md`, `claims.md`, `groups.md`, every `diffs/` file, every
   `forge/` file, every `trees/<name>/` export with its `trees/<name>.lstree` and
   `trees/<name>.export.sh`, and `baseline/1-check.md`. Its inputs are those D7
   recorded plus each bundle's head, base, and merge-base sha (the pinned base is the
   local sha of the base ref; `baseRefOid` is recorded beside it for a GitHub PR, for
   information only), `head_parent` and `head_tree` for each `head: working-tree`
   bundle, the pinned sha of every reference and source of truth, and `forge_hashes`
   (step 2).
7. Print the stage boundary line. With `budget: 0`, or `_test`
   `expire_budget_after_stage: 1`, the budget has now expired: go to stage 8. Otherwise
   start stages 2, 3, and 4 together.
