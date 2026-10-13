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

## 003-comment-editor — 2026-10-12

Status: PASS

Changed files: `lua/diffreview/init.lua`, `lua/diffreview/review.lua`, `lua/diffreview/ui/init.lua`, `lua/diffreview/ui/side_by_side.lua`, new `lua/diffreview/ui/comment_editor.lua`; focused functional editor, lifecycle and by-ID suites, registrations, command and shared mutation tests; spec contract and evidence included.

Verification: independent lint, format, format-check, full tests and diff-check passed; 50 unit, 197 integration, 78 functional (325). Evidence: `.agent-runs/003-comment-editor/independent-verification.md`.

Judge result: PASS after functional-interface coverage repair and report-only correction; compliance 5/5, all other scores 4/5.

Important decisions: one editor, write remains open and pins ID, dirty/pending guards, pinned location/owner, actual visible-text matching, detached listed draft preservation on tab closure. Product-command lifecycle tests replace internal-state assertions.

Follow-up risks: detached drafts are retained editor buffers rather than crash-recovery storage. A clean creation draft surviving refresh rejects obsolete-comparison writes and must be reopened.

## 004-comment-presentation — 2026-10-12

Status: PASS

Changed files: command/session/UI boundaries, `lua/diffreview/ui/quickfix.lua`, `lua/diffreview/ui/side_by_side.lua`, new `lua/diffreview/ui/comment_decorations.lua`; focused quickfix/decorations integration suites, management/attachment/overlap/safety/lifecycle functional suites, functional comments helper, registrations and affected fixtures; Codebase Map, spec contract and evidence included. Full inventory: `.agent-runs/004-comment-presentation/evidence.md`.

Verification: independent lint, format, format-check, full tests and diff-check passed; 50 unit, 200 integration, 87 functional (337). Evidence: `.agent-runs/004-comment-presentation/independent-verification.md`.

Judge result: PASS; compliance, architecture, simplicity 5/5; tests, regression risk, maintainability 4/5. Async same-ID pending-source replacement has a mutation-proven regression. Independent verification also found redundant unchanged-checkpoint startup rewriting, now avoided with structured equality and deterministic regression coverage.

Important decisions: separate owned lists sharing one drawer; `<CR>/e/d/r/a` actions; range-aware attachment and bang cancellation; save-before-projection, stale file-level annotations and isolated namespace cleanup; clean pinned-editor invalidation only after successful mutation.

Follow-up risks: native quickfix history remains global but actions validate ownership and presentation. Verification used isolated headless Neovim/Git fixtures; no separate interactive TUI smoke test was required or performed. No outstanding failures or blockers.

## Completion — 2026-10-12

All four specs completed in filename order with fresh implementers, gap-review approval, independent canonical gates, and passing quality-judge review. Each phase has evidence and promoted durable learnings. Final implementation provides local durable comments, exact reconciliation, write-to-save editing, independent comment browsing/management and annotations. No verification gates remain blocked or skipped.

## Review Feedback Fixes — 2026-10-12

Status: PASS

User-approved decisions: retain unique exact text/context matching; text comments are allowed only on the new/current side. Old-side text locations are rejected for creation and reattachment, including old-only deleted-file panes. File-level notes remain supported through changed-file rows, including deleted files, and presented non-text views.

Changed files: `lua/diffreview/comments.lua` restricts location types and shared record validation to `current` or file notes; `lua/diffreview/ui/init.lua` rejects old-side creation/attachment contexts before opening an editor. Comment state, storage, reconciliation, editor, attachment, navigation and annotation tests were updated to exercise current-side behavior and old-side rejection. Shared comment fixtures, write/list/editor helpers were moved into `tests/helpers/functional_review.lua`; `tests/helpers/functional_comments.lua` was removed and all consumers updated. `specs/CONTEXT.md` and specs 001–004 now describe current-side-only text comments.

