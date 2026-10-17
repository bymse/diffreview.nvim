# Evidence: 002

## Changed Files
- `lua/diffreview/ui/init.lua`: optional display/refresh file identities, annotated public projection methods, per-instance comment resources, and independent TabClosed comment cleanup.
- `lua/diffreview/ui/side_by_side.lua`: captures actual source pane/window/buffer roles and logical snapshot counts; clears projections and associations on transitions and teardown.
- `lua/diffreview/ui/comment_decorations.lua`: association validation before replacement, isolated virtual-line projection, stale anchor fallback, borrowed-buffer-safe clearing, and source bounds computed once per pane per projection.
- `tests/integration/ui/comments/helpers.lua`: local public/editor fixture helpers and real extmark inspection.
- `tests/integration/ui/comments/display_tests.lua`, `targets_tests.lua`, `cleanup_tests.lua`: seven new public-facade integration tests after moving the native tab-close journey to functional coverage.
- `tests/integration/init.lua`: registers the three test modules.
- `tests/functional/comment_tab_cleanup_test.lua` and `tests/functional/init.lua`: focused native tab-close journey and its registration; no integration-helper dependency.
- `specs/CONTEXT.md`: adds the projection module and focused tests to the Codebase Map.
- `.agent-runs/002/evidence.md` and `learnings-draft.md`: implementation evidence and durable findings. Existing `gap-review.md` is unchanged.

## Tests Added Or Updated
- `show_comments_should_render_both_sides_and_preserve_source_when_layout_changes`: both layouts and native diff windows; unchanged-line and range anchors, body blank/trailing lines, supplied order, detached input, resolved/empty replacement, and main-only versus explicit-side whole-file blocks.
- `show_comments_should_render_file_targets_once_when_main_is_source_or_information`: deleted old main, binary information, and rename-only current main; omitted hidden-side feedback and information-view line anchors.
- `show_comments_should_clamp_only_stale_anchors_when_source_is_short_or_empty`: original visible coordinates and immutable targets, stale fallback, missing old side, and omitted non-stale out-of-bounds/empty-source feedback.
- `show_comments_should_reject_unassociated_or_lost_panes_without_clearing_projection`: omitted IDs, refresh forwarding, mismatched IDs, replaced pane buffers, and fresh display identity reset.
- `display_diff_side_by_side_should_reject_invalid_identity_when_provided`: rejects an empty explicit ID.
- `clear_comments_should_preserve_borrowed_source_and_diff_highlights_when_projection_is_replaced`: real Git-backed file buffer bounds, isolated clear, unrelated records, refresh/replacement/clear, explicit cleanup, and preserved source text/modified flag.
- `cleanup_should_clear_borrowed_annotations_when_tab_closes_without_handler_cleanup` in `tests/functional/comment_tab_cleanup_test.lua`: moved from integration; native tab close with a notification-only handler, surviving unmodified borrowed buffer, removed comment marks with existing diff marks preserved, invalidated association, and repeated explicit cleanup. It asserts marks were added before closing, so cleanup cannot pass vacuously.
- `clear_comments_should_tolerate_deleted_buffers_when_panes_are_lost`: manually closed window, deleted snapshot buffer, and idempotent teardown.

## Primary Journey Verification
- Normal journey — public `display_diff_side_by_side` and `show_comments`; `display_tests.lua` / `show_comments_should_render_both_sides_and_preserve_source_when_layout_changes` asserts actual side buffers, range placement, complete body text, unchanged source, and native diff layout.
- Whole-file journey — public display/projection; both `display_tests.lua` tests assert main-only side-less blocks, explicit-side source roles, and binary information support.
- Replacement/cleanup journey — public projection/refresh/display/clear/cleanup in integration `cleanup_tests.lua`, plus native `:tabclose!` in functional `comment_tab_cleanup_test.lua`; asserts no leaked comment marks, preserved diff marks, and surviving unmodified Git-backed buffers.
- Failure journey — public projection calls after wrong/omitted identity and replaced/lost panes; `targets_tests.lua` and integration `cleanup_tests.lua` assert failures without decorating replacements or prematurely clearing existing projections.
- Independent verification passed every journey before and after repair. All eight cases remain, with the native-command case now in the functional category.

