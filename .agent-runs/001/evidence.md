# Evidence: 001

## Changed Files
- `lua/diffreview/diff_view_model.lua`
- `lua/diffreview/diffs/init.lua`
- `lua/diffreview/diffs/git.lua`
- `lua/diffreview/ui/diff_view_model.lua` (removed)
- `tests/integration/diffs_load_review_tests.lua`
- `tests/integration/init.lua`

## Tests Added Or Updated
- Added real-Git integration coverage for complete option validation, valid and invalid `origin/HEAD` targets, merge-base local/remote branches, tag/hash resolution, ambiguous and unresolved revisions, no-commit repositories, exact branch endpoints, empty comparisons, tracked operations A/C/D/M/R/T/U, filesystem and repository errors including effective native cwd access and injected post-discovery untracked inspection failure, Git-native untracked text/binary summaries, and lightweight retained metadata.

## Commands Run
- `just lint` — PASS
- `just format` — PASS
- `just format-check` — PASS
- `just test-integration load_review_should_load_default_branch_baseline_through_working_state_when_origin_head_exists` — PASS
- `just test-integration load_review_should_use_exact_endpoints_and_exclude_working_state_when_two_revisions_are_supplied` — PASS
- `just test-integration load_review_should_normalize_operation_identities_when_git_reports_added_deleted_modified_renamed_and_type_changed` — PASS
- `just test-integration load_review_should_resolve_branch_and_tag_revisions_when_one_revision_is_supplied` — PASS
- `just test-integration load_review_should_summarize_binary_untracked_files_without_retaining_contents` — PASS
- `just test-integration load_review_should_use_new_identity_when_git_reports_a_copy` — PASS
- `just test-integration load_review_should_use_stored_identity_when_git_reports_an_unmerged_file_with_baseline_content` — PASS
- `just test-integration load_review_should_match_git_numstat_for_untracked_text_line_endings` — PASS
- `just test-integration load_review_should_return_revision_errors_when_caller_revisions_are_unresolved_or_ambiguous` — PASS
- `just test-integration load_review_should_use_new_identity_when_git_reports_an_unmerged_file_without_baseline_content` — PASS
- `just test-integration load_review_should_return_missing_default_branch_when_origin_head_is_absent` — PASS
- `just test-integration load_review_should_return_repository_error_when_cwd_is_not_a_worktree` — PASS
- `just test-integration load_review_should_return_requested_errors_when_repository_has_no_commits` — PASS
- `just test-integration load_review_should_return_missing_default_branch_when_origin_head_target_is_invalid` — PASS
- `just test-integration load_review_should_resolve_branch_and_tag_revisions_when_one_revision_is_supplied` — PASS
- `just test-integration load_review_should_resolve_remote_branches_and_hashes_when_one_revision_is_supplied` — PASS
- `just test-integration load_review_should_treat_branch_names_as_exact_endpoints_when_two_revisions_are_supplied` — PASS
- `just test-integration load_review_should_return_filesystem_error_when_an_untracked_file_cannot_be_inspected` — PASS
- `just test-integration load_review_should_return_filesystem_error_when_cwd_is_inaccessible` — PASS
- `just test-integration load_review_should_return_filesystem_error_when_native_cwd_access_fails` — PASS
- `just test-integration` — PASS (98 tests)
- `just test` — PASS (44 unit, 98 integration, 2 functional tests)

## Results
- The loader returns lightweight changed-file summaries and retained Git metadata only; it does not construct file snapshots or full diff models.
- Revision policy maps caller revision failures to `revision`; working-state untracked counts are obtained through Git's `--no-index --numstat` behavior.
- Invalid, dangling, and non-commit `origin/HEAD` targets map to `missing_default_branch`; every returned summary is unviewed and retained state is checked for absent snapshot/full-model fields.
- Cwd read and traverse access is validated with libuv before Git repository discovery; a mode-0444 directory follows effective native access and a scoped native-access failure proves the filesystem diagnostic branch.

## Spec Compliance Notes
- Shared view-model annotations now reside at `diffreview.diff_view_model`; the obsolete UI module path was removed.
- Working-state comparisons use one baseline-to-working-state tracked diff and separately append untracked paths.
- Retained tracked entries store the original `GitDiff` without duplicating its metadata fields.

## Risks Or Follow-ups
- No known blockers.
