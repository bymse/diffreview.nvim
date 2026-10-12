# Evidence: 003-comment-editor

## Changed Files
- `lua/diffreview/init.lua` — range-aware `ReviewComment` registration.
- `lua/diffreview/review.lua` — public creation/edit-by-ID entry points, pinned editor ownership and comparison, session mutation delegation, pending-selection and dirty/pending refresh/stop guards, shared displayed-text validation for add/reattach.
- `lua/diffreview/ui/init.lua` — owned creation context and presented file identity.
- `lua/diffreview/ui/side_by_side.lua` — actual displayed buffer/side tracking, old-only and information-view distinction, visible-text comparison.
- `lua/diffreview/ui/comment_editor.lua` — listed temporary acwrite editor, coroutine writes, cancellation, clean/dirty lifecycle, detached ownership failures.
- `tests/functional/review_comment_editor_test.lua`, `tests/functional/review_comment_editor_lifecycle_test.lua`, `tests/functional/review_comment_editor_by_id_test.lua`, `tests/functional/init.lua`, `tests/functional/user_commands_test.lua`, `tests/integration/comment_state_tests.lua`.
- `.agent-runs/003-comment-editor/evidence.md`, `.agent-runs/003-comment-editor/learnings-draft.md`.
- `specs/003-comment-editor.md` had the user-supplied ownership contract modification before implementation; it was preserved unchanged by this implementation.

## Tests Added Or Updated
- Four command/editor journeys cover persisted cursor/current-and-old visual ranges and file-list notes, old-only deleted text and mode-only file notes, disk/display mismatch and unrelated/replaced contexts, dirty command refresh/stop and explicit cancellation.
- Ten command-driven lifecycle/context tests cover blank writes, stable IDs, delete/recreate, discard, same-target focus and clean replacement, real checkpoint replacement failure/retry, pinned selection, pending save guards, explicit pending cancellation, ordinary/forced tab closure, obsolete owners after restart, detached draft cancellation, immutable comparison lifetime, unrelated active-review tabs, and stale/remapped owned quickfix rows. These use `functional_review.with_review` with `ReviewStart`, `ReviewComment`, `ReviewFiles`, `ReviewRefresh`, `ReviewStop` and native quickfix selection; there is no internal session creation/control or session-state assertion in this suite.
- Two narrowly scoped public `edit_comment_by_id` tests in a separate suite cover known/unknown IDs, same-record focus, distinct records sharing a location, dirty replacement rejection, saved-body editing and deletion, stale/resolved preservation without navigation, and inactive-owner rejection. They seed validated persisted records, use only public session start/stop for fixture ownership, and assert editor buffers and saved checkpoints rather than session state. There is no module-driven creation, refresh, selection, or comment mutation in these tests.
- Registration and inactive-context coverage added to `user_commands_test.lua`.
- Shared mutation integration coverage proves both add and reattach reject unsaved displayed text without changing the checkpoint, then reattach succeeds after restoring the displayed comparison.

## Primary Journey Verification
- Create and persist comments — `ReviewStart`, native changed-file selection, `ReviewComment`, visual `Vj:ReviewComment`, `:write`, `ReviewStop`, restart; `review_comment_should_persist_cursor_ranges_and_file_note_when_written_and_restarted` asserts four durable records, exact sides/ranges/anchor text, and unchanged records after restart.
- Comment on deleted/non-text files — native selection, `ReviewComment`, `:write`; `review_comment_should_use_old_text_and_file_notes_when_deleted_or_nontext_is_presented` asserts old-side captured text and a file-level mode-change note.
- Repeated writes and blank deletion — `ReviewComment`, native `:write` and `:close!`; `review_comment_should_pin_id_and_delete_when_repeated_writes_and_blank_edits` asserts stable persisted ID, updated body, blank deletion, recreation with a new ID, and discarded draft edits.
- Edit existing comments — public `ReviewSession:edit_comment_by_id`; `edit_comment_by_id_should_focus_edit_and_delete_record_when_id_is_known` checks editor focus/body and persisted edits/deletion; `edit_comment_by_id_should_accept_stale_record_without_navigation_and_reject_obsolete_owner_when_stopped` checks saved body and retained stale/resolved status without navigation, then rejects an inactive owner.
- Pending save guards — `ReviewComment`, native `:write`, `ReviewRefresh`, `ReviewStop`, a second `ReviewComment` request, and native quickfix Enter selection; `review_comment_should_keep_location_and_guard_pending_save_when_selection_changes` asserts the original displayed file and pinned persisted location survive. Native `:setlocal nomodified` before the asynchronous write proves pending guards independently of the dirty flag; the test waits for the saved record, not an already-clean buffer flag, and checks that attempted refresh does not adopt an externally changed file fingerprint.
- Invalid creation context — `ReviewComment` in an unrelated tab (including a view of the owned list) and on externally truncated/reordered native owned quickfix rows; dedicated lifecycle cases assert no new buffers and byte-identical checkpoints. Restoring the valid rows then creates a file note at the expected identity.
- Preserve drafts on failure/closure — real filesystem checkpoint-directory collision and native tab/editor closure; lifecycle tests assert retained listed editable text, unchanged records, successful retry, ownership-rejected detached writes, and explicit cancellation.

