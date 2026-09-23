# Evidence: 003-clean-quickfix-projection

## Changed Files
- `lua/diffreview/ui/quickfix.lua`
- `lua/diffreview/ui/init.lua`
- `tests/integration/ui/quickfix_tests.lua`

## Tests Added Or Updated
- Added quickfix cleanup ownership, stale identity, repeated cleanup, and transactional selection/window rollback coverage, including no-current-window replacement/update rollback and other-tab preservation.

## Commands Run
- `just lint` — PASS
- `just format` — PASS
- `just format-check` — PASS
- `just test-integration cleanup_should_empty_owned_list_and_close_only_owned_current_tab_window` — PASS
- `just test-integration show_review_files_should_restore_existing_list_when_selection_fails` — PASS
- `just test-integration show_review_files_should_restore_preexisting_window_when_open_fails` — PASS
- `just test-integration show_review_files_should_close_new_window_when_open_fails` — PASS
- `just test-integration show_review_files_should_close_new_window_and_restore_selected_owned_list_when_update_fails` — PASS
- `just test-integration` — PASS (111 tests)
- `just test` — PASS (44 unit, 111 integration, 2 functional tests)
- `git diff --check` — PASS

## Results
- Cleanup validates exact quickfix context, empties only owned lists, and closes only owned current-tab quickfix windows.
- Display failures restore existing list properties and selection, or empty a newly created list and leave facade identity unset; they close only current-tab windows introduced by the failed `copen`.

## Spec Compliance Notes
- Quickfix window handling is limited to the current tabpage; rollback derives newly introduced windows from stable before/after window-ID sets and does not inspect or close other-tab windows.
- Rollback protects restoration steps and rethrows the original display error.

## Risks Or Follow-ups
- None.