Anchoring research: the user's plugin at `~/.config/nvim/lua/review/comments.lua` and `state.lua` stores fixed hunk-line ranges, selected `code_context` and a file `diff_hash`, marking comments stale when the diff changes rather than searching for moved text. The user explicitly chose to retain this repository's unique text/context matching for now.

Submodule decision: retain the `160000` fingerprint branch. `load_diffs` fingerprints all collected entries, including staged Gitlink changes and regular-file-to-submodule transitions; using the Gitlink OID avoids reading a submodule directory as a regular file. This does not enable submodule text rendering.

Verification: `just lint`, then `just format`, `just format-check`, `just test`, and `git diff --check` passed. Final results: 50 unit, 200 integration and 87 functional tests, 337 total with zero failures. During verification, the current-side annotation assertion was corrected to distinguish a range annotation from the file-note annotation now sharing the current buffer.

Follow-up risks: no known outstanding failures. Existing old-side comment records are invalid under the corrected schema contract; no automatic conversion or silent reassignment was introduced. The user's `comments.md` review input was preserved.

## Comment Model Review Fixes — 2026-10-13

Status: PASS

User-approved decisions: remove explicit side fields from comment records and locations; use current-file line ranges, with old-pane rejection retained at the UI boundary. Replace resolved/stale booleans with `status: 'open'|'resolved'|'stale'`; resolved comments remain resolved regardless of attachment availability. Reopening checks the current anchor or file identity and returns open or stale. Reattachment preserves resolved status and otherwise returns open.

Architecture: `lua/diffreview/comments.lua` now exposes a per-review `Comments` instance with explicit add, edit, delete, resolve, reopen, reattach and reconcile methods instead of an action-string dispatcher. Session operations fork comment state, save the complete candidate checkpoint, and only then adopt the instance and update projections. Active comments and their checkpoint projection share the adopted records; failed loading, validation or persistence leaves both unchanged. Text reopening uses asynchronous, fingerprint-validated snapshots and the existing session-currency guards.

Paths and presentation: comments no longer duplicate `display_path`; the UI derives readable current or last-known paths from retained file-progress records, falling back to file ID when no retained file record exists. Lists show one status and side-free locations. Resolved text comments use file-level annotations and navigation rather than suggesting an attachment that may no longer be valid. Stale unresolved comments retain their last-known anchors and recover through unique exact text/context matching.

Changed files: comment domain, session, progress and storage modules; comment quickfix, decoration, navigation and UI boundaries; affected integration and functional fixtures/assertions; `specs/CONTEXT.md` and supersession notes in specs 001–004. Added integration regressions for reopening resolved text after edits, disappearance, restart and anchor recovery; reopening missing file notes; and rejecting changed comparison snapshots without altering resolved state. Functional coverage checks last-known browsing paths in comment-only reviews. The user's existing annotation cleanup in `comments.lua` and `comments.md` review input were preserved.

Verification: `just lint`, then `just format`, `just format-check`, `just test`, and `git diff --check` passed. Results: 50 unit, 203 integration and 87 functional tests, 340 total with zero failures. Captured outputs: `/tmp/opencode/comments-lint.log` and `/tmp/opencode/comments-tests.log`.

Compatibility: checkpoint version 3 replaces version 2 without migration, consistent with the existing no-old-checkpoint assumption. Older checkpoints are rejected, not overwritten or silently converted. Text-comment reopening now requires coroutine context, like text creation and reattachment; native comment-list actions enter coroutine context. No known outstanding failures.

## Comment UI Architecture Review Fixes — 2026-10-13

Status: PASS

User-approved changes: split `ui/quickfix.lua` into `ui/files_list.lua`, `ui/comments_list.lua` and `ui/quickfix_helpers.lua`. Each list retains its own presentation and mapping state; shared native quickfix operations preserve list ownership, inactive updates, drawer selection and cursors.

