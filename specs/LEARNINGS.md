# Implementation Learnings

## 2026-09-23 — Lightweight Git review loading

Finding: `GitRepo:diff(from, nil)` produces one baseline-to-working-state diff containing staged and unstaged tracked changes without double-counting paths.
Impact: Working-state loading does not need separate index and worktree diff aggregation.
Use in future specs: Reuse the retained `GitDiff` record rather than issuing additional tracked-file diff commands.
Source: Spec 001 implementation and integration verification.

## 2026-09-23 — Transient untracked summaries

Finding: `git diff --no-index --numstat -z /dev/null <path>` provides Git-compatible text counts and binary detection for untracked files without retaining their contents.
Impact: Startup can expose accurate lightweight summaries while preserving the lazy-loading boundary.
Use in future specs: Keep untracked content inspection transient and use the retained path and binary metadata for later loading.
Source: Spec 001 implementation and integration verification.

## 2026-09-23 — Git operation fixtures

Finding: Git copy detection requires a tracked destination and a suitable changed source, while a staged regular-file-to-symlink transition reliably produces a type-change status.
Impact: Summary tests can silently cover the wrong operation when they assert only normalized output.
Use in future specs: Assert retained raw Git statuses whenever operation categories share summary behavior.
Source: Spec 001 quality review repair.

## 2026-09-23 — Shared model location

Finding: Shared diff view-model aliases now live at `diffreview.diff_view_model`; the former UI module path was intentionally removed.
Impact: UI and orchestration modules must import or reference the shared top-level model contract.
Use in future specs: Do not restore `diffreview.ui.diff_view_model` or add a compatibility shim.
Source: Spec 001 model relocation.

## 2026-09-23 — Quickfix ownership identity

Finding: Neovim retains the supplied quickfix context when an existing list is updated by stable ID.
Impact: A `ReviewUi` instance can own and update one projection without exposing the global quickfix identity to callers.
Use in future specs: Validate `ReviewUi.quickfix_id` against the exact stored instance context before cleanup or update; never infer ownership from the current list.
Source: Spec 002 implementation and integration verification.

## 2026-09-23 — Transactional quickfix rollback

Finding: Quickfix history lists share display state, while stable before-and-after window ID sets reliably identify a current-tab window introduced by a failed `copen`.
Impact: Restoring the selected list before identifying the new window can hide that window and leak it after failure.
Use in future specs: Derive rollback ownership from stable resource identities, not from globally selected quickfix state after restoration.
Source: Spec 003 implementation and quality-review repair.

## 2026-09-23 — Quickfix ownership validation

Finding: Safe cleanup requires both a stable list ID and exact ownership-context equality; titles, history positions, and shared quickfix buffers are insufficient identifiers.
Impact: Missing, stale, already-cleaned, and foreign identities can remain safe no-ops without disturbing unrelated editor state.
Use in future specs: Preserve `ReviewUi.quickfix_id` and derive the ownership context from top-level `ReviewUi.instance_id`; do not store duplicate context state.
Source: Spec 003 cleanup integration verification.

## 2026-09-23 — Cancellable review lifecycle

Finding: Marking an async operation canceled before process termination and checking operation identity at lifecycle commit points prevents late callbacks from reactivating stopped work.
Impact: Cancellation can remain independent of validated diff options while propagating consistently through Git and loader results.
Use in future specs: Retain the operation on `ReviewSession`, pass it only to orchestration-level loaders, map cancellation without diagnostic detail, and guard every UI creation or active-state commit.
Source: Spec 004 implementation and cancellation integration tests.

## 2026-09-23 — Async completion guards

Finding: `async.system` must mark completion before scheduling its coroutine continuation so duplicate process callbacks cannot resume one operation twice.
Impact: Process termination races and repeated callbacks cannot duplicate lifecycle side effects.
Use in future specs: Test callback idempotence explicitly whenever coroutine resumption depends on external callbacks.
Source: Spec 004 final quality-review repair.

## 2026-09-23 — Transactional public setup

Finding: Multi-command setup must retain its configuration marker only after every command registers and remove only commands acquired by a failed attempt.
Impact: Registration failure does not consume setup or leak a partial public interface.
Use in future specs: Treat public initialization as a transaction and verify retryability after each acquisition failure.
Source: Spec 004 implementation and integration verification.

## 2026-09-23 — Stateful lifecycle tests

Finding: Real lifecycle tests can use a temporary repository and real `ReviewUi`; only genuinely suspended process scheduling needs a narrow fake.
Impact: End-to-end resource ownership is proven without broad mocks, while teardown prevents state leakage between tests.
Use in future specs: Use unconditional teardown for active reviews, quickfix windows, temporary buffers, and patched globals, and regenerate evidence after test renames.
Source: Spec 004 quality-review repairs.

## 2026-09-23 — Review follow-up: loader-level cancellation

Finding: Cancellation can be checked between loader steps without coupling `async.system` or the Git adapter to operation state.
Impact: In-flight commands finish normally, while revision resolution, untracked-file inspection, and lifecycle commit boundaries prevent canceled work from progressing or becoming active.
Use in future specs: Keep system execution cancellation-agnostic and pass cancellation state only to orchestration-level loaders.
Source: Review comment follow-up after Spec 004.

## 2026-09-23 — Explicit review sessions

Finding: Review lifecycle state is clearer when `review.new(config)` returns a session that owns its configuration and `idle`, `starting`, or `active` state.
Impact: Commands and the public API stop a specific session, tests avoid module-global teardown, and future independent sessions have an explicit boundary.
Use in future specs: Add lifecycle behavior to `ReviewSession`; keep `init.lua` limited to setup, command adaptation, and delegation.
Source: Branch review follow-up.

## 2026-09-23 — Shared UI instance identity

Finding: The ownership identity is a property of the whole `ReviewUi`, not of its side-by-side component.
Impact: Quickfix and side-by-side resources share `ReviewUi.instance_id` without one component depending on another component's state.
Use in future specs: Keep `instance_id` at the `ReviewUi` boundary and pass it into resource-specific modules.
Source: Branch review follow-up.

## 2026-09-23 — Quickfix-owned context orchestration

Finding: A simple `diffreview:files:<instance_id>` string is sufficient for exact quickfix ownership checks and can be rebuilt whenever needed.
Impact: `ReviewUi` stores only the quickfix ID, while the quickfix module validates stale or foreign IDs and creates replacements internally.
Use in future specs: Keep quickfix ID validation, context construction, update, and cleanup inside `ui.quickfix`.
Source: Branch review follow-up.

## 2026-09-23 — Deliberately non-transactional quickfix display

Finding: Full quickfix list, selection, and window rollback adds substantial machinery for rare `copen` or history-selection failures.
Impact: Display now propagates failures directly and may leave changed quickfix UI state, while normal cleanup remains ownership-safe.
Use in future specs: Do not restore transactional rollback unless a concrete failure mode justifies the complexity.
Source: Branch review follow-up.

## 2026-09-23 — Bounded command arguments

Finding: Neovim command `nargs` cannot express zero-to-two arguments, so `ReviewStart` must use `nargs = '*'` and reject more than two arguments in its callback.
Impact: Invalid command arity is rejected before lifecycle loading instead of being encoded as malformed review options.
Use in future specs: Keep command-line arity validation in the command adapter and domain option validation in the session or loader.
Source: Branch review follow-up.
