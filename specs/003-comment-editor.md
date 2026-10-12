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

## Editor Lifecycle and Ownership Contract

- Expose `ReviewSession:open_comment_editor()` for creation from the current owned UI context and `ReviewSession:edit_comment_by_id(id)` for existing records. Return `true` when opened/focused and `nil, error` on rejection. Existing-record editing requires an active owning review, accepts stale IDs without navigation, and rejects unknown IDs. UI ownership validation belongs to creation, not edit-by-ID.
- Allow one editor per review. A repeated request for the same target focuses it; a different request while dirty or saving is rejected, and a clean editor may be replaced. Successful writes leave the editor open and clean. The first successful addition pins its returned ID; repeated writes edit that record rather than creating duplicates. Empty new writes leave no record; empty existing writes delete and clear its pinned ID.
- Pin owning active-session identity and requested location/record when opening. File selection may change, but never retargets the draft. New text writes require the original file to be selected/presented again and its visible text to match the comparison; otherwise leave the draft unchanged with an error. Writes from obsolete owners fail. Reject selection/context changes that could race a pending write, and keep the editor unavailable for replacement while saving.
- Dirty means modified buffer contents; a newly opened empty creation editor is clean. Pending asynchronous writes also block refresh and stop. Dirty refresh and `ReviewStop` are rejected, preserving active review and draft. Clean stop closes its editor. An explicit editor close without writing is draft cancellation (native force close may be necessary for modified text). Ordinary tab closure must either be blocked by native modified-buffer protection or retain the dirty draft; forced tab closure retains it as a listed editable buffer outside the closed review, detached from persistence, until explicit user cancellation. Never force-delete dirty draft text in cleanup. Any detached draft write returns an ownership error.
- Before creating a text anchor, compare the actual owned displayed buffer lines with the immutable comparison snapshot as well as disk fingerprint consistency. Unsaved displayed worktree edits, unrelated windows, replaced buffers in owned windows, and information views cannot be treated as text locations. Old-only deleted-file windows remain eligible for old-side text comments; presented non-text views create file notes.
- Add focused lifecycle functional coverage separately if needed: dirty stop/ordinary and forced tab closure, repeated writes, second editor requests, pinned selection/obsolete ownership, pending-save guards, unsaved displayed worktree mismatch, old-only deletion and replaced owned-buffer rejection. Use real filesystem failures.

## Verification

- Through `ReviewStart`, file selection and `ReviewComment`, create a text comment from a cursor, a visual line range on each available side, and a file note from the file-list row or non-text view; write the buffer, stop/restart, and observe stored records at the requested locations. Through the session's existing-comment editor entry point, edit by ID and verify the saved body.
- Exercise blank new/write, blank edit/write, close without write, failed save, external worktree change after selection, unrelated quickfix/window, unsaved editor refresh, and stop/close. Confirm no partial comment record, no unintended deletion, and no silent loss of unsaved contents.
- Run `just lint`, then `just format` and `just format-check`, then `just test` (multiple affected cases).