Input interpretation: comment keys map to named UI callbacks. The session replaces `comment_action(key, id)` with explicit navigation, resolution-toggle and attachment-begin operations, reusing existing edit/delete methods. Dirty/pending editor guards, status decisions, coroutine entry and save-before-adopt remain in session orchestration.

Naming: `load_matching_view_model`, `load_comment_view_models`, their result collections and `diffs.load_selected_view_model` now use explicit view-model terminology. Callers and selected-loader tests were updated. The user's `comments.md` remains untouched.

Verification: `just lint`, then `just format`, `just format-check`, `just test`, and `git diff --check` passed. Results: 50 unit, 203 integration and 87 functional tests, 340 total with zero failures. Captured outputs: `/tmp/opencode/list-refactor-lint.log` and `/tmp/opencode/list-refactor-tests.log`.

## Fixed-Range Comment Simplification — 2026-10-13

Status: PASS

User-approved behavior: text comments retain fixed file identities and inclusive line ranges. Selected text is stored as an SHA-256 `anchor_hash`; refresh and restart compare only that range without searching for moved text or requiring unchanged neighbors. Changed or unavailable locations make unresolved comments stale; matching text restores open status. Resolved comments remain resolved.

Acknowledgement: writing a stale comment, including unchanged `:w` or `:wq`, recaptures current text at its retained coordinates and opens it when available. Body and metadata are saved atomically before adoption and presentation updates. Missing identities, absent/non-text current content, or out-of-range bounds preserve stale status and the prior hash while allowing body edits and manual deletion. No range clamping, location conversion, or manual retargeting remains. Genuine read failures and inconsistent comparison snapshots reject the write and preserve the draft/checkpoint.

Removed: `ReviewCommentAttach`, the comment-list `a` mapping, pending-attachment state and cancellation/ownership logic, session/domain reattachment APIs, and the obsolete attachment functional suites. Existing navigation, deletion, resolution toggling, independent quickfix lists, and stale file-level presentation remain.

Editor changes: read-only virtual-line previews show target coordinates and current code separately from the body, or indicate unavailable locations. Text previews are pinned to their comparison; refreshing requires reopening before saving. New text writes also validate the captured range against the original preview so restored unsaved source edits cannot silently capture different code. Writes mark drafts modified until persistence succeeds and wait for asynchronous capture before native `:wq` closes; failed unchanged writes retain an open draft for retry.

Changed areas: comment domain, session orchestration, command registration, editor/comment-list UI, progress/storage schemas, affected integration/functional tests and shared real-editor fixtures. Added focused acknowledgement, preview-validity/lifecycle, and unavailable-location/read-failure functional coverage. `specs/CONTEXT.md` and follow-up headers in specs 001–004 record the superseding contract. The user's `comments.md` was not modified.

Compatibility: checkpoint version 4 replaces version 3 without migration, consistent with the established no-old-checkpoints assumption. Old checkpoints are rejected rather than overwritten or silently converted. By-ID text-editor opening and stale text edits use coroutine-based snapshot loading.

Verification: the `test-runner` agent ran `just lint`, then `just format`, `just format-check`, and `just test`; all passed. Final results: 50 unit, 202 integration, and 98 functional tests, 350 total with zero failures. `git diff --check` passed. Captured outputs: `/tmp/opencode/fixed-comments-lint.log`, `/tmp/opencode/fixed-comments-format.log`, `/tmp/opencode/fixed-comments-format-check.log`, and `/tmp/opencode/fixed-comments-tests.log`.

Quality review: the requested `my-code-quality-judge` instructions were executed by a read-only general reviewer. Initial review blocked a new-preview/snapshot mismatch and missing preview/unavailable-write coverage; both were repaired and independently re-reviewed. Final verdict: PASS, no blockers; compliance 5/5, architecture 4/5, simplicity 5/5, test quality 4/5, regression risk 4/5, maintainability 4/5. Report: `/tmp/opencode/fixed-comments-judge.md`.
