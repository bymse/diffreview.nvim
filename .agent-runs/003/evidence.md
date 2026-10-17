# Evidence: 003

## Final Independent Runtime Status

PASS after lifecycle repair. Independent test-runner session `ses_eb7043912ffegI62a39o4ok0Jb` ran `just lint`, `just format`, `just format-check`, `just test`, and `git diff --check`, each exit 0. All 335 tests passed: 68 unit, 201 integration, 66 functional, no failures or skips. Logs: `.artifacts/003-repair2-independent-{lint,format,format-check,test,diff-check}.txt`. This supersedes the pending handoff statuses and earlier failed revisions documented below. The real-editor trace established that restoring `bufhidden` at BufLeave preserves immediate hiding after a rejected quit, while native forced quit still discards without saving.

## Changed Files
- `lua/diffreview/ui/comment_editor.lua`: new explicit-target writable editor, save contracts, shared programmatic/native write path, and owned lifecycle handling.
- `lua/diffreview/ui/init.lua`: open/write/close facade, editor teardown on cleanup and owned-tab loss, and preservation of the pre-cleanup window when it survives.
- `lua/diffreview/ui/comment_decorations.lua`: expose the existing logical source-line count for editor validation without duplicating its empty-source rules.
- `lua/diffreview/ui/side_by_side.lua`: exclude comment-editor buffers from source-window recovery and recover above a focused editor rather than replacing it.
- `tests/integration/ui/comments/editor_tests.lua`, `saving_tests.lua`, and `editor_lifecycle_tests.lua`; `tests/integration/init.lua`.
- `tests/functional/comment_editor_write_test.lua`, `comment_editor_lifecycle_test.lua`; `tests/functional/init.lua`.
- `specs/CONTEXT.md`: add editor implementation and test paths to the Codebase Map. Existing approved spec/context gap clarifications and `.agent-runs/003/gap-review.md` were preserved.
- `.agent-runs/003/evidence.md` and `learnings-draft.md`.

## Tests Added Or Updated
- 12 integration tests covering explicit target shape, displayed source bounds (including real Git-backed path content, artificial empty rows, and information views), stale original ranges and exact bodies, bottom split/native-diff separation, quickfix whole-file saves, save identity rotation, deletion and blank normalization, handler failures/retries, detached callback targets, unchanged annotations, hidden draft reuse, clean replacement, forced cleanup, manual buffer loss, and source/origin recovery.
- 5 functional tests covering native `:w`, successful `:wq`, failed save/delete/thrown-handler `:wq` and retries (including failed creation), blank new-draft `:wq`, modified ordinary quit, forced quit followed by fresh reopen, clean quit, and native tab closure.
- Registered both new test categories in the existing registries. No test infrastructure or mocks were introduced.

## Primary Journey Verification
The final parent-run suite passed every integration and functional journey below, including the strengthened quit/hide regression.

- Normal range save — `open_comment_editor` / `write_comment_editor`; `saving_tests.lua::write_comment_editor_should_propagate_identity_and_exact_text_when_saving_repeatedly` asserts exact source target/text, identity propagation, an open unmodified editor, and unchanged projection.
- Quickfix whole-file save — public file drawer and open/write/close facade; `editor_tests.lua::open_comment_editor_should_save_whole_file_when_quickfix_has_no_selected_diff` asserts a side-less target, surviving entries/drawer, and origin focus.
- Native writes — real editor commands; `comment_editor_write_test.lua` asserts write-keeps-open, write-quit-closes, failed save/delete/throw aborts write-quit with retained modified body/identity, and successful retry.
- Delete/recreate — public write facade; `saving_tests.lua` asserts one delete with the latest identity, a normalized identity-free blank draft, no repeated blank handler call, and subsequent creation without an old identity.
- Ownership/recovery — public facade and real window APIs; `editor_lifecycle_tests.lua::open_comment_editor_should_retain_captured_draft_when_source_and_origin_are_lost` asserts that a diff displayed while the editor is focused does not replace its buffer, and same-target reuse ignores malformed replacement payloads before saving the captured target/body/identity through the original handler.
- Native discard — real `:quit` / `:hide` / `:quit!`; `comment_editor_lifecycle_test.lua::quit_should_protect_draft_and_forced_quit_should_discard_when_editor_is_modified` asserts protection without changing global hiding, retained modified content after non-discarding hide, zero handler calls, forced disposal, origin/source preservation, and a fresh blank reopen.