## Commands Run
- `git status --short` — PASS; initial status contained only the existing untracked `.agent-runs/002/` directory.
- `just lint` — PASS; LuaLS reported no problems.
- `just lint && just format && just format-check` — PASS; ordered static gates passed after implementation/test updates.
- `git diff --stat` — PASS; inspected tracked change scope (untracked additions inspected separately with file tools).
- `git diff --check && git diff -- lua/diffreview/ui/init.lua lua/diffreview/ui/side_by_side.lua` — PASS; inspected facade and ownership changes.
- `just lint && just format && just format-check && git diff --check` — PASS; final Lua/test source state, all commands exited 0 and LuaLS reported no problems.
- `git status --short && git diff --stat` — PASS; only scoped production/test/map changes and run artifacts are present; nothing staged.
- `just test` — PASS in initial independent test-runner verification; see Independent Verification. Not run directly by this implementer.
- Repair pass 1: `just lint && just format && just format-check && git diff --check` — PASS; ordered static gates all exited 0 and LuaLS reported no problems after the test move and bounds optimization.
- Repair pass 1: `just test` — PASS through independent test-runner session `ses_eb7199e56ffe7iY0lhTgVZRR9O`; no tests were run directly by the implementer.

## Results
- Static gates and post-repair independent verification pass: 318 tests (68 unit, 189 integration, 61 functional). Eight added cases are registered: seven integration and one functional.
- Source inspection of UI requires confirms no comments collection dependency or controller/lifecycle wiring. Rendering uses native extmarks with existing `Comment` and `WarningMsg` highlights in a separate per-instance namespace.
- No services started, dependencies added, files staged, or commits created.

## Spec Compliance Notes
- Projection validates every captured pane before clearing existing comment marks, including identity, window/buffer validity, buffer association, and review tab membership.
- Snapshot logical counts remain distinct from Neovim's empty display row; path-backed bounds come from the displayed buffer. Only stale anchors clamp, without target mutation.
- Blocks sharing an anchor are grouped in supplied order. Source text is never written, input comment tables are not retained, and the captured diff is detached.
- Side-by-side transitions own projection invalidation; TabClosed releases comment resources independently before invoking the existing handler, without forcing broader side-by-side teardown.
- Scope remains spec 002 only: no editor, save handling, commands, mappings, collection mutations, or orchestration wiring.

## Risks Or Follow-ups
- No outstanding verification blocker remains.

## Independent Verification

Before repair, the parent orchestrator completed test-runner session `ses_eb71d4fadffeOeCkuQCBc17g7f`: `just lint`, `just format`, `just format-check`, `just test`, and `git diff --check` all exited 0. All 318 tests passed: 68 unit, 190 integration, 60 functional, no failures or skips. Output: `.artifacts/002-independent-test.txt` and corresponding `.artifacts/002-independent-*.txt` static-gate logs. The repair implementer inspected the test log's three category summaries, which confirm those counts.

After repair, independent test-runner session `ses_eb7199e56ffe7iY0lhTgVZRR9O` repeated all five commands successfully (each exit 0). All 318 tests passed: 68 unit, 189 integration, 61 functional, no failures or skips. Logs: `.artifacts/002-repair1-independent-{lint,format,format-check,test,diff-check}.txt`.

## Repair Pass 1

Judge review required moving native `:tabclose!` out of integration coverage. The journey now lives in `tests/functional/comment_tab_cleanup_test.lua`, is registered in the functional registry, and has been removed from integration. Its notification, buffer-survival, annotation-removal, invalid-association, and repeated-cleanup checks are preserved; it additionally compares surviving marks to the pre-projection marks. The only production repair moves source-bound computation outside the comment loop, once per pane. Context and learnings reflect the functional boundary. Ordered static gates and post-repair full-suite delegation pass.
