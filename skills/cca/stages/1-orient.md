# Stage 1: orient

The orchestrator runs this stage alone. Sections A to D happen before stage 1 proper: a
stop there ends the command with one message, and nothing is written except as
sections C and D say. Their labels are fixed, but they run in this order: A, B, D1 to
D4 (the run directory exists before any PR is read), C, then D5 to D7. Steps 1 to 10
follow the stage's rule numbers. Order matters: the read-only baseline (step 1b) is
taken right after the approved fetch, before any export or other stage 1 work, so
everything after it is checked.

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
   - Bundle names: the repo directory's base name, lowercased, with `-2`, `-3` added
     when two bundles share it. `<bundle>` in file names below is this name.
     References and sources of truth keep their `name`, slugged the same way.
   - Ticket and PR ids to `github:owner/repo#n` or `file:<absolute path>`. A short id
     such as `#159` is accepted only when the bundle's repo has exactly one GitHub
     remote (`git -C <repo> remote -v`); otherwise stop with
     `<id>: write it as github:owner/repo#n or file:<path>`.
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
   base is rejected: stop with `bundle <name>: no base`.
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
   evaluated it.

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
   1. `scratch/`, `tmp/`, or `.scratch/` in the primary repo, when the directory exists
      and `git -C <primary> check-ignore -q <dir>/` succeeds;
   2. `.cca/` in the primary repo, when `git -C <primary> check-ignore -q .cca/`
      succeeds;
   3. `${CLAUDE_PLUGIN_DATA}/runs/`.
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
7. Write `stages.json` with `plugin_version` `0.1.0`, empty `approvals`, and a stage 1
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
b. Take the read-only baseline now, before any other work:
   1. Create `baseline/marker` (an empty file) in the run directory.
   2. For each audited repo `<name>`, write:
      - `baseline/<name>.status`:
        `git -C <repo> status --porcelain=v2 --branch --untracked-files=all`
      - `baseline/<name>.refs`: `git -C <repo> for-each-ref`
      - `baseline/<name>.stash`: `git -C <repo> stash list`
      - `baseline/<name>.config`: `git -C <repo> config --list --local`
      - `baseline/<name>.hashes`: `git -C <repo> hash-object --no-filters <path>` for
        every modified and untracked file the status lists, one `hash path` per line
      - `baseline/<name>.ignored`: every file
        `git -C <repo> status --porcelain=v2 --ignored --untracked-files=all` marks
        `!`, with size and modification time (`stat -c '%s %Y %n'`, or
        `stat -f '%z %m %N'` where `stat` is BSD), excluding `.git/` and the run
        directory.
   A repo that appears in more than one role is snapshotted once.

### 2. Forge data

For each bundle, save under `forge/<bundle>/`:

- `pr.md`: title, body, state, reviews, and review threads (file, line, comments),
  rendered from `pr.json` and `pr-threads.json` below (`pr.json` is raw, so the author
  of a review or comment is its `author.login`). For an export, copy its content.
- `<ticket>.md` for each ticket in the bundle, and each ticket the PR's
  `closingIssuesReferences` names: text, state, acceptance criteria, fields, links,
  comments, rendered from the ticket's `.json` below. For an export, copy its content.

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
  `gh issue view <n> -R <owner>/<repo> --json number,url,title,body,state,labels,comments --jq '{number,url,title,body,state,labels: [.labels[].name], comments: [.comments[] | {author: .author.login, body, createdAt}]}' > forge/<bundle>/<ticket>.json`

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
  `<head>`, use these shas;
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
   `git -C <repo> status --porcelain --untracked-files=no` is empty, and
   `git -C <repo> ls-files -v` shows no path flagged `S`, `h`, or `s` (skip-worktree
   or assume-unchanged). Agents read the
   checkout and search per the direct-read rules in `common.md`.
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

