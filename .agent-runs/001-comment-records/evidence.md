# Evidence: 001-comment-records

## Changed Files
- `lua/diffreview/comments.lua` — comment types, location/schema validation, detached candidate mutations, IDs and exact anchor/context capture.
- `lua/diffreview/review.lua` — six session methods, snapshot/fingerprint checks, asynchronous validity guards and save-before-adopt behavior.
- `lua/diffreview/review_progress.lua` — version 2 and unchanged comment carry-forward.
- `lua/diffreview/storage.lua` — shared load/save validation before filesystem writes, recoverable directory/encoding failures; existing path and atomic replacement retained.
- `tests/integration/comment_state_tests.lua` — nine real-Git session tests.
- `tests/integration/storage_tests.lua` — version-2 fixture and malformed comment load/save coverage.
- `tests/integration/review_progress_tests.lua` — version/default-comments assertion.
- `tests/integration/init.lua` — new suite registration.
- `.agent-runs/001-comment-records/evidence.md` and `.agent-runs/001-comment-records/learnings-draft.md` — required reports.
- Pre-existing changes to the spec contract and orchestration artifacts were preserved, not authored by this implementation. No commit was created.

## Tests Added Or Updated
- `add_comment_should_persist_management_and_viewed_progress_when_review_restarts` covers both sides, consecutive ranges, unchanged lines, neighbor boundaries, default flags, distinct/stable IDs, detached return records, editing, resolving/reopening, reattachment, deletion, refresh and restart.
- `comment_mutations_should_preserve_checkpoint_when_request_is_invalid` covers invalid/missing file locations, side/bounds, unselected text, blank bodies, unknown IDs, canceled/inactive sessions and unchanged checkpoints.
- `add_comment_should_reject_changed_worktree_and_pending_operations_without_saving` covers fingerprint mismatch and pending selection/refresh rejection.
- `add_comment_should_preserve_checkpoint_when_stop_interrupts_content_loading` covers real asynchronous cancellation.
- `comment_mutations_should_leave_active_state_when_atomic_replace_fails` covers all six mutations against a real replacement failure.
- `reattach_comment_should_clear_staleness_and_preserve_identity_when_location_kind_changes` covers stored stale/resolved state and text/file-note transitions.
- `reattach_comment_should_reject_superseded_operation_when_content_loading_yields` covers deletion during loading and a changed selection.
- `add_comment_should_allow_only_file_notes_when_selected_side_has_no_text` covers absent and binary text sides plus successful binary file notes.
- `edit_comment_should_return_recoverable_error_when_storage_directory_is_not_a_directory` covers a real filesystem obstruction without thrown API errors or state changes.
- `save_should_preserve_valid_checkpoint_when_comment_schema_is_invalid` covers invalid lists, duplicate/corrupt IDs, bodies, flags, shapes, bounds, anchor lengths/types and context types through both load and save.
- Existing storage fixture now uses version 2 and rejects version 1; existing progress test asserts version 2 and an empty comments list.

## Primary Journey Verification
- Durable comment management — public `ReviewSession` methods in a real temporary Git repository; `tests/integration/comment_state_tests.lua:add_comment_should_persist_management_and_viewed_progress_when_review_restarts` asserts saved IDs, bodies, captured text/locations, deletion and viewed progress after restart and unchanged comment carry-forward through refresh.
- Safe reattachment — public `reattach_comment`; `reattach_comment_should_clear_staleness_and_preserve_identity_when_location_kind_changes` asserts preserved ID/body/resolution, cleared staleness and omission of text fields after conversion to a file note.
- Recoverable rejection — public session methods and `storage.load/save`; the rejection, cancellation and filesystem tests assert unchanged active records and checkpoint bytes. No editor APIs, notifications or internal collaborators are intercepted.

## Commands Run
- `git status --short && git log -1 --oneline` — PASS; baseline `269360b`, with only pre-existing spec/orchestration changes.
- `just lint` — FAIL initially; one comment/location type mismatch, fixed by expressing the type relationship.
- `just lint && just format && just format-check && just test` — PASS on the initial implementation; LuaLS clean, formatting passed, unit 50/50, integration 180/180, functional 60/60.
- `git diff --stat && git diff --check` — PASS.
- `just lint && just format && just format-check && just test` — FAIL on the next invocation at lint; formatting had moved inline casts away from the intended values, and one new wait predicate could return nil. Fixed using nearby `---@cast` style and a boolean predicate; later chained gates did not run on this invocation.
- `just lint && just format && just format-check && just test` — FAIL on the subsequent invocation at integration tests; lint/format/format-check and unit tests passed, integration 182/183. The new binary fixture could not be written through the text-only Git helper. Fixed using real libuv byte writes; functional tests did not run on this invocation.
- `just lint && just format && just format-check && just test` — PASS on the final invocation; LuaLS reports no problems across 86 files, formatting and format-check pass, unit 50/50, integration 183/183, functional 60/60 (293 total).
- `git diff --check && git status --short && git diff -- lua/diffreview/review.lua lua/diffreview/review_progress.lua lua/diffreview/storage.lua` — PASS; inspected final production changes and preserved unrelated pre-existing changes.
- `rg --count '^function ReviewSession:(add_comment|edit_comment|delete_comment|resolve_comment|reopen_comment|reattach_comment)\(' lua/diffreview/review.lua && rg --count 'version = 2' lua/diffreview/review_progress.lua && git diff --exit-code -- lua/diffreview/init.lua lua/diffreview/ui` — PASS; six session methods, one version-2 construction and no public-command/UI changes.

## Results
- All required final gates pass. LuaLS supplies the repository's static/typechecking gate; no separate build is defined or needed for these Lua changes.
- New and existing integration tests use real Git repositories and real storage/editor interfaces. Expected error notifications from existing rejection tests are printed during the suite; they are not test failures.
- Successful mutations save the complete candidate checkpoint before adoption and return detached records. Failed requests, cancellation, comparison mismatch and storage failures do not adopt candidates.

## Spec Compliance Notes
- Scope is exactly spec 001: checkpoint version 2, local fields only, session operations and persistence. No editor command, comment UI, matching/stale reconciliation, migration or comment-only startup was added.
- Text anchors use selected immutable comparison snapshots and existing fingerprint validation, not editor buffer contents. Session, selected file, pending operations, loaded comparison and progress identity are rechecked after asynchronous reads.
- File notes can target any current comparison entry. Text notes require the selected/presented file and a supported text side.
- Existing storage identity/path and atomic replacement remain unchanged. Validation is shared between loading and saving; invalid candidates are rejected before any checkpoint replacement.

## Risks Or Follow-ups
- Text-location add/reattach calls yield through the existing Git loader and must run in a coroutine, as documented on the methods. Future UI callers must follow the existing coroutine-based session pattern.
- Version 1 checkpoints are deliberately unsupported per contract. Refresh/restart deliberately retain comments without content matching until spec 002; no later-spec behavior is claimed.
- No outstanding failing gates or known spec-001 blockers remain.
