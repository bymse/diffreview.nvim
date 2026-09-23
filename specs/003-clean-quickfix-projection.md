# Spec 003: Clean The Quickfix Projection

## Goal

Add ownership-validated, idempotent quickfix cleanup and transactional display rollback so `ReviewUi` removes only its own projection and preserves prior or unrelated editor state after failures.

## Prerequisites

Spec 002 must be complete.

## Context

Read `specs/CONTEXT.md` for UI ownership decisions, cleanup constraints, and existing quickfix and side-by-side cleanup patterns.

## Tasks

1. Add the internal interface `cleanup(id: quickfix_id|nil, context: QuickfixContext): nil` to `lua/diffreview/ui/quickfix.lua`. Fetch the identified list context and require exact equality of `plugin`, `view`, and `instance_id` before mutation.
2. Empty only the validated owned list because Neovim cannot free one quickfix history entry independently. Quickfix-window handling is limited to windows in the current tabpage, matching the scope in which `copen` displays the projection. Identify each current-tab quickfix window by stable window ID and determine its displayed quickfix list by stable list ID; close only windows displaying the owned list. Never inspect or alter windows in other tabpages, free all history, navigate away from or mutate unrelated lists, or blindly close a foreign quickfix window.
3. Make missing, stale, already-cleaned, or context-mismatched identities safe no-ops. Preserve unrelated list contents, titles, contexts, history ordering, and displayed windows in every cleanup path.
4. Extend `ReviewUi:cleanup()` in `lua/diffreview/ui/init.lua` to clean both existing side-by-side resources and the owned quickfix projection, then clear its stored quickfix identity. Cleanup remains idempotent and safe after partial acquisition.
5. Validate a stored ID and its exact ownership context before every display update. `ReviewUi:show_review_files` clears `self.quickfix_id` before delegating when the stored ID is missing or its context differs, then creates a replacement without mutating the foreign list. A failed replacement leaves the facade identity nil; a failed update of a valid owned list retains that owned ID. Retain and update the existing list only when ownership matches.
6. Make quickfix display transactional. Capture an existing owned list’s items, title, context, and `quickfixtextfunc` by stable list ID; capture the previously selected list’s stable ID and history number; and capture every current-tab quickfix window’s stable window ID plus displayed list ID before mutation. If display fails, restore an existing owned list’s captured properties; for a newly created list, empty it and leave `ReviewUi.quickfix_id` nil because Neovim cannot remove one history entry. Restore the previously selected valid list when selection changed. Never close a pre-existing quickfix window; restore each captured current-tab quickfix window to its prior displayed list instead. Close only an exact quickfix window opened by the failing display call when no quickfix window existed in the current tab beforehand, and preserve all foreign lists, other current-tab windows, and every other tabpage. Rollback is best effort: protect each restoration step so later steps still run, preserve the original display error as the error observed by the caller, and do not replace it with a rollback error.
7. Extend `tests/integration/ui/quickfix_tests.lua` with owned cleanup, foreign-context preservation, cleanup when the owned list is not current, stale and foreign stored-ID replacement, conditional current-tab window closure, repeated cleanup, partial-acquisition cleanup, and rollback after failures occurring during list selection and after quickfix opening. Assert the facade identity rules for failed replacement and failed owned-list update. Assert both window rollback cases: a pre-existing current-tab quickfix window remains open with its prior list, while an exact window newly opened by the failing call is closed; quickfix windows in other tabpages remain untouched.
8. Inject deterministic display failures by temporarily replacing the relevant Neovim function or command callable inside each test and restoring it afterward. For selection rollback, fail the targeted `cnewer` or `colder` command after list mutation. For window rollback, wrap the targeted `botright copen` call, invoke the original command first, then raise the injected error so rollback observes the opened window. Use narrow predicates so rollback commands can execute, and restore every patched callable even when the assertion fails. Do not add a production dependency-injection interface solely for these tests.
9. Keep `tests/integration/init.lua` unchanged unless coverage is split into a new test module; if split, register the new module there. Follow the repository’s lowercase snake-case test naming convention.

## Verification

1. Run `just lint` and fix every LuaLS diagnostic for affected Lua code.
2. Run `just format`, then `just format-check`.
3. Run focused cleanup and rollback cases while developing, including `just test-integration cleanup_should_empty_owned_list_and_close_only_owned_current_tab_window`, `just test-integration show_review_files_should_restore_existing_list_when_selection_fails`, `just test-integration show_review_files_should_restore_preexisting_window_when_open_fails`, and `just test-integration show_review_files_should_close_new_window_when_open_fails`.
4. Run `just test-integration` to cover quickfix and side-by-side ownership interactions.
5. Run `just test` as the final regression gate because multiple cleanup and rollback behaviors are affected.
