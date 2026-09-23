# Spec 003: Clean The Quickfix Projection

## Goal

Add ownership-validated, idempotent quickfix cleanup and transactional display rollback so `ReviewUi` removes only its own projection and preserves prior or unrelated editor state after failures.

## Prerequisites

Spec 002 must be complete.

## Context

Read `specs/CONTEXT.md` for UI ownership decisions, cleanup constraints, and existing quickfix and side-by-side cleanup patterns.

## Tasks

1. Add the internal interface `cleanup(id: quickfix_id|nil, context: QuickfixContext): nil` to `lua/diffreview/ui/quickfix.lua`. Fetch the identified list context and require exact equality of `plugin`, `view`, and `instance_id` before mutation.
2. Empty only the validated owned list because Neovim cannot free one quickfix history entry independently. Close a quickfix window only when that window is displaying the owned list; never free all history, navigate away from or mutate unrelated lists, or blindly close a foreign quickfix window.
3. Make missing, stale, already-cleaned, or context-mismatched identities safe no-ops. Preserve unrelated list contents, titles, contexts, history ordering, and displayed windows in every cleanup path.
4. Extend `ReviewUi:cleanup()` in `lua/diffreview/ui/init.lua` to clean both existing side-by-side resources and the owned quickfix projection, then clear its stored quickfix identity. Cleanup remains idempotent and safe after partial acquisition.
5. Validate a stored ID and its exact ownership context before every display update. If the ID no longer exists or identifies a foreign context, clear the stale identity and create a new owned list without mutating the foreign list; retain and update the existing list only when ownership matches.
6. Make quickfix display transactional. Capture the prior owned-list properties, current quickfix selection, and whether a quickfix window already exists, including its window ID and displayed list. If display fails, restore an existing owned list’s previous items, title, context, and text function; for a newly created list, empty it and leave `ReviewUi.quickfix_id` nil because Neovim cannot remove one history entry. Restore the previously selected valid list when selection changed. Never close a pre-existing quickfix window; restore its prior displayed list instead. Close only the exact quickfix window opened by the failing display call when no quickfix window existed beforehand, and preserve all foreign lists and other windows.
7. Extend `tests/integration/ui/quickfix_tests.lua` with owned cleanup, foreign-context preservation, cleanup when the owned list is not current, stale and foreign stored-ID replacement, conditional window closure, repeated cleanup, partial-acquisition cleanup, and rollback after failures occurring after list mutation and after selection/window work begins. Assert both rollback cases: a pre-existing quickfix window remains open with its prior list, while a window newly opened by the failing call is closed.
8. Inject deterministic display failures by temporarily replacing the relevant Neovim function or command callable inside each test and restoring it afterward. Do not add a production dependency-injection interface solely for these tests.
9. Keep `tests/integration/init.lua` unchanged unless coverage is split into a new test module; if split, register the new module there. Follow the repository’s lowercase snake-case test naming convention.

## Verification

1. Run `just lint` and fix every LuaLS diagnostic for affected Lua code.
2. Run `just format`, then `just format-check`.
3. Run focused cleanup and rollback cases with `just test-integration <exact_test_name>` while developing.
4. Run `just test-integration` to cover quickfix and side-by-side ownership interactions.
5. Run `just test` as the final regression gate because multiple cleanup and rollback behaviors are affected.
