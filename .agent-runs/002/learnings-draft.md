# Learnings Draft: 002

## Durable Findings
- Pane associations must capture window and buffer identity at presentation time: snapshot buffers can be reused, deleted content puts old source in main, rename-only views hide old source, and information buffers have no source side.
- Logical snapshot line counts must be captured separately from buffer row counts because an empty snapshot still has Neovim's artificial first row. Path-backed bounds should be read from the displayed buffer, not the diff snapshot/model.
- Compute source bounds once per pane per projection, not for every comment; path-backed counting reads the displayed buffer's lines.
- Grouping virtual lines per anchor preserves caller order without depending on ordering between multiple extmarks at one row.

## Repo Conventions Discovered
- Side-by-side transitions are the ownership boundary for presentation invalidation. Keep comment cleanup isolated from native diff reset, statuslines, and the existing diff-decoration namespace.
- The TabClosed handler is caller-supplied and need not call UI cleanup; owned comment resources must be cleared independently before that notification. Avoid recursive full teardown in that callback.
- UI integration tests can identify actual source panes through tab windows and source text, then inspect all real extmark details without relying on private projection state or replacing editor APIs.
- Native user-command journeys such as `:tabclose!` belong in functional tests even when setup calls the public UI facade directly. `tests/functional/comment_tab_cleanup_test.lua` covers this boundary without importing integration-only helpers.

## Things Future Specs Should Know
- Public display now accepts an optional fourth explicit file ID; refresh accepts an optional third ID. Omission intentionally produces an unassociated presentation, including after a previously associated display.
- `clear_comments` preserves the current association; display, refresh, clear-selected-diff, cleanup, and owned tab closure invalidate it. Failed projection validation leaves the previous projection intact for explicit cleanup.
- Comment projection is caller-driven and retains no comment records. Future editor save handling must not implicitly redraw annotations or turn clamped stale display rows into saved target coordinates.
