# Resume

`/cca:resume <run-id> [--from <stage>]` reruns an audit from a stage, reusing only
artifacts whose inputs have not changed. It never reuses a stale stage and never loses
a finished one.

## Steps

1. **Find the run.** Read `${CLAUDE_PLUGIN_DATA}/runs.json` and take the entry whose
   `run_id` is the invocation's `run-id`. When there is none, or its `path` no longer
   exists, stop with one line saying so. The run directory is that `path`.
2. **Recover state.** Read, in the run directory, `manifest.json` and `stages.json`
   only. If `manifest.json` is missing, stop with one line saying the run directory is
   unrecoverable. If `stages.json` is missing, that is recoverable: the first stage to
   rerun is 1, with empty approvals and no earlier superseded records (nothing
   survives to carry over), and stage 1 writes a new `stages.json` from
   `1-orient.md` D7. Every approval in `stages.json` `approvals` stands: do not ask for
   it again. A stage whose status is `running` counts as incomplete, since its agents
   belonged to an earlier session; it is rerun, and nothing waits for its old agents.
   If the stage 1 entry is missing, is `running`, or `audit-brief.md` does not exist,
   the first stage to rerun is 1: skip steps 3 to 5, then run steps 6 to 9 with stage 1
   as the first rerun stage (step 6 supersedes any stage 1 outputs that exist; step 9
   continues with stage 1 as `1-orient.md` section D describes for resume, reusing the
   run directory, run id, `runs.json` entry, and approvals). Stage 1 on this path
   rebuilds its inputs from `manifest.json`'s `source` key merged with the prompt
   inputs and flags recorded in it, as step 4 does for hashing, and runs section A
   onward with those; the invocation block's `manifest: none` and `inputs: none` are
   ignored. Only when stage 1 is `complete` and `audit-brief.md` exists, also read
   `audit-brief.md` and `common.md`, and run steps 3, 4, and 5.
3. **Head and base sha check.** For each bundle, resolve its head and base as stage 1
   did and compare each with the head and base sha stage 1 recorded in
   `audit-brief.md`. Resolve every ref through the mapping lines in the brief's Read
   paths (`<ref as given> -> <remote>/...`) before `rev-parse`. For a GitHub PR, run
   the `gh pr view` command of `1-orient.md` step 2 once, with its output redirected
   to `forge/<bundle>/pr.json.new`, and read `headRefOid` and `baseRefOid` from that
   file with `jq`; step 4 projects the same file, with no second query. For any other
   bundle, the shas its `branch` and `base` refs resolve to. Then:
   - A changed head: stop and ask whether to restart from stage 1, showing each
     bundle's recorded and current shas. On yes, the first stage to rerun is 1. On no,
     stop and change nothing.
   - A changed base sha alone does not stop or invalidate. Compare the merge base
     recorded in `audit-brief.md` with
     `git -C <repo> merge-base <current base sha> <recorded head sha>`. When they are
     equal, continue: record the current base sha as `base moved` (stage entry key
     `base_moved`, a map from bundle to the current base sha) in the first rerun
     stage's entry and in the report's Coverage, and keep the recorded base sha for
     every diff and every comparison. When they differ, or the current base sha is
     not present locally (resume does not fetch), ask as for a changed head.
   On a stop, remove every `forge/<bundle>/pr.json.new`. When stage 1 reruns, it keeps
   these files and reuses them (`1-orient.md` section C); otherwise step 5 removes
   them.
4. **Recompute input hashes.** For each stage entry, recompute every input it records,
   the same way it was recorded:
   - stage 1: the manifest (the file named in `manifest.json`'s `source` key, merged
     again with the recorded prompt inputs and flags and normalized, then compared with
     `manifest.json`), each claims file, the questions file, the content hash of
     every `file:` ticket or PR export, and `plugin_version`;
   - the stage 1 `forge_hashes`: recompute each path in the map (`1-orient.md` step 2:
     `pr.hash.json`, `pr-threads.json`, `<ticket>.json`) and compare it with the
     recorded hash. For `pr.hash.json`, project the one file step 3 already fetched
     with the identical `jq` command of step 2, reading
     `forge/<bundle>/pr.json.new`, and hash the result, with no second query:
     `jq '<filter>' forge/<bundle>/pr.json.new | git hash-object --no-filters --stdin`.
     The projection leaves out `headRefOid` and `baseRefOid`, so a base moved by step 3
     does not change the hash. For `pr-threads.json` and each `<ticket>.json`, run the
     identical `gh` command of step 2, with the same owner, repo, number, and
     projection, and with its `> <path>` redirect replaced by
     `| git hash-object --no-filters --stdin`, so no file is written. A difference
     invalidates stage 1. Keep each `forge/<bundle>/pr.json.new` until step 5 picks the
     first stage to rerun; step 5 removes them unless that stage is 1 (then stage 1
     renames them, `1-orient.md` section C), and any stop removes them. A `gh` or `jq`
     failure during the re-query stops resume with one line, since the brief's evidence
     cannot be confirmed current;
   - each bundle's head, base, and merge-base sha and the pinned sha of every
     reference and source of truth, by resolving each again as stage 1 did, through
     the brief's ref mapping lines (step 3), and for a GitHub PR from step 3's result;
     a changed one invalidates stage 1, except a base sha that step 3 accepted as
     `base moved`, whose recorded value stands;
   - upstream stage outputs, by `git hash-object --no-filters <file>`;
   - `plugin_version`, which for this release is `0.1.0`.
   A stage's inputs have changed when any recomputed value differs from the recorded
   one, or when an input is missing.
