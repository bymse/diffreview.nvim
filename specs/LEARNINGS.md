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
Use in future specs: Preserve `ReviewUi.quickfix_id` and `quickfix_context` as the lifecycle cleanup seam.
Source: Spec 003 cleanup integration verification.
