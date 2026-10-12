# Implementation Learnings

Durable findings from verified implementation phases will be appended here.

## 2026-10-12 — Durable comments and asynchronous snapshots

Finding: text-comment add/reattach uses coroutine-based Git loading. `diffs.load_selected_view(..., true)` captures immutable text and fingerprint input; `selected_fingerprint_matches` verifies those captured bytes. Cancellation alone is insufficient: check active state, loaded comparison, progress identity and selection after yielding.

Impact: UI callers must enter a coroutine and preserve save-before-adopt semantics. Returned records are detached, and projections must not mutate authoritative progress.

Use in future specs: version-2 checkpoints require a comments array and shared `comments.validate`. Six session operations return a record (or true for deletion), otherwise nil/error. File notes accept current changed entries; text operations require the selected/presented file. Reattachment preserves ID/body/resolution and clears staleness. Use `---@cast` for mixed returns; binary Git fixtures require libuv byte writes rather than the text helper.

Source: `.agent-runs/001-comment-records/learnings-draft.md`, verified spec 001.
