# Context: Minimal Review Orchestration

## Issue Summary

Diffreview already has asynchronous Git execution, raw diff parsing, quickfix rendering, and side-by-side UI primitives, but no implemented flow connects them. The plugin currently emits a hello notification at load time; `diffs.load_review` is empty; no public setup, review lifecycle, or commands exist; and quickfix ownership remains with callers. The missing orchestration prevents users from starting and stopping a lightweight review without eagerly loading every file snapshot.

## Final Goal

After one explicit `require('diffreview').setup({ layout, view })` call, users can run `:ReviewStart [from] [to]` to resolve the approved Git comparison, load only changed-file summaries, and open an owned quickfix projection. `:ReviewStop` cancels an in-progress start or cleans the active UI without disturbing unrelated editor state. The public Lua start interface additionally accepts an explicit repository path. Full diff loading, file activation, reviewed-state persistence, comments, refresh, and publishing remain deferred.

## Key Design Decisions

- `diffreview.diffs` remains the deep Git-to-model module. It resolves revision policy, aggregates tracked and applicable untracked changes, creates stable lightweight summaries, and retains private Git metadata for future lazy loading without constructing or retaining full snapshots now.
- Shared `ChangedFileViewModel` and `DiffViewModel` definitions move from `diffreview.ui.diff_view_model` to `diffreview.diff_view_model`; existing UI modules continue to consume those types directly, with no mapper module.
- Stable changed-file IDs are `stored:<old-path>` when baseline content exists and `new:<new-path>` for added, copied, or untracked files. They are independent of Git object IDs and are the future seam for quickfix lookup, reviewed state, and comments.
- Zero revisions use the merge-base of `HEAD` and the default branch discovered through `origin/HEAD`; one local or remote branch uses its merge-base with `HEAD`; one tag or hash uses its exact commit; both forms compare through the current tracked and untracked working state. Two revisions resolve exact commit endpoints and exclude worktree and untracked changes. Missing defaults and unresolved revisions fail clearly rather than guessing.
- `review.lua` owns the singleton `idle`, `starting`, and `active` lifecycle, asynchronous orchestration, cancellation, rollback, and user notifications. A second start is rejected while starting or active. Stop invalidates in-flight loading, suppresses its eventual completion, or cleans the active UI.
- `init.lua` is the thin public and command interface. Setup is explicit and single-use, accepts top-level `layout` and `view`, defaults to `horizontal` and `side_by_side`, and rejects every later call. Commands are registered only by successful setup.
- `ReviewUi` owns its quickfix list identity and context. Cleanup is idempotent because rollback and partial resource acquisition require repeated disposal to be safe, even though setup and review start are not idempotent.
- An empty comparison is successful Git loading but does not create an active review; it produces a user notification and leaves the lifecycle idle.
- No external dependencies are added. Cancellation is checked between top-level loading steps, while operation invalidation prevents late callbacks from committing obsolete state.

## Codebase Map

- `PLAN.md` — source-of-truth outcomes, boundaries, phases, and proof obligations; its status must be Approved before implementation begins.
- `plugin/diffreview.lua` — runtime load guard; it requires the public module but must not register commands automatically.
- `lua/diffreview/init.lua` — current hello placeholder; becomes the explicit setup and public start/stop interface plus command argument adapter.
- `lua/diffreview/config.lua` — current top-level layout/view annotations; becomes the normalized setup configuration contract.
- `lua/diffreview/review.lua` — new lifecycle and orchestration module introduced in the final phase.
- `lua/diffreview/async.lua` — coroutine wrapper around `vim.system` plus lightweight operation flags; system execution remains independent of cancellation and guards against duplicate callback resumes.
- `lua/diffreview/diffs/init.lua` — empty `load_review` placeholder; becomes the lightweight review loader and owner of retained Git metadata.
- `lua/diffreview/diffs/git.lua` — Git repository adapter for revision resolution, diff collection, untracked discovery, metadata, and blob loading; extended for branch classification, merge-base, and summary inspection while remaining independent of cancellation.
- `lua/diffreview/diffs/parsers.lua` — validated Git wire-format parsers and the existing `GitDiff` record carrying paths, modes, object IDs, status, counts, and binary state.
- `lua/diffreview/diffs/status.lua` and `lua/diffreview/file_mode.lua` — validated Git statuses and file modes reused by summary normalization.
- `lua/diffreview/ui/diff_view_model.lua` — current shared type location; moved to `lua/diffreview/diff_view_model.lua` without implementing full-model loading.
- `lua/diffreview/ui/init.lua` — `ReviewUi` facade and side-by-side state owner; extended to own quickfix identity and invoke quickfix cleanup.
- `lua/diffreview/ui/quickfix.lua` — converts `ChangedFileViewModel` records into quickfix entries, selects the owned list, and opens the drawer; extended with instance context and safe cleanup.
- `lua/diffreview/ui/side_by_side.lua` — existing idempotent cleanup model for owned tabs, windows, and buffers.
- `tests/helpers/git_repo.lua` — temporary Git repository fixture and deterministic commit/branch helpers used by integration coverage.
- `tests/integration/init.lua` — registry for Git, diffs, UI, and review integration tests.
- `tests/integration/ui/quickfix_tests.lua` — current quickfix projection and list-history coverage, extended for ownership and cleanup.
- `tests/functional/plugin_test.lua` and `tests/functional/init.lua` — plugin-load and public command coverage; hello behavior is removed.
- `tests/run.lua`, `tests/minimal_init.lua`, and `justfile` — coroutine-aware isolated test harness and required lint, format, and test gates.
