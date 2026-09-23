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
