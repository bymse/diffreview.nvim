# Implementation Learnings

Durable findings from verified implementation phases will be appended here.

## 2026-10-12 — Durable comments and asynchronous snapshots

Finding: text-comment add/reattach uses coroutine-based Git loading. `diffs.load_selected_view(..., true)` captures immutable text and fingerprint input; `selected_fingerprint_matches` verifies those captured bytes. Cancellation alone is insufficient: check active state, loaded comparison, progress identity and selection after yielding.

Impact: UI callers must enter a coroutine and preserve save-before-adopt semantics. Returned records are detached, and projections must not mutate authoritative progress.

Use in future specs: version-2 checkpoints require a comments array and shared `comments.validate`. Six session operations return a record (or true for deletion), otherwise nil/error. File notes accept current changed entries; text operations require the selected/presented file. Reattachment preserves ID/body/resolution and clears staleness. Use `---@cast` for mixed returns; binary Git fixtures require libuv byte writes rather than the text helper.

Source: `.agent-runs/001-comment-records/learnings-draft.md`, verified spec 001.

## 2026-10-12 — Reconciliation and presentation lifetime

Finding: all present text-comment files need immutable fingerprint-validated views. Exact anchors plus recorded available neighbors determine attachment; previously absent neighbors may appear after movement. A third selected-view result classifies submodules only after supported-side reads succeed, and Gitlink fingerprints use metadata OIDs.

Impact: refresh, including preloaded refresh, is coroutine-based and returns acceptance rather than completion. Stale records can recover automatically with resolution unchanged. An empty comparison can remain active with comments.

Use in future specs: replace displayed disposable buffers before deleting snapshots so cleanup cannot close the owning review tab. Preserve the replacement buffer during cleanup. Command tests can seed validated checkpoints and observe public commands; wait for a new owned quickfix ID on restart. Resolve abbreviated Git OIDs before manipulating loose-object fixtures.

Source: `.agent-runs/002-anchor-reconciliation/learnings-draft.md`, verified spec 002 and command-driven lifecycle regression.

## 2026-10-12 — Owned editor lifecycle

Finding: text anchors require actual owned-buffer text matching in addition to immutable snapshot/fingerprint validation. `BufWinLeave` cleanup must allow tab-closure ownership resolution; dirty listed acwrite buffers detach rather than disappear. Pending saves block selection/refresh/stop/replacement and guard owner/buffer validity after yielding.

Impact: comment-list editing should reuse `edit_comment_by_id(id)` and creation should reuse `open_comment_editor(first?, last?)`. Targets and owners stay pinned; repeat writes edit the saved ID. Blank deletion clears that ID. Presented identity is explicit on UI display/refresh.

Use in future specs: functional tests use configured commands, native selection, buffers and checkpoints; narrowly scoped by-ID tests cover the public entry point lacking a command. Wait for checkpoint adoption, not merely an unmodified buffer, for async saves. Plain `text` filetype avoids isolated-runtime Markdown parser requirements. Summarize verification and link captured output instead of copying transient progress counters.

Source: `.agent-runs/003-comment-editor/learnings-draft.md`, verified spec 003.
