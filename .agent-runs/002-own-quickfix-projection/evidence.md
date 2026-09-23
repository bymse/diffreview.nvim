# Evidence: 002-own-quickfix-projection

## Changed Files
- `lua/diffreview/ui/init.lua`
- `lua/diffreview/ui/quickfix.lua`
- `tests/integration/ui/quickfix_tests.lua`

## Tests Added Or Updated
- Updated all `ReviewUi:show_review_files` callers for the owned, no-return facade.
- Added exact instance-context and unrelated-history preservation coverage.

## Commands Run
- `just lint` — PASS
- `just format` — PASS
- `just format-check` — PASS
- `just test-integration show_review_files_should_preserve_unrelated_list_contents_and_history_when_updating` — PASS
- `just test-integration show_review_files_should_update_same_list_when_other_lists_exist` — PASS
- `just test-integration` — PASS (102 tests)
- `just test` — PASS (44 unit, 102 integration, 2 functional tests)

## Results
- Each UI instance now owns a stable quickfix list ID and instance-specific context, reusing the same list across updates.
- Quickfix entry rendering, ordering, stable `user_data.file_id`, selection, and bottom opening behavior remain covered.

## Spec Compliance Notes
- The existing `side_by_side.instance_id` supplies quickfix ownership identity; no global identity mechanism was added.
- Cleanup and failed-display rollback remain out of scope for Spec 003.

## Risks Or Follow-ups
- Owned quickfix cleanup and display rollback are intentionally deferred to Spec 003.
