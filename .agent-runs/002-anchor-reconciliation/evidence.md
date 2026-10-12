# Evidence: 002-anchor-reconciliation

## Changed Files
- `lua/diffreview/comments.lua` — detached exact-range/context reconciliation, including stale records and file notes.
- `lua/diffreview/review_progress.lua` — reconcile comments alongside the unchanged viewed-file rules.
- `lua/diffreview/review.lua` — load and validate all commented-file snapshots before save/adoption; reuse snapshots for selection; coroutine-safe preloaded refresh; comment-only startup.
- `lua/diffreview/diffs/content.lua` and `lua/diffreview/diffs/init.lua` — distinguish successfully identified unsupported submodule content from supported-side read failures during snapshot loading.
- `lua/diffreview/diffs/fingerprint.lua` — fingerprint submodules using collector Gitlink metadata instead of trying to read a directory as file bytes.
- `lua/diffreview/ui/side_by_side.lua` — preserve the owned main window before deleting displayed snapshots during selected-view clearing (judge repair pass 2).
- `tests/integration/comment_reconciliation_tests.lua` — thirteen real-repository session tests, including supported-side Git blob failure in a submodule-associated candidate.
- `tests/integration/init.lua` — register the new suite.
- `tests/integration/review_refresh_tests.lua` — wait for preloaded refresh completion before checking rejected-selection behavior.
- `tests/functional/comment_reconciliation_test.lua` and `tests/functional/init.lua` — saved-comment command journey and registration (judge repair pass 1).
- `.agent-runs/002-anchor-reconciliation/evidence.md` and `learnings-draft.md` — implementation evidence and durable findings.
- `specs/002-anchor-reconciliation.md` was already modified on entry; its approved contract was read and left untouched.

## Tests Added Or Updated
- New suite covers unique old/current range movement, restart, manual resolution, viewed-fingerprint invalidation, modified anchors, changed neighbors, duplicated context, automatic stale reattachment, missing entries, comment-only restart, returning file identities, rename display paths, missing sides, binary/submodule transitions, explicit Git target snapshots, boundary-context updates, unselected-file snapshot mismatch/read failure, canceled preloaded refresh/startup, and failed atomic replacement.
- Existing selected-content failure tests now wait for asynchronous preloaded refresh; existing identity failure, viewed reconciliation, no-comments/no-changes startup, storage, and functional coverage remain passing.
- Judge repair pass 1 adds a saved version-2 checkpoint fixture with old/current range comments and a file note. Existing `ReviewStart HEAD`, `ReviewRefresh`, and `ReviewStop` commands exercise startup movement, refresh movement, stale recovery, manual resolution/body/ID preservation, empty comparison, empty restart, returning identities, and stop without rewriting checkpoint bytes. Assertions read persisted records and native quickfix/tab state, not the configured session's internals.
- The new submodule read-failure test loads a real type-change candidate with old regular-file/new Gitlink metadata, removes the old loose blob, then supplies the candidate to session refresh. It asserts unchanged comparison/progress references, checkpoint bytes, current quickfix ID/items, window IDs, current buffer, and both panes' contents.
- Judge repair pass 2 extends the existing functional saved-comment journey rather than adding a duplicate fixture. It selects the file through its native quickfix mapping, performs a snapshot-producing command refresh, verifies the drawer is closed, removes the last comparison entry, and asserts the same tab/main window survive with native diff disabled and obsolete snapshots deleted. Restoring content and invoking `ReviewRefresh` reattaches the same saved records on the same quickfix list without any intervening stop/start. Separate empty restart and stop coverage remains in the same test.

## Primary Journey Verification
- Public command journey — `ReviewStart HEAD`, `ReviewRefresh`, `ReviewStop`; `tests/functional/comment_reconciliation_test.lua/review_commands_should_preserve_saved_comments_when_anchors_move_disappear_and_return` asserts exact saved records (stable IDs, bodies, old/current moved bounds, anchors/context, resolution and staleness), a newly owned empty-review quickfix list on restart, recovery through refresh on the same active tab, and unchanged saved bytes after stop.
- Selected last-entry disappearance — the same functional test additionally exercises actual quickfix selection plus immutable snapshot refresh with the drawer closed, persisted stale records after the empty refresh, surviving tab/main-window handles, deleted old snapshot buffers, and restored attachment through command refresh without restart.
- Persist and relocate comments — `ReviewSession:add_comment`, `resolve_comment`, `refresh`, `stop`, and `start`; `comment_reconciliation_tests.lua/refresh_should_move_unique_ranges_and_preserve_resolution_when_both_sides_move` asserts stable IDs, relocated old/current ranges, saved restart state, unchanged resolution, and fingerprint-based viewed invalidation.
- Preserve uncertain comments and reattach returning anchors — session refresh; `refresh_should_retain_last_location_and_reattach_stale_ranges_when_exact_context_returns` asserts retained last-known anchors/context, staleness on edits/ambiguity, and automatic reattachment without changing resolution.
- Restart without changed files — session start/refresh; `start_should_retain_comment_only_reviews_and_reattach_notes_when_file_identity_returns` asserts an active empty comparison retaining stale comments, returning text/file attachment, and renamed file-note display paths.
- Reject inconsistent content without partial adoption — preloaded session refresh; `refresh_should_reject_unselected_snapshot_when_bytes_change_after_aggregate` and `refresh_should_reject_entire_candidate_when_unselected_content_read_fails` assert unchanged active progress/comparison, checkpoint bytes, native quickfix items, and displayed buffer/text.
- Preserve immutable Git comparisons — session startup with an explicit target branch; `start_should_match_git_snapshot_ranges_when_explicit_target_moves` asserts old-side retention and current-side movement across restart.
- Cancel pending work — session stop during preloaded refresh/startup; cancellation tests assert idle state and unchanged saved checkpoint.
- Distinguish submodules from genuine read failures — preloaded session refresh; `refresh_should_preserve_review_when_supported_blob_read_fails_in_submodule_candidate` asserts the complete prior checkpoint and presentation survive a real supported-side Git read failure, rather than accepting the candidate as non-text.

