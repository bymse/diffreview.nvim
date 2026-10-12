# Learnings Draft: 001-comment-records

## Durable Findings
- Git content loading uses coroutine-based `diffreview.async.system`. Session text-comment add/reattach methods yield and return their result when resumed; future editor callers must enter a coroutine, as existing start/selection/refresh do.
- `diffs.load_selected_view(..., true)` returns immutable worktree text plus fingerprint input. Passing that input to `selected_fingerprint_matches` validates the same captured bytes; old and explicit-target content are already Git snapshots.
- Async comment operations must compare the captured active state, loaded comparison, progress and selected file after loading. Checking cancellation alone does not protect against concurrent deletion, progress updates or selection changes.
- Version-2 checkpoints require a comments array. `comments.validate` is shared by storage load/save, and `review_progress.reconcile` deep-copies comments unchanged in this phase.
- Comment operation results are detached from adopted state, including anchor arrays. Future UI projections should not mutate session-owned records.
- `vim.fn.mkdir` can throw for a blocked directory path; storage must convert this into a recoverable error before callers adopt candidate state.

## Repo Conventions Discovered
- Tests execute inside coroutines and can exercise asynchronous session/module operations with real temporary Git repositories; nested coroutines allow cancellation/concurrency tests without intercepting APIs.
- Use `---@cast` for return-type narrowing around mixed-result helpers. StyLua may relocate an inline `--[[@as ...]]` beside a comma in a multiple return, invalidating the intended annotation on the next lint run.
- `helpers.git_repo:write_file` is a text-line helper, not a binary byte writer. Binary fixtures use real libuv open/write/close, as nearby content/fingerprint tests do.
- The canonical gates are `just lint`, `just format`, `just format-check`, `just test`; tests are registered explicitly in category `init.lua` files.

## Things Future Specs Should Know
- The six public comment methods are on `ReviewSession`: add/edit/delete/resolve/reopen/reattach. They save complete candidate progress before adoption and return a record (or true for deletion), otherwise nil plus an error.
- No comment presentation or editor commands exist yet. File-note locations accept any current changed entry; text-location operations enforce the selected/presented file, snapshot consistency, supported text side and inclusive bounds.
- Reattachment can switch file, side or note kind, removes obsolete text fields, clears staleness and preserves ID/body/resolution. Content reconciliation and comment-only startup remain explicitly deferred to spec 002.
