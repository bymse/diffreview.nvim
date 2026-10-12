# Plan: Local Review Comments

Status: Approved

## Outcome
- **Goal:** Reviewers can write, view, and manage durable comments from the existing review UI, without publishing them.
- **Non-goals:** Remote publishing, Markdown export, automatic refresh, comments in files outside the displayed review, and support for existing checkpoint files.
- **Success:** Comments on review files survive stopping and restarting a review, remain discoverable when files change or disappear, and can be edited, deleted, resolved, reopened, or manually reattached.

## Runtime Change
1. `ReviewComment` opens a temporary editable buffer for the current review line, visual line range, or selected file-list entry; non-text review views support file-level comments.
2. Writing that buffer commits the comment to validated review state; writing empty text removes an existing comment, while closing without writing discards edits.
3. Comments appear as virtual text on displayed review files and in their own quickfix list, separate from the changed-file quickfix list; the two lists use the same bottom drawer, with only one open at a time. Resolved comments remain visible with their status, and the comment list offers navigation and management actions.
4. On manual refresh or review restart, uniquely matching line context keeps a text comment attached despite line movement; unmatched comments remain stored and visibly stale until manually reattached, resolved, or deleted. File-level comments remain attached while their file identity is present and become stale when it disappears.

## Approved Boundaries
- **Approach:** Extend the existing authoritative review checkpoint with local comments and derive editor buffers, virtual text, and the comment list from it; save each completed operation before presenting it as committed.
- **Constraints:** Keep the current Git-specific storage directory and source/baseline/target review identity; change the checkpoint format in place without migration. Limit creation to files presented by the side-by-side review UI, including unchanged lines on either visible side, text line ranges, file-level notes, and file-level notes on non-text views. Do not enable the unfinished inline view.
- **Reuse and additions:** Reuse review-session orchestration, checkpoint persistence, side-by-side content, and the native quickfix drawer; add a comment model, a separate comment quickfix list, and editor/decorations for the local lifecycle. Store only local comment data, with no speculative publication fields.
- **Rejected:** Keeping comments solely in extmarks or editor buffers would lose them across sessions and make stale recovery unreliable.
- **Open questions:** none

## Phases

### 1. Durable local comment state
- **Behavior:** Comments retain stable identity, content, file/side/location and manual resolution state across review restarts; refresh preserves uniquely matched anchors and retains unmatched or disappeared-file comments as stale, including when no changed files remain.
- **Boundary:** Review state, persistence, comparison content, and refresh reconciliation.
- **Depends on:** none.
- **Proof:** Real-repository checks demonstrate create/edit/delete/resolve/reopen/reattach persistence, changed and moved line matching, ambiguous or missing anchors, rejected corrupt state, and retention of comments in an otherwise empty comparison.

### 2. Comment writing in the review UI
- **Behavior:** `ReviewComment` creates line, range, or file-level comments from the displayed review or file drawer, and an editor writes changes only on explicit save; manual refresh rejects an unsaved editor without discarding its contents.
- **Boundary:** Review commands, session lifecycle, and comment editor in the owned review tab.
- **Depends on:** 1.
- **Proof:** Editor and command flows demonstrate correct side/range/file selection, durable save, empty-text deletion, cancel without change, and safe refresh and stop behavior.

### 3. Comment discovery and management
- **Behavior:** Inline virtual text indicates current, stale, and resolved comments, while a separate comment quickfix list in the shared drawer supports navigation, edit, delete, resolve/reopen, and reattachment by selecting a stale comment and choosing a new review location; starting a review with comments but no changed files opens that list.
- **Boundary:** Side-by-side presentation, review drawer, and comment-management actions.
- **Depends on:** 1 and 2.
- **Proof:** End-to-end review flows demonstrate updated annotations, switching between independent quickfix lists in one drawer, management actions, stale recovery, and comment access when no changed files remain.

## Risks
- Exact-context matching may be ambiguous or impossible after edits; preserve the comment and mark it stale rather than attaching it to the wrong line.
- Concurrent refresh and editor operations must not overwrite saved comments or silently lose unsaved text.
- Current checkpoint files are deliberately not migrated; the in-place format change assumes none need preserving.
