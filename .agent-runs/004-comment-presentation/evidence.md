# Evidence: 004-comment-presentation

## Changed Files
- `lua/diffreview/init.lua` — configured `ReviewComments` and ranged/bang `ReviewCommentAttach` commands.
- `lua/diffreview/review.lua` — comment actions, pinned pending attachment, coroutine completion, save-before-projection updates, editor guards/invalidation, navigation and refresh drawer preservation.
- `lua/diffreview/ui/init.lua` — independent comment-list ownership, drawer toggling, annotation updates and cleanup.
- `lua/diffreview/ui/quickfix.lua` — comment IDs/context/rows, list-aware native bindings, replacement validation, inactive updates and cursor preservation.
- `lua/diffreview/ui/side_by_side.lua` — owning-side navigation and comment annotation lifecycle.
- `lua/diffreview/ui/comment_decorations.lua` — separate namespace, valid text ranges, file notes, stale file-level presentation and tracked-buffer cleanup.
- `tests/integration/ui/comment_quickfix_tests.lua`, `tests/integration/ui/comment_decorations_tests.lua`, `tests/integration/init.lua`.
- `tests/functional/review_comments_test.lua`, `tests/functional/review_comment_attachment_test.lua`, `tests/functional/review_comment_management_safety_test.lua`, `tests/functional/review_comment_presentation_lifecycle_test.lua`, `tests/helpers/functional_comments.lua`, `tests/functional/init.lua`.
- `tests/functional/review_comment_attachment_overlap_test.lua` — repair 1 adds overlapping asynchronous cancellation/same-ID reselection coverage; registered in `tests/functional/init.lua`. No lasting production changes in repair 1.
- `tests/functional/comment_reconciliation_test.lua` — existing empty-comparison journey now expects the comment drawer and preserves its identity across refresh.
- `tests/functional/user_commands_test.lua` — registration coverage includes both new commands.
- `tests/functional/review_comment_editor_lifecycle_test.lua` — repair 2 makes unchanged-restart byte preservation deterministic with valid noncanonical JSON; all original detached-draft, new-tab, failed-old-owner-write and checkpoint byte-equality assertions remain.
- `specs/CONTEXT.md` — update the Codebase Map to describe implemented dual-list ownership and annotation/editor modules.
- `.agent-runs/004-comment-presentation/evidence.md`, `.agent-runs/004-comment-presentation/learnings-draft.md`.
- `specs/004-comment-presentation.md` was already modified on entry with the approved Interaction and Projection Contract; its supplied change was preserved, not rewritten.

## Tests Added Or Updated
- Three new integration tests cover independent lists, inactive updates, row replacement rejection, annotation range/status, namespace isolation and actual ReviewUi selection cleanup.
- Nine new functional tests cover native navigation/edit/delete/resolve/reopen, repeated drawer switching, stale attachment cancellation/retry/replacement, true overlapping Git reads with cancellation/same-ID reselection, conversion to a file note, refresh/source-deletion cancellation, clean pinned-editor invalidation, dirty/saving rejection, unrelated/replaced rows, checkpoint-save failure, annotation updates/tab cleanup, and comment-only refresh/restart.
- Existing reconciliation and command registration tests updated for the current contract.
- Repair 2 updates the existing force-close/detached-draft/restart journey, without relaxing any assertions or adding synchronization delays. A leading whitespace byte in the real checkpoint deterministically detects redundant serialization on restart.
- Functional tests use configured commands, native keys, real editor buffers and real Git/checkpoint fixtures; integration tests use module interfaces without editor-key simulation or internal collaborator mocks.

