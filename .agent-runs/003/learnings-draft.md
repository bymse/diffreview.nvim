# Learnings Draft: 003

## Durable Findings
- Logical source bounds already exist in `comment_decorations.source_line_count`; editor validation can reuse those rules for path-backed empty files and artificial empty-snapshot rows instead of duplicating them.
- Same-target identity comparison must precede replacement payload and presentation checks. A surviving owned draft captures its target, handler, identity, path, and origin independently of the selected diff and source-window lifetime.
- Source-window ownership cannot rely only on a historical window tag: the buffer currently displayed there must not be a comment editor. Initial presentation from a quickfix-origin editor also needs a separate source split.
- The independent suite demonstrated that `acwrite` with a hiding policy can allow ordinary `:quit` to hide a modified split. A QuitPre marker alone therefore cannot identify forced discard: treating a subsequent BufHidden event as force loses ordinary drafts. Neovim's packaged docs specify that forced quit unloads the buffer and that `hidden` is global/default-on; keep hiding versus unloading as distinct lifecycle boundaries without changing global editor options.
- Parent-run native traces establish that restoring a temporary buffer-local hide policy at BufWinLeave is too late to prevent unloading during an immediate hide after rejected quit. Restoring at BufLeave retains the loaded modified buffer and exact draft text, permits same-buffer reopen, and still allows forced quit to unload/wipe with zero save callbacks. This ordering is verified in `.artifacts/003-quit-bufleave-trace.txt` against the pinned Neovim.

## Repo Conventions Discovered
- The comment projection fixtures are sufficient for direct-facade functional flows as well as integration coverage; real save callbacks can record requests without intercepting production components, notifications, or editor APIs.
- LuaLS treats `vim.cmd` as a callable table rather than a function suitable for `pcall`; wrap native commands in functions. Assign malformed API fixtures to inferred locals to test runtime validation without disabling type diagnostics.
- Public open/write/close tests belong in integration tests; native write/quit/tab-close commands belong in functional tests and both require explicit registry entries.

## Things Future Specs Should Know
- `open_comment_editor` receives its handler per request; no controller dependency was added. Projection refresh remains an explicit caller responsibility after saves.
- Comment editors have a separate `diffreview_comment_editor_owner` buffer tag and use `acwrite`, not the locked projection scratch-buffer path. Native close cleanup is deferred outside BufHidden/BufUnload, while public close and explicit UI teardown discard synchronously.
- Parent-run suites exposed ordinary-quit protection and then immediate-hide retention. The focused diagnostic verifies restoring the temporary buffer-local quit policy at BufLeave, rather than BufWinLeave. Production uses that event change; final independent verification passes all 335 tests (68 unit, 201 integration, 66 functional), including native write/quit/hide regressions.
