# Learnings Draft: 004-comment-presentation

## Durable Findings
- Native quickfix list updates can reset the displayed drawer cursor, including while updating projections. Preserve actual window cursors around updates rather than treating the native quickfix index as the selected mapped row.
- `getqflist` with a positive `idx` filters returned items; do not request `idx = 1` while retrieving the complete presented list. Native `changedtick` plus detached item snapshots provides rejection of externally replaced rows, even when record IDs are reused.
- Pending attachment needs an identity token, not only a record ID, because text completion yields during Git/snapshot validation. Cancellation and selecting the same ID again must still invalidate the earlier request.
- To exercise that identity guard without mocks, start ranged `ReviewCommentAttach` against valid presented text, cancel and reselect the same comment with native `a` before yielding to the event loop. Keep loaded comparison, selected file and progress unchanged so those other currency guards cannot mask the regression. The repair-1 test proves unchanged checkpoint/list items/annotations, then successful fresh attachment to a different line; weakening the guard to compare IDs causes the obsolete completion to save and the test to fail.
- Accepted refresh renders snapshot-backed content and can replace a displayed worktree buffer. Annotation cleanup must track all previously annotated buffers, not merely the currently displayed pair.
- Lua table reconstruction can change JSON object field ordering even when decoded checkpoints are deeply equal. An unchanged restart should reuse its existing checkpoint instead of rewriting it; new/changed reconciled state must still save before presentation. Valid noncanonical JSON (such as leading whitespace) makes a redundant-write regression deterministic while retaining strict byte-preservation assertions.

## Repo Conventions Discovered
- Functional tests are globally sorted by name. `plugin_should_register_commands_when_setup_is_called` requires setup to be untouched; new configured-command journeys must sort after it (the `review_comments_should_*` names do so).
- Expected command rejections may throw through `vim.cmd` because error notifications become command errors; catch rejection without intercepting notifications and assert persisted state/buffer behavior instead.
- Asynchronous acwrite verification must wait for checkpoint adoption as well as an unmodified buffer. Real writes can appear clean before asynchronous saving has completed.

## Things Future Specs Should Know
- Comment presentation is disposable and centralized: session mutations update both owned lists and annotations after saving; `ReviewUi:update_review_comments` also refreshes the currently displayed annotations without switching the drawer.
- Quickfix buffer mappings must check list ownership and presentation on every action, because the native buffer is reused for unrelated lists. Cleanup removes only callbacks still owned by this instance.
- `comment_decorations` has its own per-instance namespace and tracked-buffer set; selection, refresh and cleanup must clear it without touching the diff namespace or user-buffer text.
- File-list row attachment changes a text record into a file note through the existing session reattachment path; by-ID editing remains available even when its file vanished. No new deliberate ceilings were introduced.
