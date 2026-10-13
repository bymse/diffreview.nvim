# Spec 002: Refresh and Restart Reconciliation

Fixed-range follow-up: the approved 2026-10-13 simplification in `specs/CONTEXT.md` supersedes unique text/context search below. Refresh/restart check the stored range hash without moving coordinates; missing or changed ranges remain stale until matching text returns or an available location is acknowledged by writing the comment.

Follow-up contract: the approved 2026-10-13 review changes in `specs/CONTEXT.md` supersede this phase's independent resolution/staleness and explicit-side representation. Resolved comments remain resolved; reopening rechecks current attachment eligibility.

Naming follow-up: the selected comparison loader is now `diffs.load_selected_view_model`; session helpers and their result collections also spell out view-model terminology.

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

## Reconciliation Contract

- Reconcile every record, including previously stale records. If the original file/side and captured text/context regain a unique exact match, clear staleness automatically. Returning file identities similarly reattach file notes. Preserve ID, body and manual resolution state; unsuccessful matches preserve last-known location, anchors and context.
- Missing sides and successfully identified non-text content (binary or submodule) make text comments stale. File notes remain attached to present identities. Genuine filesystem/Git content-read failures abort the entire candidate. Classify submodule views from collector metadata rather than treating all error views as stale.
- For every file with text comments, including unselected files, load immutable comparison snapshots and verify them against the candidate aggregate fingerprints before saving. A successful read with mismatched bytes is a failed candidate, not a stale-anchor result. Recheck session/request currency after yielding; keep loading orchestration at the session boundary and exact matching in the domain. Preloaded refresh must also have a valid coroutine path.
- Rejected refresh retains the previous active state, checkpoint and presentation. Canceled startup remains idle without a candidate save. Explicit stop performs its normal idle transition and prevents a pending operation from adopting or saving its candidate.
- Successful refresh to an empty comparison with retained comments must preserve the active review tab/window even when the selected panes are cleared and the drawer is closed. Make the minimum lifecycle correction in `lua/diffreview/ui/side_by_side.lua` or its owning UI boundary; comment-list presentation remains spec 004. Add a command-driven regression that selects a file, refreshes snapshots, removes the last entry with the drawer closed, then restores content and refreshes without restart.

## Verification

- Via session start/refresh in real temporary Git repositories, persist comments, move a uniquely identifiable current-side line or range, refresh or restart, and observe the same comment IDs on the new lines, including unchanged context. File-level comments remain attached through content edits/renames under the same collector ID.
- Exercise modified text, duplicated matching context, vanished side/file, empty comparison, canceled or failed content load, and failed checkpoint save. Observe comments retained as stale when matching is uncertain, retained across restart even if no changed files remain, and no partial state/UI adoption on failure; viewed status continues following its fingerprint rules.
- Cover an unselected commented file changing after `load_diffs` with a preloaded refresh candidate; verify active state, checkpoint and presentation are preserved. Cover stale text/file identities returning with resolution unchanged, and supported text becoming non-text distinctly from a genuine content-load failure.
- Run `just lint`, then `just format` and `just format-check`, then `just test` (multiple affected cases).