## Commands Run
- `git status --short && git diff --stat` — PASS; initial tree had only the approved spec-contract modification.
- `just lint` — PASS; LuaLS reported no problems.
- `just format` — PASS.
- `just format-check` — PASS.
- `just test` — PASS; final repair-pass-2 run: 50 unit, 196 integration, 61 functional tests, zero failures.
- `git diff --check` — PASS.
- `git diff --stat`, scoped production/test `git diff`, and `git status --short` — PASS; inspected final changes and scope.
- Required gates were run in the requested order and repeated after final production changes. Earlier full runs also passed (the first had 190 integration tests before the last five cases were added).
- Repair pass 1 initial `just lint && just format && just format-check && just test` — FAIL at the new integration fixture's abbreviated-OID loose-object path; preceding gates and unit tests passed. Resolved the collector's abbreviated OID through real `git rev-parse` before deleting the fixture blob.
- `just test-integration refresh_should_preserve_review_when_supported_blob_read_fails_in_submodule_candidate` — PASS after fixture correction.
- `just test-functional review_commands_should_preserve_saved_comments_when_anchors_move_disappear_and_return` — FAIL in exploratory selected-pane variants; PASS after narrowing the command journey to the open file drawer and explicitly awaiting a new quickfix list on empty restart.
- Final repair-pass `just lint && just format && just format-check && just test && git diff --check` — PASS, in canonical order; LuaLS reported no problems.
- Repair pass 2 pre-fix `just test-functional review_commands_should_preserve_saved_comments_when_anchors_move_disappear_and_return` — FAIL at the tab-survival assertion, reproducing the reported lifecycle defect.
- Repair pass 2 initial `just lint && just format && just format-check && just test` — FAIL at LuaLS's nullable main-window parameter; fixed using the nearby `assert(main)` pattern. The subsequent run passed lint/format/format-check, unit and integration suites but failed an extra post-recovery reselection/disk-buffer-content assertion. Removed that unrelated assertion; retained all requested survival, snapshot cleanup and saved-comment recovery checks.
- Repair pass 2 post-fix targeted functional command — PASS.
- Repair pass 2 final `just lint && just format && just format-check && just test && git diff --check` — PASS, in canonical order; LuaLS reported no problems, 50 unit / 196 integration / 61 functional tests passed.
- Repair pass 2 scoped `git diff -- lua/diffreview/ui/side_by_side.lua`, `git diff --check`, and `git status --short` — PASS; inspected the minimal lifecycle patch and final scope.

## Results
- All required gates passed on final code. Negative-path tests intentionally emit real error notifications; these were expected and did not fail tests.
- No dependencies, services, UI commands, editor interfaces, comment projections, or commits were added.
- Judge repair pass 1 changed only tests, registration, evidence and learnings; all production files were left as reviewed. The user-requested coverage gaps are now exercised through commands and real Git failures.
- Judge repair pass 2 adds only the newly approved lifecycle correction in `side_by_side.clear` and extends the existing command regression. The exploratory last-entry tab-closure failure is now fixed and covered, not deferred.

## Spec Compliance Notes
- Session code owns asynchronous snapshot orchestration and request-currency checks after yielding. The comments domain performs only exact matching against supplied immutable views.
- Every present file with text comments is validated once, including unselected files and stale records. File-only notes need identity checks, not text loading. Selected views reuse validated snapshots.
- Complete anchors and all recorded available neighbors must match uniquely; a fingerprint is a consistency gate, not anchor evidence. Uncertain matches retain the previous location/context. Returning records clear staleness without changing ID/body/resolution.
- Candidate save precedes active state and presentation adoption. Identity changes, read failures, mismatched bytes, cancellation, and failed saves do not adopt a partial candidate.
- Submodule classification uses collector modes and a successful-content-loader result, rather than treating arbitrary error views as stale. Supported-side reads must succeed before unsupported submodule status is accepted.
- The Codebase Map matched actual paths; no map repair was needed. The user supplied gap-review PASS; no separate gap-review artifact was present in the supplied specs directory.
- Lifecycle flow was traced from `ReviewSession:refresh` through `ReviewUi:clear_selected_diff` to `side_by_side.clear`/`cleanup`. Deleting both displayed scratch snapshots could close the last windows and trigger the normal tab-closed stop handler. The correction attaches the existing empty information-buffer projection to the owned main window before deleting old buffers and excludes that replacement from cleanup; normal full-stop cleanup, native-diff restoration, and ownership checks remain intact. No comment-list UI is introduced.

## Risks Or Follow-ups
- Preloaded refresh is now asynchronous; callers must wait for completion, like normal refresh. Its boolean return continues to mean the request was accepted, not that reconciliation succeeded.
- Submodule views remain unsupported text views, as required by existing scope; Gitlink fingerprints use collector metadata. Comment-only presentation remains deferred to spec 004.
- Cancellation specifically during saved-comment startup snapshot loading was considered but not added: the existing public surface does not expose that startup phase, and selecting it deterministically would require interception or new test hooks. Existing tests cover immediate saved-comment startup cancellation and stop during preloaded commented-file snapshot loading.
- The previously recorded selected-pane last-entry lifecycle defect was resolved in repair pass 2 and is now asserted through the command-driven regression.