## Primary Journey Verification
- Discover and manage persisted comments — configured commands and `<CR>/e/d/r`; `tests/functional/review_comments_test.lua:review_comments_should_navigate_edit_toggle_and_delete_when_native_rows_are_selected` verifies file-note/main-window navigation, old-side range navigation, unchanged viewed progress, editing, resolve/reopen, deletion, stable independent IDs, one drawer, and restart persistence.
- Reattach a stale text comment — `ReviewComments`, `a`, `ReviewCommentAttach!`, ranged `ReviewCommentAttach`; `tests/functional/review_comment_attachment_test.lua:review_comment_attach_should_preserve_identity_and_retry_when_stale_source_is_pinned` verifies cancellation, failed visible-text validation followed by retry, preserved ID/body/resolution, and a new current-side range.
- Replace/cancel attachment and invalidate a clean editor — commands and native list keys; `review_comment_attach_should_replace_cancel_and_invalidate_pinned_editor_when_file_note_is_completed` verifies replacement of the source, text-to-file-note attachment, clean pinned-buffer deletion, refresh cancellation and source-deletion cancellation.
- Reject an obsolete attachment during a real asynchronous Git read — `ReviewCommentAttach`, `ReviewCommentAttach!` and native `a`; `tests/functional/review_comment_attachment_overlap_test.lua:review_comment_attach_should_reject_obsolete_completion_when_pending_source_is_canceled_or_reselected_during_git_read` runs cancellation-only and cancellation-plus-same-ID-reselection cases. It starts an attachment at line 1, verifies the checkpoint has not yet adopted it, cancels/reselects before yielding the editor event loop, then verifies unchanged checkpoint, file/comment items and both panes' annotations. A fresh completion at line 3 succeeds with the original ID/body/resolution and updates the projections without switching the drawer.
- Preserve drafts and failed saves — commands/native keys; the three tests in `review_comment_management_safety_test.lua` verify unchanged persisted state for invalid/foreign rows and dirty/saving conflicts, failed-delete projection/editor retention, then successful deletion/invalidation.
- Present annotations through writes/refresh/cleanup — editor writes, native resolve and `ReviewRefresh`/tab closure; `review_comments_should_follow_writes_refresh_and_tab_cleanup_without_editing_content` verifies body updates, resolution, stale text shown only at the file level, old-buffer cleanup and tab cleanup.
- Retain discoverability with an empty comparison — `ReviewRefresh`, `ReviewStop`, `ReviewStart HEAD`; `review_comments_should_open_from_closed_drawer_when_refresh_and_restart_have_only_saved_comments` verifies the automatically opened drawer, vanished-file navigation safety, continued editing and stable identity after restart. The updated reconciliation journey also verifies drawer-kind preservation when files return.

## Commands Run
- `git status --short && git log --oneline -3` — PASS; baseline HEAD `4c5ebbe`, only the supplied spec contract modified on entry.
- `just lint` — initial FAIL for LuaLS annotation/test typing issues; fixed. Final PASS, no problems.
- `just format` — PASS after final LuaLS checks.
- `just format-check` — PASS.
- `just test` — initial FAIL for outdated comment-only expectations and native drawer cursor reset; fixed. A subsequent run timed out after a test rejected a command without catching its expected error, cascading into later fixtures; fixed. Another completed run exposed the existing alphabetical setup-test ordering requirement; new functional names adjusted to the review-command interface. Pre-repair PASS: 50 unit, 200 integration, 86 functional. Repair 1 final PASS: 50 unit, 200 integration, 87 functional.
- `just test-integration update_review_comments_should_preserve_active_files_when_comments_are_inactive` — PASS.
- `just test-functional review_comments_should_navigate_edit_toggle_and_delete_when_native_rows_are_selected` — initial FAIL while fixing drawer cursor preservation; final targeted PASS.
- `just test-functional review_comment_attach_should_preserve_identity_and_retry_when_stale_source_is_pinned` — PASS.
- `just test-functional review_comment_attach_should_replace_cancel_and_invalidate_pinned_editor_when_file_note_is_completed` — PASS.
- Targeted functional safety/lifecycle runs under their initial `comment_management_*`, `comment_keys_*` and `comment_annotations_*` names — PASS; final names use `review_comments_*`, and all pass in the full suite.
- `just test-functional review_comments_should_open_from_closed_drawer_when_refresh_and_restart_have_only_saved_comments` — PASS.
- Final `just lint && just format && just format-check && just test && git diff --check` — PASS in required order.
- `git diff --check` and `git status --short && git diff --numstat` — PASS.
- Repair 1: `just test-functional review_comment_attach_should_reject_obsolete_completion_when_pending_source_is_canceled_or_reselected_during_git_read` — PASS with the real token-identity guard.
- Repair 1 mutation probe: the same targeted command with the pending-source check temporarily weakened to compare only comment IDs — intentional FAIL in the same-ID-reselection case: the obsolete line-1 completion modified the checkpoint. This proves the regression specifically needs token identity rather than merely comment ID. The original production guard was immediately restored; no mocks or API/notification interception were used.
- Repair 1 final `just lint && just format && just format-check && just test && git diff --check` — PASS in required order; LuaLS reports no issues, all 337 tests pass.
- Repair 2 investigation: ten isolated runs of `just test-functional review_comment_should_detach_draft_and_reject_old_owner_when_tab_is_force_closed_and_review_restarts` and four `just test-functional` runs initially passed. A further repeated targeted run reproduced the reported failure on its fifth invocation with temporary diagnostic assertions: decoded before/after checkpoint state was equal, but JSON object field ordering differed. The new tab and detached buffer assertions passed. Diagnostic assertions were removed after diagnosis.
- Repair 2 deterministic regression: `just test-functional review_comment_should_detach_draft_and_reject_old_owner_when_tab_is_force_closed_and_review_restarts` with the valid whitespace-prefixed checkpoint — FAIL before the production repair, PASS in ten consecutive runs afterward.
- Repair 2 final `just lint && just format && just format-check && just test && git diff --check` — PASS in required order; 50 unit, 200 integration, 87 functional tests, zero failures.

