# Learnings Draft: 002-anchor-reconciliation

## Durable Findings
- Reconciliation needs validated immutable views for all present files with text comments, not just the selected file. Fingerprints gate snapshot consistency; exact captured ranges and recorded available neighbors determine attachment.
- Available-neighbor matching does not require a previously absent neighbor to remain absent. A unique move captures its newly available neighbors for subsequent reconciliation. Failed matches preserve the last-known location and context.
- `diffs.load_selected_view(..., true)` now returns a third result identifying metadata-confirmed unsupported submodule views only after supported-side reads succeed. Arbitrary error views remain candidate failures. Worktree Gitlink fingerprints use collector OIDs instead of file-byte reads.
- Preloaded and ordinary session refresh both enter a coroutine. The refresh boolean acknowledges request acceptance; consumers needing the final result must wait for request completion.
- A persisted checkpoint containing comments can activate an empty comparison. All missing-entry comments remain stale and available in structured state; comment-only presentation is still deferred.
- Deleting scratch buffers while they remain displayed can close their windows and the review tab, invoking the normal tab-closed stop handler. When clearing a selected view but retaining an active review, replace the main window's buffer before deleting obsolete snapshots, and keep the replacement out of the cleanup deletion set.

## Repo Conventions Discovered
- Existing refresh fixture checks need to await `refresh_request == nil` when supplying preloaded candidates now that snapshot loading can yield.
- Real Git fixtures can model text-to-submodule transitions using `update-index --cacheinfo` with a commit OID; filesystem fixtures can exercise rejected reads and atomic replacement without mocks.
- Collector raw-diff OIDs can be abbreviated. A fixture manipulating loose Git objects must resolve the full OID with `git rev-parse` before constructing `.git/objects/<prefix>/<suffix>` paths.
- Command-level reconciliation tests can seed a validated version-2 checkpoint using `review_progress.reconcile` and `storage.save`, then observe actual `ReviewStart`/`ReviewRefresh`/`ReviewStop` behavior via saved records and native editor state without exposing or intercepting the configured session.
- On empty restart, waiting for zero quickfix items alone can match the stopped review's old empty list. Require a new owned review list ID to prove startup presentation has completed.

## Things Future Specs Should Know
- Keep async loading and currency checks at the session boundary; pass immutable views into the comments domain. Reuse validated selected snapshots instead of reading the same file twice within one refresh.
- Comment projections should expect stale records to automatically reattach on explicit refresh/restart, with manual resolution unchanged. Stale locations are retained for discovery, not valid display positions.
- The functional saved-comment fixture now covers selected snapshot panes becoming an empty comparison with the drawer closed, tab/main-window survival, native-diff release, deletion of obsolete snapshots, and refresh reattachment without restart. This distinguishes state persistence from a still-active session and reusable presentation.