5. **Pick the first stage to rerun.** It is the earliest of:
   - the `--from` stage, when given;
   - the first stage, in the order 1 to 8, whose entry is missing, or whose status is
     anything other than `complete` or `not_applicable` (such as `running`, `failed`,
     or `superseded`), or that is `complete` but lists an output that does not exist;
   - the first stage whose input hashes changed;
   - stage 1, when any tree `audit-brief.md` maps as `direct` fails a direct-read
     condition now: `git -C <repo> rev-parse HEAD` is not the pinned sha,
     `git -C <repo> status --porcelain --untracked-files=no` is not empty, or
     `git -C <repo> ls-files -v` shows a path flagged `S`, `h`, or `s`. Rerunning
     stage 1 re-exports it.
   A `not_applicable` stage whose inputs have not changed is reused. When the first
   stage to rerun is not 1, or nothing needs a rerun, remove every
   `forge/<bundle>/pr.json.new` now. When nothing needs a rerun and no `--from` was
   given, say the run is current, print its report path and terminal state (and any
   `base moved` shas), and stop.
6. **Supersede.** Every stage from the first rerun stage through stage 8 is rerun. For
   each of those stages that has an entry, in order:
   1. Move each of its outputs that exists to `superseded/<k>/<path>`, where `<k>` is
      one more than the highest number already under `superseded/`, keeping the
      run-relative path (so `ledger/5.md` goes to `superseded/<k>/ledger/5.md`).
      Stage 5's outputs include `ledger/5.md`, stage 6's `ledger/6.md`, and stage 7's
      `ledger/7.md`, each with its stage.
   2. Rewrite its entry with status `superseded` and, in its `superseded` list, one
      record per moved output: `path`, `moved_to`, and `time`.
   The files `forge/<bundle>/pr.json.new` that step 3 wrote are never moved; stage 1
   renames them (`1-orient.md` section C).
   When the first rerun stage is 1 and its entry is missing or `running`, supersede
   the stage 1 outputs that exist (those `1-orient.md` step 10.6 lists) the same way.
   When `stages.json` is missing, no entry lists outputs, so walk the run directory
   instead: move every one of these paths that exists to `superseded/<k>/<path>`:
   `audit-brief.md`, `common.md`, `claims.md`, `groups.md`, `diffs/`, `forge/`,
   `trees/`, `guidelines/`, `domain/`, `scope/`, `pass1/`, `pass2/`, `ledger/`,
   `codex/`, `late/`, `converged/`, `converged.md`, `gate.md`, `report.md`, `usage.md`,
   and `baseline/`. `manifest.json`, `stages.json`, and `superseded/` are never moved.
   With no entry to rewrite, keep the move records (`path`, `moved_to`, `time`) and put
   them in the `superseded` list of the new stage 1 entry when stage 1 writes it
   (`1-orient.md` section D, step D7).
   Stages before the first rerun stage keep their entries and outputs unchanged and
   are reused as they are.
7. **Baseline.** When the first rerun stage is 1, stage 1 takes the baseline again.
   Otherwise, retake it now, before any agent launches, as in stage 1 step 1b: move
   the old `baseline/` files, except the stage check files of reused stages, to
   `superseded/<k>/baseline/`, create a new `baseline/marker`, and write new snapshot
   files. A fetch runs only when stage 1 reruns. A recorded approval covers only the
   commands in its `commands` list: when the planned commands for a repo and remote
   are all in one recorded list for that target, they are not asked again; otherwise
   ask once, listing the new commands, and record a new approval entry.
8. **Mark the run running.** Set the run's `state` in `runs.json` to `running`. A
   resumed run has no budget; the original invocation's budget does not carry over.
9. **Continue.** Go to the SKILL.md section for the first rerun stage and run every
   stage after it, with the same rules as an audit. When the first rerun stage is 2, 3,
   or 4, launch every stage among 2, 3, and 4 that is being rerun together; a reused
   stage 2 or 3 counts as satisfied for the barrier, and its recorded
   `output_hashes` are the final hashes. Rerun stages write new entries, each keeping
   the `superseded` list from step 6; the first rerun stage's entry also carries the
   `base_moved` map when step 3 recorded one. When stage 1 reruns, it reuses this run's
   directory, run id, `runs.json` entry, approvals, and superseded records, and only
   rewrites the stage 1 entry as `running` (stage 1, section D).
10. **Report.** Stage 8 writes a new `report.md` with a new revision line. An approval
    given to `/cca:act` against the old revision no longer matches, by design.