## Results
- Final suite after repair 2: 337 tests passed, zero failed (50 unit, 200 integration, 87 functional). LuaLS, formatting and whitespace gates passed. Negative fixtures intentionally emit rejected-save/context diagnostics.
- Static tool inspection verified both command registrations, range/bang handling, pending-source lifecycle, shared mutation projection updates, distinct comment contexts and namespaces. No services, new dependencies or commits.

## Spec Compliance Notes
- Implemented only spec 004, including its approved Interaction and Projection Contract and supplied gap-review PASS. No future-spec features, storage schema changes, publishing/export, automatic refresh or inline-mode support.
- Comment mappings validate owned ID/context, owning tab/window, presented item contents and native list changedtick before invoking session actions. Inactive updates preserve the current list and drawer cursor; toggling explicitly switches the one drawer.
- The shared mutation boundary rejects dirty/saving management, preserves failed-save projections, and updates both lists/annotations only after checkpoint adoption. Editor writes use that same boundary with explicit write authorization; successful external delete/reattach invalidates a clean editor pinned to the record.
- Pending attachment uses an identity token as well as record ID so cancellation/replacement during an asynchronous completion cannot adopt an obsolete request. Snapshot, comparison, progress and selection currency remain checked by existing mutation validation.
- Repair 1 supplies an observable overlapping regression for that token check and an ID-only mutation probe that fails specifically when the same source ID is selected again. Production remains unchanged; independent verification/judge reassessment is separate from this implementer evidence.
- Repair 2 diagnosis: this was neither a detached-editor ownership defect nor a synchronization race. Startup unconditionally saved unchanged reconciled progress, and Lua table/JSON object ordering occasionally changed its bytes. `ReviewSession:start` now avoids a redundant save when the loaded checkpoint and reconciled state are deeply equal. Changed/new states still save before UI adoption; editor ownership and cleanup logic are untouched. This preserves the original strict checkpoint assertions rather than substituting decoded-state equality.
- Annotations track and clear every prior buffer independently of diff decorations. Stale text is never rendered at its stored obsolete range.

## Risks Or Follow-ups
- Native quickfix history remains global, as required. External list replacement invalidates bindings; explicit presentation can reacquire an owned list without changing foreign items.
- Verification used the repository's isolated headless Neovim/Git fixtures on Linux; no separate interactive TUI smoke test was run. No known outstanding gate failures or newly accepted implementation ceilings.
- Repair 2 read `independent-verification.md`; its links target summary headings only, and it explicitly states that full command output is not a repository artifact. Local reproduction supplied the before/after JSON evidence. The independent report was not rewritten, and independent re-verification remains separate.
