# Spec 003: Write Comments in the Review UI

## Goal

Give reviewers `ReviewComment` and a temporary editable buffer that commits local comments only on explicit write.

## Prerequisites

Specs 001 and 002 complete.

## Context

Read `specs/CONTEXT.md` for text/file locations, editor semantics, review ownership, and compatibility limits. This implements the plan's comment-writing phase.

## Tasks

- Register `ReviewComment` in `lua/diffreview/init.lua` (`setup`) with visual line range support. From the displayed side-by-side review, a range targets the highlighted consecutive lines and a cursor targets one line on that window's old/current side; from a selected changed-file quickfix row, target that file; from a presented non-text view, target its file. Reject unrelated quickfix lists, windows, tabs, stale selections and unpresented content without creating an editor.
- Extend `lua/diffreview/review.lua` (`ReviewSession`, `select_file`, `start`, `refresh`, `stop`) and `lua/diffreview/ui/init.lua` (`ReviewUi`, presentation callbacks/context) to mediate creation and editing through the session comment operations, not by changing structured state in UI code. Provide a session entry point to open an existing comment by ID for editing; spec 004 connects the list action to it. Expose enough owned-buffer/side information from `lua/diffreview/ui/side_by_side.lua` to distinguish the actual current/old review window, an old-only deleted-file view, and non-text information buffers. Verify the selected worktree content still corresponds to the review comparison before committing a new or reattached text anchor; reject a changed snapshot rather than saving a misleading location.
- Create `lua/diffreview/ui/comment_editor.lua` for a plugin-owned temporary editable buffer in the review tab. A buffer write commits the current contents; closing without writing discards draft edits; writing blank text for an existing comment deletes it, while a blank new comment creates nothing. A failed save leaves the draft open and stored state unchanged. Manual `ReviewRefresh` must reject an unsaved editor; review stop or tab closure must not silently discard its unsaved changes. Clean up editor buffer and handlers with the owning review.
- Add focused command/editor journeys in `tests/functional/review_comment_editor_test.lua` and register in `tests/functional/init.lua`; extend `tests/functional/user_commands_test.lua` only for command registration/invalid context. Use `tests/helpers/functional_review.lua` and real editor/Git fixtures. Add integration coverage for session/UI context only if behavior can be observed through module interfaces without simulated keys.

## Verification

- Through `ReviewStart`, file selection and `ReviewComment`, create a text comment from a cursor, a visual line range on each available side, and a file note from the file-list row or non-text view; write the buffer, stop/restart, and observe stored records at the requested locations. Through the session's existing-comment editor entry point, edit by ID and verify the saved body.
- Exercise blank new/write, blank edit/write, close without write, failed save, external worktree change after selection, unrelated quickfix/window, unsaved editor refresh, and stop/close. Confirm no partial comment record, no unintended deletion, and no silent loss of unsaved contents.
- Run `just lint`, then `just format` and `just format-check`, then `just test` (multiple affected cases).
