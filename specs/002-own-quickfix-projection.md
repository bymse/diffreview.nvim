# Spec 002: Own The Quickfix Projection

## Goal

Make each `ReviewUi` instance own and update its quickfix projection without exposing list identity to orchestration callers.

## Prerequisites

None. If Spec 001 has already moved the shared model file, use `diffreview.diff_view_model` annotations; otherwise avoid changes that conflict with that move.

## Context

Read `specs/CONTEXT.md` for UI ownership decisions and existing quickfix projection patterns.

## Tasks

1. Extend `ReviewUi` in `lua/diffreview/ui/init.lua` with `quickfix_id: quickfix_id|nil` and `quickfix_context: QuickfixContext`. `QuickfixContext` has the exact fields `plugin: 'diffreview'`, `view: 'review_files'`, and `instance_id: integer`, using the existing UI instance identity rather than a new global ownership mechanism.
2. Change the public facade to `ReviewUi:show_review_files(files: ChangedFileViewModel[]): nil` so callers neither pass nor receive a quickfix ID. Remove the old return annotation and value, update every caller, reuse the stored list on later displays, and commit a newly returned low-level ID only after display succeeds.
3. Adapt `lua/diffreview/ui/quickfix.lua` around the internal interface `show_review_files(id: quickfix_id|nil, context: QuickfixContext, files: ChangedFileViewModel[]): quickfix_id`. Preserve existing entry text, unviewed-before-viewed ordering, `user_data.file_id`, stable-ID updates, list selection, and bottom quickfix opening behavior.
4. Store the returned stable list ID after a successful display and reuse it on later calls so updates continue to target the same projection even when unrelated quickfix lists are added to history. Store the exact instance ownership context in the list on every create or update.
5. Extend `tests/integration/ui/quickfix_tests.lua` using its existing list reset, summary fixture, and displayed-line helpers. Update existing callers for the no-return ReviewUi interface and cover list creation, exact instance context, summary rendering and ordering, same-list updates amid unrelated history, and preservation of unrelated list contents and history during successful display.
6. Keep `tests/integration/init.lua` unchanged unless coverage is split into a new test module; if split, register the new module there. Follow the repository’s lowercase snake-case test naming convention.

## Verification

1. Run `just lint` and fix every LuaLS diagnostic for affected Lua code.
2. Run `just format`, then `just format-check`.
3. Run focused quickfix integration cases with `just test-integration <exact_test_name>` while developing.
4. Run `just test-integration` to cover the complete quickfix projection behavior.
5. Run `just test` as the final regression gate because multiple quickfix projection cases and shared UI annotations are affected.
