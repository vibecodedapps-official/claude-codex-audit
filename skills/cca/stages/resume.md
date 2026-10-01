# Resume

`/cca:resume <run-id> [--from <stage>]` reruns an audit from a stage, reusing only
artifacts whose inputs have not changed. It never reuses a stale stage and never loses
a finished one.

## Steps

1. **Find the run.** Read `${CLAUDE_PLUGIN_DATA}/runs.json` and take the entry whose
   `run_id` is the invocation's `run-id`. When there is none, or its `path` no longer
   exists, stop with one line saying so. The run directory is that `path`.
2. **Recover state.** Read, in the run directory, `manifest.json`, `stages.json`,
   `audit-brief.md`, and `common.md`. Every approval in `stages.json` `approvals`
   stands: do not ask for it again. A stage whose status is `running` counts as
   incomplete, since its agents belonged to an earlier session; it is rerun, and
   nothing waits for its old agents.
3. **Head sha check.** For each bundle, resolve its head as stage 1 did (a GitHub PR's
   `headRefOid` from `gh pr view`, else the sha its `branch` resolves to) and compare
   it with the head sha stage 1 recorded in `audit-brief.md`. If any bundle's head sha
   has changed, stop and ask whether to restart from stage 1, showing each bundle's
   recorded and current sha. On yes, the first stage to rerun is 1. On no, stop and
   change nothing.
4. **Recompute input hashes.** For each stage entry, recompute every input it records,
   the same way it was recorded:
   - stage 1: the manifest (the file named in `manifest.json`'s `source` key, merged
     again with the recorded prompt inputs and flags and normalized, then compared with
     `manifest.json`), each claims file, the questions file, the content hash of
     every `file:` ticket or PR export, and `plugin_version`;
   - each bundle's head, base, and merge-base sha and the pinned sha of every
     reference and source of truth, by resolving each again as stage 1 did; a changed
     one invalidates stage 1;
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
   A `not_applicable` stage whose inputs have not changed is reused. When nothing
   needs a rerun and no `--from` was given, say the run is current, print its report
   path and terminal state, and stop.
6. **Supersede.** Every stage from the first rerun stage through stage 8 is rerun. For
   each of those stages that has an entry, in order:
   1. Move each of its outputs that exists to `superseded/<k>/<path>`, where `<k>` is
      one more than the highest number already under `superseded/`, keeping the
      run-relative path (so `ledger/5.md` goes to `superseded/<k>/ledger/5.md`).
      Stage 5's outputs include `ledger/5.md`, stage 6's `ledger/6.md`, and stage 7's
      `ledger/7.md`, each with its stage.
   2. Rewrite its entry with status `superseded` and, in its `superseded` list, one
      record per moved output: `path`, `moved_to`, and `time`.
   Stages before the first rerun stage keep their entries and outputs unchanged and
   are reused as they are.
7. **Baseline.** When the first rerun stage is 1, stage 1 takes the baseline again. Otherwise, retake it now, before
   any agent launches, as in stage 1 step 1b: move the old `baseline/` files, except
   the stage check files of reused stages, to `superseded/<k>/baseline/`, create a new
   `baseline/marker`, and write new snapshot files. A fetch runs only when stage 1
   reruns: an approval recorded in `stages.json` is not asked again, and a fetch with
   no recorded approval is asked once.
8. **Mark the run running.** Set the run's `state` in `runs.json` to `running`. A
   resumed run has no budget; the original invocation's budget does not carry over.
9. **Continue.** Go to the SKILL.md section for the first rerun stage and run every
   stage after it, with the same rules as an audit. When the first rerun stage is 2, 3,
   or 4, launch every stage among 2, 3, and 4 that is being rerun together; a reused
   stage 2 or 3 counts as satisfied for the barrier, and its recorded
   `output_hashes` are the final hashes. Rerun stages write new entries, each keeping
   the `superseded` list from step 6. When stage 1 reruns, it reuses this run's
   directory, run id, `runs.json` entry, approvals, and superseded records, and only
   rewrites the stage 1 entry as `running` (stage 1, section D).
10. **Report.** Stage 8 writes a new `report.md` with a new revision line. An approval
    given to `/cca:act` against the old revision no longer matches, by design.
