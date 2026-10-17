# Implementation Learnings

Durable discoveries from completed implementation phases are recorded here.

## 2026-10-17 — Comment target identity and source content

Finding: Explicit-side IDs are SHA-256 of the JSON tuple `{ file_id, side, line_start or 0, line_end or 0 }`; omitted sides use JSON null in that tuple while remaining absent in returned targets. The existing side validator enforces operation-aware availability and content validity.

Impact: Side-less whole-file support reuses validation and lifecycle behavior without weakening explicit-side contracts.

Use in future specs: Keep UI targets detached and preserve original target coordinates. Default selected worktree views are path-backed; collection line targets still require snapshots (`load_selected_view(loaded, id, nil, true)`). The UI may use actual displayed path-backed lines without changing that model contract. Malformed typed test inputs can be assigned to inferred local fixture tables for LuaLS-compatible negative tests.

Source: `.agent-runs/001/learnings-draft.md`; spec 001 implementation and judge review.

## 2026-10-17 — Presentation ownership and editor-test boundaries

Finding: Pane association captures actual window/buffer/side identities. Deleted files put old source in main, rename-only views may hide old, and information views have no source side. Logical snapshot counts differ from the artificial empty-buffer row; path-backed counts come from displayed source lines. Source bounds should be computed once per pane.

Impact: Projection and future editor validation must use captured actual panes, not infer displayed sides from the diff model. Group virtual lines by anchor to preserve supplied order. TabClosed resource cleanup must precede caller notification independently of whether the handler invokes cleanup.

Use in future specs: `display_diff_side_by_side` accepts optional fourth file ID, refresh optional third; omission resets association. `clear_comments` preserves association while presentation transitions invalidate it. Editor drafts must remain captured across those transitions and must not redraw projections automatically or save stale-clamped coordinates. Native editor-command journeys belong in functional tests; integration tests use facade methods. Establish owned resources before cleanup assertions to avoid vacuous tests.

Source: `.agent-runs/002/learnings-draft.md`; spec 002 judge repair and independent verification.

## 2026-10-17 — Native comment-editor lifecycle

Finding: A writable acwrite split can hide modified content on ordinary quit when global hiding is enabled. A temporary buffer-local unload policy at QuitPre requests native modified-buffer protection; restoring it at BufLeave preserves immediate non-discarding hiding after a rejected quit. BufWinLeave is too late. Actual native unload remains distinct from retained modified hiding and releases discarded resources.

Impact: Native write errors must propagate from BufWriteCmd to abort write-quit. Clean native close cleanup is deferred until Neovim finishes closing; explicit API close and teardown discard synchronously. No global option changes are required.

Use in future specs: Preserve the quit/immediate-hide/reopen/forced-quit regression and pinned-editor verification. Same-target reuse precedes replacement-payload and presentation checks. Check both historical window ownership and the currently displayed buffer during source-window recovery; a comment-editor buffer never becomes a source pane. Reuse `comment_decorations.source_line_count` for displayed-source validation, and keep save handlers per request with explicit projection refresh.

Source: `.agent-runs/003/learnings-draft.md`, delegated native event traces, final 335-test verification and judge review.
