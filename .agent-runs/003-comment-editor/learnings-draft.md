# Learnings Draft: 003-comment-editor

## Durable Findings
- Session text-anchor mutation must verify both the fingerprint-validated immutable Git/worktree snapshot and the actual buffer in the owned side window. Disk consistency alone misses unsaved displayed edits; window ownership alone misses replaced buffers.
- `BufWinLeave` cleanup must wait for tab-closure ownership resolution. Ordinary/forced tab closure can hide a modified listed acwrite buffer; detach it rather than deleting it. Capture whether it was already detached when leaving so a later explicit close cancels the detached draft without confusing original tab teardown with cancellation.
- A pending coroutine save must block selection, refresh, stop, and editor replacement; cancellation also needs a buffer-validity/ownership guard after asynchronous snapshot loading. Changed ticks preserve modifications made while a successful write is pending.
- Pending-save tests must wait for observable checkpoint adoption, not merely an unmodified buffer: a clean buffer can still have an asynchronous write in flight. Native `:setlocal nomodified` before a real text-anchor write separates pending-save guards from dirty-buffer guards without mocking collaborators.

## Repo Conventions Discovered
- Native error notifications can surface as synchronous `vim.cmd` failures inside command/autocmd execution. Expected-failure tests use `pcall` and assert observable buffers/checkpoints rather than notification wording.
- The bundled Neovim Markdown ftplugin starts Tree-sitter unconditionally, but the isolated test runtime lacks the Markdown parser. The plain comment editor uses the native `text` filetype; rich Markdown rendering is not required by the current contract.
- Command-capable functional journeys must use the configured plugin commands and native file-list selection, asserting observable buffers and saved checkpoints rather than session state. Only the spec-required public edit-by-ID entry point, which has no command yet, warrants narrowly scoped module-driven editor tests; module-only behavior otherwise belongs in integration coverage.

## Things Future Specs Should Know
- `ReviewSession:open_comment_editor(first?, last?)` derives creation context from the actual owned UI; `ReviewSession:edit_comment_by_id(id)` accepts stale records without navigation and handles editor focus/replacement. Future comment-list actions should use the latter, not duplicate lifecycle logic.
- Presented file identity travels explicitly through `display_diff_side_by_side`/`refresh_selected_diff`; `comment_context` distinguishes owned old/current text and information views, while `comment_text_matches` validates the side's actual displayed buffer.
- The editor's target and active-session owner stay pinned while selected files change. Once saved, subsequent writes edit its ID; blank deletion clears the ID. Clean creation editors that outlive a refreshed comparison reject new writes rather than retargeting their anchors.
