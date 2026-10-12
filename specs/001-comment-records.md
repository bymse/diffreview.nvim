# Spec 001: Durable Comment Records

## Goal

Provide validated, durable local comment records and persistence-backed comment management through a review-session interface, without any new editor UI.

## Prerequisites

None.

## Context

Read `specs/CONTEXT.md` for approved behavior, storage identity, file identity, compatibility assumptions, and test conventions. This is the first part of the plan's durable-state phase.

## Tasks

- Create `lua/diffreview/comments.lua` as the domain boundary for creation, editing, deletion, explicit resolve/reopen, reattachment, validation of requested locations, and text-anchor capture. Public operations must return success or a recoverable error without mutating persisted state on failure. A single-line anchor is a range of length one; capture the selected lines and immediate available neighbor text so later exact matching can distinguish repeated content.
- Extend `ReviewProgress` in `lua/diffreview/review_progress.lua` with `comments: ReviewComment[]`. Pin `ReviewComment` to `id: string` (stable unique local identity), `file_id: string` (collector identity), `display_path: string` (last known path for browsing), `body: string`, `resolved: boolean`, `stale: boolean`, `side: 'old'|'current'|nil` (nil for a file note), `start_line: integer|nil`, `end_line: integer|nil` (1-based inclusive, nil for a file note), `anchor_lines: string[]|nil`, `context_before: string|nil`, and `context_after: string|nil`. A file note has no side or line anchor; a text note has a present side, positive ordered bounds, and matching anchor lines. Carry previous comments unchanged through file-progress reconciliation until spec 002 adds content matching. Persist comments in the same checkpoint as file progress; do not add provider or publication fields.
- Modify `lua/diffreview/storage.lua` (`load`, `save`) to validate the new version and every comment record, including unique IDs, nonblank bodies, text/file-note shape, boolean flags, line bounds and captured context. Keep `path` and atomic replacement behavior. Old checkpoint versions are unsupported without migration; invalid or corrupted state must not be overwritten on load or partial save.
- Modify `lua/diffreview/review.lua` (`ReviewSession` state and progress mutation path) to expose session-level operations for comment add/edit/delete/resolve/reopen/reattach by ID and review location. These operations must validate the active review, file identity and supported side, use comparison content for a text location, save a candidate before adopting it, and leave viewed-file progress intact. Reattachment keeps the original ID/body/resolution status and replaces the location and captured context. Avoid UI-internal assumptions in the operations so integration tests can exercise them through the session/module interface.
- Update existing checkpoint assertions/fixtures in `tests/integration/storage_tests.lua` and `tests/integration/review_progress_tests.lua` for the new schema. Add focused real-repository behavior coverage in `tests/integration/comment_state_tests.lua` and register it in `tests/integration/init.lua`. Use existing Git and review helpers; test ordinary and edge-case operations without intercepting editor APIs or notifications.

## API and Validation Contract

- Expose session methods `add_comment(location, body)`, `edit_comment(id, body)`, `delete_comment(id)`, `resolve_comment(id)`, `reopen_comment(id)`, and `reattach_comment(id, location)`. Return the resulting comment (or `true` for deletion) on success and `nil, error` on failure; additions return a record containing the new ID. Unknown IDs and inactive sessions fail without changes. Reject empty or whitespace-only bodies; editor empty-write behavior belongs to spec 003.
- A location contains `file_id` and optionally `side`, `start_line`, and `end_line`. Text locations require the currently selected/presented comparison file; file-note locations may reference any current changed-file entry, supporting file-drawer selection. Spec 003 enforces actual window/row ownership at the UI boundary. Public module interfaces may select files directly for integration coverage.
- Use checkpoint version 2. New records start with `resolved = false` and `stale = false`. Reattachment may change file, side, or text/file-note kind, preserves ID/body/resolution, and clears staleness on success.
- Text records require a string array whose length equals the inclusive line range; neighboring context is optional string data, captured when the immediate neighbor exists. File notes omit side, bounds, anchor lines, and both context fields. Validate the same schema before saving and after loading.
- Capture comparison text using the existing selected-content fingerprint consistency checks or an equivalent immutable snapshot. Reject worktree changes that invalidate the active comparison. Reject mutations during pending selection/refresh; after asynchronous content loading, revalidate session identity, selected file, and operation validity before saving. Stop or cancellation during loading must leave active and persisted state unchanged.
- This phase carries stored comments unchanged through refresh/restart. Matching, stale reconciliation, and comment-only startup belong to spec 002.

## Verification

- Through the public review-session/module interface in a real temporary Git repository, add an old-side or current-side text comment and a file note, change a body, resolve/reopen, reattach, and delete; stop/restart and load state to confirm stable IDs, bodies, locations and viewed progress are preserved, and deleted records stay absent.
- Exercise invalid sides or line bounds, absent file identities, empty new body, duplicate/corrupted IDs, malformed text/file-note records and storage write failures. Confirm no active or saved state changes after a rejected operation and no invalid checkpoint is replaced.
- Cover consecutive ranges, both sides and unchanged lines, unknown IDs, inactive/canceled sessions, initial flags and reattachment clearing stale state. Modify worktree content between comparison loading and mutation and verify rejection preserves the checkpoint. Saving an invalid candidate must preserve an existing valid checkpoint.
- Run `just lint`, then `just format` and `just format-check`, then `just test` (multiple affected cases). Follow the repository's real-Git fixture and test naming rules.
