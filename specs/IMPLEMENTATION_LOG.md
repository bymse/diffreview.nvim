# Implementation Log

## 001-load-lightweight-review-files — 2026-09-23

Status: PASS

Changed files:
- `lua/diffreview/diff_view_model.lua`
- `lua/diffreview/ui/diff_view_model.lua` (deleted)
- `lua/diffreview/diffs/git.lua`
- `lua/diffreview/diffs/init.lua`
- `tests/integration/diffs_load_review_tests.lua`
- `tests/integration/init.lua`

Verification:
- `just lint` — PASS
- `just format-check` — PASS
- `just test-integration` — PASS (100 tests)
- `just test` — PASS (146 tests)

Judge result:
- PASS: spec compliance 5/5, architectural fit 5/5, simplicity/YAGNI 4/5, test quality 5/5, regression risk 4/5, maintainability 4/5.

Important decisions:
- Working-state comparisons reuse one baseline-to-worktree Git diff and append separately inspected untracked paths.
- Stable IDs use baseline paths for stored files and current paths for added, copied, and untracked files.
- Shared diff model annotations now live at `diffreview.diff_view_model` without a compatibility shim.

Follow-up risks:
- None.

## 002-own-quickfix-projection — 2026-09-23

Status: PASS

Changed files:
- `lua/diffreview/ui/init.lua`
- `lua/diffreview/ui/quickfix.lua`
- `tests/integration/ui/quickfix_tests.lua`

Verification:
- `just lint` — PASS
- `just format-check` — PASS
- `just test-integration` — PASS (102 tests)
- `just test` — PASS (148 tests)

Judge result:
- PASS: spec compliance 5/5, architectural fit 5/5, simplicity/YAGNI 5/5, test quality 5/5, regression risk 4/5, maintainability 5/5.

Important decisions:
- `ReviewUi` reuses its existing instance identity for quickfix ownership context.
- The facade stores a returned quickfix ID only after low-level display succeeds and no longer exposes list identity to callers.

Follow-up risks:
- Owned cleanup and transactional display rollback remain intentionally deferred to Spec 003.

## 003-clean-quickfix-projection — 2026-09-23

Status: PASS

Changed files:
- `lua/diffreview/ui/init.lua`
- `lua/diffreview/ui/quickfix.lua`
- `tests/integration/ui/quickfix_tests.lua`
- `specs/003-clean-quickfix-projection.md`

Verification:
- `just lint` — PASS
- `just format-check` — PASS
- `just test-integration` — PASS (111 tests)
- `just test` — PASS (157 tests)

Judge result:
- PASS: spec compliance 5/5, architectural fit 4/5, simplicity/YAGNI 4/5, test quality 5/5, regression risk 4/5, maintainability 4/5.

Important decisions:
- Quickfix window cleanup and rollback are limited to the current tabpage where the projection is displayed.
- Exact context equality validates list ownership, and stale or foreign facade identities are cleared before replacement.
- Transactional rollback restores list and selection state best-effort while preserving the original display error.

Follow-up risks:
- None.

## 004-expose-review-lifecycle — 2026-09-23

Status: PASS

Changed files:
- `lua/diffreview/async.lua`
- `lua/diffreview/config.lua`
- `lua/diffreview/diffs/git.lua`
- `lua/diffreview/diffs/init.lua`
- `lua/diffreview/init.lua`
- `lua/diffreview/review.lua`
- `tests/integration/git_repo_meta_tests.lua`
- `tests/integration/plugin_test.lua`
- `tests/integration/review_tests.lua`
- `tests/integration/init.lua`
- `tests/functional/plugin_test.lua`
- `specs/004-expose-review-lifecycle.md`

Verification:
- `just lint` — PASS
- `just format-check` — PASS
- `just test-integration` — PASS (121 tests)
- `just test-functional` — PASS (2 tests)
- `just test` — PASS (44 unit, 121 integration, 2 functional tests)

Judge result:
- PASS: spec compliance 5/5, architectural fit 5/5, simplicity/YAGNI 4/5, test quality 4/5, regression risk 4/5, maintainability 4/5.

Important decisions:
- Public setup commits configuration only after both commands register and rolls back resources acquired by a failed attempt.
- `review.lua` owns the singleton lifecycle, notifications, UI rollback, and operation-identity checks around every asynchronous completion.
- Cancellation remains separate from diff options and propagates through repository commands as a detail-free terminal result.
- Duplicate process callbacks cannot resume or commit one lifecycle operation more than once.

Follow-up risks:
- None.

## Spec 004 review follow-up — 2026-09-23

Status: PASS

Changes:
- Renamed `GitRepo:empty_source_numstat` to `GitRepo:untracked_file_stats` to make its purpose explicit.
- Removed cancellation state from system-call and Git-adapter interfaces; `load_review` now checks cancellation between top-level loading steps.
- Added coverage for cancellation between revision candidates and untracked-file inspections.

Verification:
- `just lint` — PASS
- `just format-check` — PASS
- `just test` — PASS (44 unit, 121 integration, 2 functional tests)

Follow-up risks:
- In-flight system calls are not terminated; their results are ignored at the next loader or lifecycle boundary after cancellation.

## Branch review follow-up — 2026-09-23

Status: PASS

Changes:
- Replaced the module-level review singleton with `ReviewSession` objects created by `review.new(config)`; public setup and commands now start and stop one specific session.
- Moved setup-option normalization and validation into `config.lua`.
- Added direct `ReviewStart` command arity validation because Neovim has no native zero-to-two argument declaration.
- Moved the shared UI `instance_id` to `ReviewUi`; quickfix rebuilds `diffreview:files:<instance_id>` contexts internally and validates incoming list IDs before updating them.
- Removed transactional quickfix display rollback while retaining exact ownership checks and targeted cleanup.
- Removed the redundant `GitRepo:named_ref` wrapper and used `rev_parse` directly.
- Deleted the integration plugin test and retained plugin command coverage in the functional suite.

Verification:
- `just lint` — PASS
- `just format-check` — PASS
- `just test` — PASS (162 tests)

Important decisions:
- Review lifecycle state belongs to an explicit session object rather than module-global state.
- `ReviewUi.instance_id` identifies the whole UI and is the ownership source for both quickfix and side-by-side resources.
- Quickfix owns context construction and stale-ID recovery; `ReviewUi` stores only the returned list ID.
- Quickfix display failures are allowed to propagate without restoring prior list or window state.

Follow-up risks:
- A failure after quickfix mutation may leave the newly selected list or opened window visible; this is accepted to keep display orchestration simple.

## Review comments follow-up — 2026-09-23

Status: PASS

Changes:
- Added focused unit coverage for `config.normalize`, including defaults, supported options, and every validation error; setup and lifecycle tests retain only their distinct behavioral assertions.
- Added direct integration coverage for the new `GitRepo:symbolic_ref`, `GitRepo:merge_base`, and `GitRepo:untracked_file_stats` exports, including success and failure results plus text and binary file stats.

Verification:
- `just lint` — PASS
- `just format-check` — PASS
- `just test` — PASS (50 unit, 123 integration, 2 functional tests)

Follow-up risks:
- None.