The brief maps each name to the path agents must read, the sha, and the mode
(`direct`, `export`, or `git show`). An export holds tracked files only, so a check run
that needs installed dependencies is done only in a directly read tree; otherwise the
question is marked "not run".

Classify each source of truth with a `path` for stages 2 and 3: count the tracked files
at the pinned sha by extension; when more than half are documents (`.md`, `.mdx`,
`.markdown`, `.txt`, `.rst`, `.adoc`, `.asciidoc`, `.html`, `.htm`, `.pdf`), it is a
**document corpus**, else a **code base**. Record the class and the counts in the brief.

### 7. Claims

Split every claims file into `claims.md`: every sentence, numbered from 1 across all
files, in file order. Each line:

```
<n>. [claim|other] <bundle>/<ticket or none> <source file>:<line>: <sentence>
```

`claim` is a checkable statement about the work; `other` is anything else. Tag each
with the bundle and ticket it concerns, or `none`. Headings, list items, and table
cells count as sentences. Nothing is dropped; a sentence split across lines takes its
first line. Step 9 appends the group.

### 8. Groups

Map every changed file in every bundle's `.stat` to a review group in `groups.md`.
Group ids are lowercase slugs: a ticket's group is `<bundle>-<ticket number or file
name>`; the fixed groups are `unticketed` and `cross-cutting`.

With a manifest `groups` key, it replaces the derivation, the extraction, and the
merge: each entry is a group named by its `name`; its globs are relative to the entry's
`repo`; a file matching two entries goes to both with a note; changed files no entry
matches go to `unticketed`. Skip to the format below.

Otherwise derive, per bundle:

1. A ticket's commits are those whose message names the ticket's full id token,
   matched whole: the token followed by a non-digit, a non-letter, or the end, so `#12`
   does not match `#123` and `APP-1` does not match `APP-10` or `APP-1a`. In a bundle
   with one ticket, every commit is that ticket's.
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

### 9. Claim assignment

Append ` -> <group id>` to every `claim` line in `claims.md`:

1. A claim goes to the group whose files it concerns; a claim about a
   `cross-cutting` file goes to `cross-cutting`.
2. A claim that names no file goes to its ticket's group when that group exists in
   `groups.md`; else to the first group in `groups.md` that holds a file of the
   claim's bundle; else to the first group in `groups.md`.
3. Never assign a claim to a group that is absent from `groups.md` or has no files.

`other` lines get ` -> none`. Before finishing the stage, check that every `claim`
line names a group present in `groups.md` with at least one file, so each claim has a
scope that stage 4 schedules; reassign any that does not by rule 2.

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
   Tier and reason; Bundles (head, base, merge-base, base commits since the
   merge-base, files changed on both sides, stack; the head sha is recorded as
   `headRefOid` for a GitHub PR, and the pinned base sha is the local sha of
   `<remote>/<baseRefName>`; for a GitHub PR also `baseRefOid`, labeled "base as
   GitHub last evaluated it", for information only; resume compares the head and the
   pinned base); Combined state; Sources of truth (the order used, each with its sha
   and class, and whether it replaced the default); References (each with its sha);
   Read paths (name, path, sha, mode; plus each ref mapping line from step 1a); Export
   notes (symlinks with targets, submodules, LFS pointers, skipped paths, declined
   exports); Forge (queried or not, per bundle; "not in export" keys); Questions; Stage
   applicability; Run directory (its path, and whether it is inside the session's
   repository: a run directory inside it avoids the inline form of the Codex request);
   Test injection (the `_test` key, when present); Claims (a statement that every claim
   is assigned to a scope that stage 4 schedules, with the count per group);
   Corrections (filled in stage 5).
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
   information only), the pinned sha of every reference and source of truth, and
   `forge_hashes` (step 2).
7. Print the stage boundary line. With `budget: 0`, or `_test`
   `expire_budget_after_stage: 1`, the budget has now expired: go to stage 8. Otherwise
   start stages 2, 3, and 4 together.
