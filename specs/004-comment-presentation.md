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

## Verification

- Through user commands in a real review, create comments, open `ReviewComments`, select and navigate to a text/file note, edit, delete, resolve/reopen, and reattach a stale note to a new location; restart and observe lasting state and updated virtual text. With only saved comments and no changed files, starting the review opens their list.
- Switch repeatedly between `ReviewFiles` and `ReviewComments` and inspect separate quickfix IDs/contexts/items, only one visible drawer, valid row-to-record actions, stable file viewed behavior and safety in the presence of an unrelated quickfix list. Exercise text on both sides, ranges, file notes, stale and resolved styling, selection changes, and cleanup of annotation extmarks without changing real buffer contents.
- Run `just lint`, then `just format` and `just format-check`, then `just test` (multiple affected cases).
