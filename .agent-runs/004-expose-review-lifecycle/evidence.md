# Evidence: 004-expose-review-lifecycle

## Changed Files
- `lua/diffreview/async.lua`
- `lua/diffreview/config.lua`
- `lua/diffreview/diffs/git.lua`
- `lua/diffreview/diffs/init.lua`
- `lua/diffreview/init.lua`
- `lua/diffreview/review.lua`
- `specs/004-expose-review-lifecycle.md`
- `tests/integration/init.lua`
- `tests/integration/git_repo_meta_tests.lua`
- `tests/integration/plugin_test.lua`
- `tests/integration/review_tests.lua`
- `tests/functional/plugin_test.lua`

## Tests Added Or Updated
- Added real ReviewUi quickfix cleanup/resource-preservation, suspended-start conflict, isolated UI failure, cancellation, and duplicate process-callback coverage.
- Replaced hello/plugin coverage with explicit setup, transactional registration, public-option, and zero-to-two command-routing coverage.

## Commands Run
- `just format` — PASS
- `just lint` — PASS
- `just format-check` — PASS
- `just test-integration start_should_display_loaded_files_and_cleanup_when_stopped` — PASS
- `just test-integration stop_should_suppress_late_canceled_start_completion` — PASS
- `just test-functional plugin_should_expose_setup_commands_and_command_arity_behavior` — PASS
- `just test-integration plugin_should_validate_setup_and_register_commands_transactionally` — PASS
- `just test-integration repo_meta_should_propagate_cancellation_from_optional_metadata_commands` — PASS
- `just test-integration start_should_display_real_quickfix_and_preserve_unrelated_resources_when_stopped` — PASS
- `just test-integration start_should_reject_second_start_while_loader_is_suspended` — PASS
- `just test-integration start_should_complete_lifecycle_once_when_process_callback_is_repeated` — PASS
- `just test-integration git_commands_should_return_canceled_without_diagnostics_when_operation_is_canceled_before_or_during_execution` — PASS
- `just test-integration` — PASS (121 tests)
- `just test-functional` — PASS (2 tests)
- `just test` — PASS (44 unit, 121 integration, 2 functional tests)
- `git diff --check` — PASS

## Results
- Explicit one-time setup rolls back `ReviewStart` if `ReviewStop` registration fails, leaving setup retryable; public start and stop delegate to the private lifecycle owner.
- Cancellation propagates from async process ownership through normal and optional Git commands into detail-free diff-load failures; late completions cannot commit an obsolete review.
- `ReviewStart` routes zero, one, and two revisions correctly; over-arity enters validation without starting a lifecycle coroutine, while `ReviewStop` retains native arity handling.
- Repeated process callbacks schedule only one suspended coroutine continuation and lifecycle completion.

## Spec Compliance Notes
- No automatic setup, full diff activation, persistence, refresh, or command-line cwd option was added.
- The approved uncommitted Spec 004 clarification and stale `.agent-runs/001/` directory were preserved.

## Risks Or Follow-ups
- None identified by the required gates.
