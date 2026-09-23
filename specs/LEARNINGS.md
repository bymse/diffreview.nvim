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