## Commands Run
- `git status --short` — PASS; initial changes were the approved spec/context clarifications and current gap-review directory.
- `just lint` (initial) — FAIL; eight test-only annotation/callable diagnostics. Fixed by using inferred malformed-request fixtures and function wrappers around native commands.
- `just lint && just format && just format-check && git diff --check` — PASS after those fixes.
- `just lint && just format && just format-check && git diff --check` (final source/test state) — PASS; LuaLS diagnosed 106 files with no problems, formatting/checking and whitespace checks exited 0.
- `git diff --stat`, `git diff --numstat`, focused production `git diff`, and `git status --short` — PASS; inspected scope and confirmed no staging/commits.
- Spec-specific content searches — PASS; no comments-model/controller require, comment file-writing path, or new command/mapping was found in the UI changes. The sole mapping search match is the unchanged quickfix `<CR>` binding.
- Implementer-local tests were deferred to the parent test-runner because the implementation session had no delegation tool. No CLI fallback, runtime probes, or direct test execution was performed by the implementer.
- Parent-run independent `just test` — FAIL before repair; `.artifacts/003-independent-tests.txt` reports 68/68 unit, 201/201 integration, and 65 functional passed with one functional failure at `comment_editor_lifecycle_test.lua:19` (ordinary quit unexpectedly succeeded).
- Repair documentation lookup: remote WebFetch/curl — FAIL (HTTP 403); `gh api` — FAIL (authentication unavailable). Read the pinned AppImage's packaged `options.txt`, `editing.txt`, `autocmd.txt`, and `vvars.txt` after documentation-only `--appimage-extract 'usr/share/nvim/runtime/doc'` in `/tmp/opencode` — PASS. The initial multi-prefix extraction attempt was rejected by the AppImage CLI. No editor process or test was started for this lookup.
- `just lint && just format && just format-check && git diff --check` (native lifecycle repair) — PASS; LuaLS diagnosed 106 files with no problems and all subsequent static gates exited 0.
- First repair was handed to the parent for delegated testing.
- Parent-run repair-1 independent `just test` — FAIL; `.artifacts/003-repair1-independent-test.txt` reports 68/68 unit, 201/201 integration, and 65/66 functional passed. Ordinary quit protection passed; immediate non-discarding hide failed at `comment_editor_lifecycle_test.lua:26`.
- Parent-delegated focused native diagnostics — PASS for the BufLeave restoration variant; `.artifacts/003-quit-trace.txt` establishes that BufWinLeave restoration permits unintended unload, while `.artifacts/003-quit-bufleave-trace.txt` records rejected quit, immediate hide retaining loaded/modified buffer 5 and its `draft` text, same-target reopen returning buffer 5, and forced quit unloading/wiping it with zero save callbacks.
- `just lint && just format && just format-check && git diff --check` (BufLeave repair) — PASS; LuaLS diagnosed 106 files with no problems and all subsequent static gates exited 0. No direct tests were run by this implementer.
- Full `just test` after the BufLeave production change — PASS through independent test-runner session `ses_eb7043912ffegI62a39o4ok0Jb`, 335/335, exit 0. Ordered static gates also exited 0; logs `.artifacts/003-repair2-independent-*.txt`.

## Results
- Static gates and the final parent-delegated complete `just test` gate pass after repair. All 17 added cases and the full regression suite pass: 68 unit, 201 integration, 66 functional.
- Inputs and callback targets are copied. Same-target reuse precedes replacement payload and current-presentation validation. Existing records preserve original coordinates. Successful writes alone update identity/modified state; blank existing drafts delete and blank new drafts call no handler.
- Native writes raise an actual autocmd error on failure rather than notifying or manually closing. The independent suite passed the native write/write-quit failure and retry cases.
- Native lifecycle repair: `acwrite` plus hiding does not itself require a modified split to reject `:quit`. The original QuitPre marker treated any successful quit as discard, incorrectly conflating ordinary hiding with force. QuitPre now temporarily sets only this buffer's hiding policy to `unload` so native quit performs its modified-buffer check; BufLeave restores the normal policy before native close chooses unload, and a scheduled reset handles rejected quits without departure. BufWinLeave was too late, as established by the first diagnostic trace. The production repair changes only the restoration event from BufWinLeave to BufLeave, with a local explanation of the ordering requirement. Clean hiding releases the editor, modified hiding retains it, and actual native unload releases forced-discard resources. All substantive functional assertions, including immediate hide/reopen after failed quit, are unchanged.

## Spec Compliance Notes
- Implements only approved spec 003, including the gap clarifications. No model/controller wiring, commands/bindings, membership inference, persistence, automatic annotation refresh, or refresh deferral.
- Existing read-only scratch projections are unchanged. Editor buffers are separately tagged, unlisted, swapless, writable `acwrite` buffers with a `diffreview://` name and non-body target context.
- Source recovery edits are limited to editor exclusion and recovery placement. Existing display focus behavior is retained.
- No intentional feature ceiling was accepted; there is no new dependency or speculative abstraction.

## Risks Or Follow-ups
- No outstanding runtime verification blocker remains. Final independent tests and quality judge passed.

## Quality Review

Judge session `ses_eb702fa89ffey7Da9z34GnVEyj`: PASS. Compliance, architectural fit, and simplicity 5/5; test quality, regression risk, and maintainability 4/5. No required fixes or weakened existing behavior assertions found.