## Commands Run
- `git status --short && git log -1 --oneline` — PASS; baseline `51df887`, only the supplied current spec was initially modified.
- Initial `just lint` — FAIL; three annotation/call typing issues, repaired.
- Initial `just lint && just format && just format-check && just test` — FAIL at functional tests; unit/integration passed. Native Markdown ftplugin required an unavailable parser, and expected synchronous command errors needed `pcall` in tests. Repaired without mocking APIs or installing dependencies.
- `just test-functional` — PASS after initial repairs, 68/68; a later expanded run failed on an incorrect information-view expectation and leaked test tab, both repaired; subsequent expanded run PASS, 74/74.
- Final `just lint && just format && just format-check && just test && git diff --check` — PASS, repeated after final detached-cancellation change; LuaLS reports no problems, formatting passes, 50 unit + 197 integration + 75 functional tests pass.
- `git diff --stat`, `git diff --numstat`, `git diff -- lua/diffreview/review.lua lua/diffreview/ui/init.lua lua/diffreview/ui/side_by_side.lua`, `git status --short` — PASS; reviewed intended scope and existing spec change.
- Tool content search for command registration, public editor methods, visible comparison checks, dirty/pending guards — PASS; required paths present. No spec 004 list/decorations implementation added.
- Repair pass 1 initial `just lint && just format && just format-check && just test` — FAIL at functional registration ordering after command-capable tests began configuring the plugin; LuaLS, formatting, 50 unit and 197 integration tests passed. Renamed command journeys with the repository's `review_comment_should_...` convention so the existing setup registration case runs first.
- Repair pass 1 second canonical gate run — FAIL at a pending-save assertion (plus subsequent fixture fallout); fixed the wait predicate to observe checkpoint adoption instead of an already-clean buffer flag.
- `just test-functional review_comment_should_keep_location_and_guard_pending_save_when_selection_changes` — PASS, 1/1, using real asynchronous Git reads and native selection.
- Repair pass 1 final `just lint && just format && just format-check && just test && git diff --check` — PASS; no LuaLS problems, formatting passes, 50 unit + 197 integration + 78 functional tests pass.
- Repair pass 1 tool content search for `session`, `review.new`, `.state`, `:select_file`, `:refresh`, `:open_comment_editor`, and `:add_comment` in the command lifecycle suite — PASS, no matches.

## Results
- All final canonical gates passed in required order; 325 tests pass, including 17 new functional cases and one new integration case.
- Saves reuse existing session add/edit/delete operations; the other existing resolve/reopen/reattach operations remain intact. UI code does not mutate authoritative comment records.
- Failed text loading, mismatched visible/disk content, canceled ownership, and checkpoint failures do not adopt partial records or clear draft modification state.
- Judge BLOCK repair pass 1 addressed the test-interface boundary and missing context cases; production code was unchanged during this repair. Independent judge approval remains external to this implementation evidence.

## Spec Compliance Notes
- Implements only spec 003 including its new lifecycle/ownership contract; supplied gap-review status was PASS. No separate gap-review file was present in the provided mapped inputs.
- The Codebase Map was sufficient; no structure globbing was used. Context, learnings, implementation log, repository instructions, nearby code and fixtures were read before changes.
- Creation validates actual owned windows and buffers; edit-by-ID does not require a navigation context and accepts stale records. One editor pins target and active owner; the first successful add pins ID. A creation editor cannot silently adopt a refreshed comparison.
- Ordinary tab closure may retain the dirty draft rather than block, as permitted by the contract. Forced closure retains the listed acwrite buffer and detaches it; write handlers stay solely to reject obsolete ownership until explicit cancellation.
- No dependencies, services, commits, comment quickfix list, annotations, or future-spec commands added.

## Risks Or Follow-ups
- Detached drafts are local editor buffers, not persisted recovery checkpoints; the contract protects review/tab cleanup, not process termination.
- A clean unsaved creation editor retained across refresh intentionally rejects writes against its obsolete comparison; close and reopen to target the refreshed comparison.
- Native buffer events and asynchronous Git reads remain lifecycle-sensitive; focused real-editor cancellation and closure tests cover the implemented boundaries.
