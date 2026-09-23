# Evidence: 001-load-lightweight-review-files

## Changed Files
- `lua/diffreview/diff_view_model.lua`
- `lua/diffreview/ui/diff_view_model.lua` (deleted)
- `lua/diffreview/diffs/git.lua`
- `lua/diffreview/diffs/init.lua`
- `tests/integration/diffs_load_review_tests.lua`
- `tests/integration/init.lua`

## Tests Added Or Updated
- Added real-Git integration coverage for loader validation, revision resolution, comparison modes, operation summaries, untracked files, structured errors, lightweight retained state, default cwd selection, and Git command failures.

## Commands Run
- `just test-integration load_review_should_load_default_branch_baseline_through_working_state_when_origin_head_exists` — PASS
- `just test-integration load_review_should_return_revision_errors_when_caller_revisions_are_unresolved_or_ambiguous` — PASS
- `just test-integration load_review_should_normalize_operation_identities_when_git_reports_added_deleted_modified_renamed_and_type_changed` — PASS
- `just test-integration load_review_should_use_new_identity_when_git_reports_a_copy` — PASS
- `just test-integration load_review_should_return_git_error_when_tracked_diff_command_fails` — PASS
- `just test-integration load_review_should_use_process_current_directory_when_cwd_is_omitted` — PASS
- `just test-integration` — PASS (100 tests)
- `just lint` — PASS
- `just format` — PASS
- `just format-check` — PASS
- `just test` — PASS (44 unit, 100 integration, 2 functional tests)

## Results
- The loader returns lightweight changed-file summaries with stable IDs and private metadata only; it does not construct or retain snapshots or full diff models.
- Revision policy distinguishes named branches from tags and commit-ish expressions and rejects ambiguous or unsupported full ref namespaces.

## Spec Compliance Notes
- Stable error kind, message, and detail handling is covered by integration tests.
- Genuine type-change and copy fixtures assert the retained Git statuses are `T` and `C`.
- Working-state comparisons include tracked staged/unstaged and untracked summaries; two-endpoint comparisons exclude later working-state changes.

## Risks Or Follow-ups
- None for this spec.
