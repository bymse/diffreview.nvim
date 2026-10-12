# Spec 004: Comment List and Inline Presentation

## Goal

Make local comments discoverable and manageable with annotations and an independent comment quickfix list that shares the existing bottom drawer.

## Prerequisites

Specs 001, 002 and 003 complete.

## Context

Read `specs/CONTEXT.md` for the approved dual-list drawer, stale/resolve semantics, and review-tab ownership. This implements the plan's discovery and management phase.

## Tasks

- Extend `lua/diffreview/ui/quickfix.lua` with independent ownership for a comment list, including its own ID, context, presented comment IDs, row validation, buffer-local mappings and cleanup. Preserve file-list identity, ordered progress, and selection behavior. Switching lists uses the same bottom quickfix drawer while keeping the inactive list independent; refreshing one must not overwrite the other's items or act on unrelated user lists.
- Extend `lua/diffreview/ui/init.lua` (`ReviewUi`) and `lua/diffreview/review.lua` (`ReviewSession:start`, `refresh`, `select_file` and comment mutation paths) to toggle/update the comment list, navigate a valid comment to its file and side when present, and expose edit/delete/resolve/reopen and stale reattachment from its selected row. Selecting a stale entry for reattachment, navigating to a new valid review line/range or file-list row, then explicitly completing the attachment must preserve ID/body/resolution; abandoned attachment changes nothing. When starting with saved comments but no changed files, show the comment list immediately. Register `ReviewComments` (list toggle) and `ReviewCommentAttach` (complete pending reattachment at the review location) in `lua/diffreview/init.lua` (`setup`).
- Create `lua/diffreview/ui/comment_decorations.lua` for virtual-text rendering of line/range comments and file-level notes on displayed review content; integrate with `lua/diffreview/ui/side_by_side.lua` without disturbing diff highlights from `lua/diffreview/ui/decorations.lua`. Display stale and resolved status wherever a comment can be drawn; comments on vanished files remain in the list. Use a namespace separate from diff highlights, clear old annotations on file selection, refresh, stop and UI cleanup, and never modify a user-owned buffer's content.
- Add focused drawer/ownership coverage in `tests/integration/ui/comment_quickfix_tests.lua` and annotation coverage in `tests/integration/ui/comment_decorations_tests.lua`; register new suites in `tests/integration/init.lua`. Add command/key-driven journeys in `tests/functional/review_comments_test.lua` and register in `tests/functional/init.lua`; use existing review UI helpers and real editor/Git fixtures.

## Interaction and Projection Contract

- On the owned comment-list buffer, `<CR>` navigates, `e` edits through `edit_comment_by_id`, `d` deletes, `r` toggles resolved/reopened, and `a` selects a stale record as pending attachment. Validate current list ownership and the presented row/record on every action; bindings on unrelated or replaced lists must perform no mutation. Exact list formatting is flexible, but include display path, file/text location and side, body preview, and independently visible stale/resolved status.
- `ReviewCommentAttach` accepts the same optional line range as `ReviewComment` and completes at `comment_context`; `ReviewCommentAttach!` cancels pending attachment without mutation. Attachment can change file, side or note kind. A new `a` replaces the pending source, refresh cancels it, source deletion cancels it, and stop/tab closure cancels it. Failed completion retains the pending source for retry; successful completion clears it. Abandoning a pending source never changes persisted data.
- Valid text navigation selects its file and focuses the owning side window at the start line; file-note navigation selects its file and focuses the main review window. Stale entries may select a present file but must not position at an obsolete text line; vanished files leave selection unchanged and remain editable/manageable. Navigation never changes viewed progress. Unavailable sides cannot be treated as valid text destinations.
- Reject comment-list management and attachment actions while an editor is dirty or saving, preserving draft and checkpoint. Editor writes remain allowed through their existing mutation path. Clean editors may remain open, but deleting or reattaching their pinned record must close/invalidate that editor first after a successful mutation so later writes cannot resurrect or silently retarget it. Selection while saving follows the existing guard.
- Reuse `edit_comment_by_id`, `comment_context`, `comment_text_matches` and session mutations. Text attachment runs in coroutine context with existing snapshot/currency guards. All successful mutation paths, including editor writes, and accepted refreshes update both disposable lists and annotations; updating an inactive list never opens/switches the drawer. Failed saves leave both projections unchanged.
- Preserve the currently visible owned drawer across refresh. A refresh/start to no changed files with retained comments shows the comment drawer, including from a previously closed drawer. Toggling files/comments uses one bottom drawer and maintains separate list identities; unrelated lists remain untouched.
- Annotations show body preview and resolved state at valid text ranges or file-note positions without changing buffer contents. Stale text records must never be drawn at obsolete line numbers; if their file is displayed, show a clearly stale file-level annotation instead. Use a separate namespace and clean every previously annotated buffer on selection, refresh, stop and tab closure without erasing diff decorations.
- Add observable rejection coverage for invalid/replaced rows and unrelated mappings, dirty/pending conflicts, canceled/failed attachments, refresh to comment-only state, tab cleanup and stale annotations that cannot imply an obsolete attachment. Split large functional suites by behavior.

## Verification

- Through user commands in a real review, create comments, open `ReviewComments`, select and navigate to a text/file note, edit, delete, resolve/reopen, and reattach a stale note to a new location; restart and observe lasting state and updated virtual text. With only saved comments and no changed files, starting the review opens their list.
- Switch repeatedly between `ReviewFiles` and `ReviewComments` and inspect separate quickfix IDs/contexts/items, only one visible drawer, valid row-to-record actions, stable file viewed behavior and safety in the presence of an unrelated quickfix list. Exercise text on both sides, ranges, file notes, stale and resolved styling, selection changes, and cleanup of annotation extmarks without changing real buffer contents.
- Run `just lint`, then `just format` and `just format-check`, then `just test` (multiple affected cases).
