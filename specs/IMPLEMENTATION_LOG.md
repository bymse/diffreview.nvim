# Implementation Log

## Preflight — 2026-10-12

Specs 001–004 are ordered and pending. The working tree is clean on branch `comments`. Shared context includes the feature Codebase Map. Canonical gates are `just lint`, `just format`, `just format-check`, and `just test`, in that order. Each phase requires independent verification and judge approval before its checkpoint commit.

## 001-comment-records — 2026-10-12

Status: PASS

Changed files: `lua/diffreview/comments.lua`, `lua/diffreview/review.lua`, `lua/diffreview/review_progress.lua`, `lua/diffreview/storage.lua`, `tests/integration/comment_state_tests.lua`, `tests/integration/storage_tests.lua`, `tests/integration/review_progress_tests.lua`, and `tests/integration/init.lua`; spec contract and orchestration evidence included.

Verification: independent `just lint`, `just format`, `just format-check`, and `just test` passed; 50 unit, 183 integration, 60 functional tests. Evidence: `.agent-runs/001-comment-records/independent-verification.md`.

Judge result: PASS; compliance, architecture, simplicity, tests and maintainability 5/5; regression risk 4/5. No blockers.

Important decisions: version-2 schema, named session operations and detached results; snapshot consistency and save-before-adopt; eligibility and cancellation clarified in the spec before coding.

Follow-up risks: text add/reattach calls require coroutine context. Matching and comment-only startup are deferred to spec 002 as planned.

## 002-anchor-reconciliation — 2026-10-12

Status: PASS

Changed files: `lua/diffreview/comments.lua`, `lua/diffreview/review.lua`, `lua/diffreview/review_progress.lua`, `lua/diffreview/diffs/content.lua`, `lua/diffreview/diffs/init.lua`, `lua/diffreview/diffs/fingerprint.lua`, `lua/diffreview/ui/side_by_side.lua`, focused reconciliation integration/functional suites, category registrations and refresh fixtures; spec clarifications and phase evidence included.

Verification: independent lint, format, format-check, full tests and diff-check passed; 50 unit, 196 integration, 61 functional. Evidence: `.agent-runs/002-anchor-reconciliation/independent-verification.md`.

Judge result: PASS after two repair passes; compliance, architecture, simplicity 5/5; tests, regression risk, maintainability 4/5.

Important decisions: returning anchors automatically clear stale status; non-text differs from read failure; all text-comment files need validated snapshots. Review found and fixed selected-pane cleanup closing the tab on empty refresh, with a command-driven regression.

Follow-up risks: preloaded refresh is asynchronous and returns request acceptance. Startup cancellation during saved-comment loading is indirectly covered; request-currency guards are intact. Comment-only list presentation belongs to spec 004.
