# Spec 002: Refresh and Restart Reconciliation

## Goal

Preserve comments through review refresh and restart, keeping uniquely matching text locations attached and retaining uncertain or absent locations as stale.

## Prerequisites

Spec 001 complete.

## Context

Read `specs/CONTEXT.md` for the approved identity, content snapshot, and stale-state rules. This finishes the plan's durable-state phase.

## Tasks

- Extend `lua/diffreview/comments.lua` with reconciliation over stored records and the current `LoadedDiffs`: compare the complete captured line range plus recorded available neighboring context on the same side of the same file ID. Accept only a unique exact match; update line bounds and context when text moves. Preserve the last known location for stale records and never use a fingerprint match alone as evidence that a line is still correct. For file notes, update the display path on rename and keep them attached while the file ID remains; mark every note for a missing comparison entry stale.
- Extend `lua/diffreview/review_progress.lua` (`reconcile`) and `lua/diffreview/review.lua` (`ReviewSession:start`, `refresh`) to carry comment records through file-record reconciliation and persist the reconciled result. Source old/current text through `lua/diffreview/diffs/init.lua` (`load_selected_view`) and `lua/diffreview/diffs/content.lua` as appropriate; handle path-backed current versions and Git snapshots consistently. A failure, cancellation, or changed review identity must retain the prior active state and saved checkpoint. Avoid loading or matching text for files without text comments where no file-level identity check is needed.
- Adjust `ReviewSession:start` in `lua/diffreview/review.lua` so a checkpoint with comments may become an active review even when the comparison has no changed files; keep the existing no-changes result for a review with no saved comments. Keep the separate source/baseline/target key and existing viewed-file reconciliation intact. Presentation of the comment-only UI belongs to spec 004.
- Add focused real-repository coverage in `tests/integration/comment_reconciliation_tests.lua`, register in `tests/integration/init.lua`, and extend `tests/integration/review_refresh_tests.lua` or `tests/integration/review_progress_tests.lua` only where shared behavior changes. Follow existing start/refresh Git fixtures and selected-content consistency checks.

## Verification

- Via session start/refresh in real temporary Git repositories, persist comments, move a uniquely identifiable line or range, refresh or restart, and observe the same comment IDs on the new lines; check both old and current sides and unchanged context. File-level comments remain attached through content edits/renames under the same collector ID.
- Exercise modified text, duplicated matching context, vanished side/file, empty comparison, canceled or failed content load, and failed checkpoint save. Observe comments retained as stale when matching is uncertain, retained across restart even if no changed files remain, and no partial state/UI adoption on failure; viewed status continues following its fingerprint rules.
- Run `just lint`, then `just format` and `just format-check`, then `just test` (multiple affected cases).
