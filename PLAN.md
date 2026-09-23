# Plan: Minimal Review Orchestration

Status: Approved

## Outcome
- **Goal:** Provide an explicitly configured review lifecycle that resolves zero, one, or two Git revisions, loads lightweight changed-file summaries, and displays them in an owned quickfix list without eagerly loading file snapshots.
- **Non-goals:** Opening a selected file, constructing full diff snapshots on demand, tracking or persisting reviewed state, comments, refresh, inline rendering, and publishing are deferred.
- **Success:** After `require('diffreview').setup(...)`, `:ReviewStart [from] [to]` opens a quickfix list containing the requested repository comparison, while `:ReviewStop` can cancel an in-progress start or cleanly end the active review without disturbing unrelated editor state.

## Runtime Change
1. Setup validates and stores top-level layout/view configuration, registers the review commands once, and rejects later setup calls.
2. Review start selects Neovim's working directory or the public Lua API's explicit `cwd`, then delegates the zero-to-two-revision comparison to the diffs module.
3. The diffs module loads Git metadata and untracked summaries, assigns stable file IDs, computes summary counts without retaining file contents, and returns no full snapshots.
4. The review lifecycle creates a UI instance and projects non-empty summaries into its owned quickfix list; an empty comparison is reported and leaves the lifecycle idle.
5. Review stop cancels and invalidates in-flight Git work or cleans the active UI, then returns the lifecycle to idle.

## Approved Boundaries
- **Approach:** Keep `diffs` as the deep Git-to-model module, move the shared diff model definitions to `diffreview.diff_view_model`, and let `review.lua` own the singleton idle/starting/active lifecycle, orchestration, cancellation, and user notifications while `init.lua` remains the thin public and command interface.
- **Constraints:** `setup` accepts top-level `layout` and `view`, defaults them to `horizontal` and `side_by_side`, and rejects every later setup call; `ReviewStart` accepts at most two positional revisions and uses Neovim's current working directory, while `diffreview.start({ cwd, from, to })` additionally permits an explicit repository path; local and remote branch refs use their merge-base with `HEAD`, tags and hashes use exact commits, zero arguments require the default branch discoverable from `origin/HEAD`, one argument compares against the current tracked and untracked working state, and two arguments compare exact committed endpoints without untracked files; missing defaults, unresolved revisions, invalid options, repeated setup, conflicting starts, and Git or UI failures are reported; cancellation produces only the stop notification and late async completions cannot reactivate the review.
- **Reuse and additions:** Reuse the existing Git adapter/parsers, quickfix projection, UI facade, coroutine-based process execution, and side-by-side cleanup; add lightweight loaded-diff state keyed by documented `stored:<old-path>` and `new:<new-path>` identities, missing revision/merge-base capabilities, cancellable process coordination, review lifecycle orchestration, and plugin-owned quickfix cleanup.
- **Rejected:** Renaming `diffs` to `git`, adding a separate Git-to-view-model mapper, eagerly constructing a map of full diff snapshots, automatically registering commands at plugin load, reconfiguring through repeated setup, and allowing concurrent or implicitly replacing reviews are rejected because they add coupling, memory use, or lifecycle ambiguity without serving the minimal flow.
- **Open questions:** none

## Phases

### 1. Load Lightweight Review Files
- **Behavior:** Callers can load changed-file summaries for the approved zero-to-two-revision semantics, including accurate transient counts for untracked text files and stable identities, without retaining snapshots or constructing full diff models.
- **Boundary:** Shared diff model definitions move above the UI layer, while the diffs module owns revision resolution, Git-derived normalization, and private metadata retained for later lazy loading.
- **Depends on:** none.
- **Proof:** Integration coverage demonstrates branch and commit semantics, default-branch failure, working-state and exact-endpoint differences, untracked text and binary summaries, stable IDs across operation types, structured failures, and absence of eagerly retained snapshot content.

### 2. Own The Quickfix Projection
- **Behavior:** Each ReviewUi instance owns its quickfix identity and can create or update its review summary projection without exposing list identity to callers.
- **Boundary:** Quickfix identity and display coordination move behind the ReviewUi interface while the low-level quickfix module retains list creation, update, selection, and rendering behavior.
- **Depends on:** none.
- **Proof:** Automated coverage demonstrates instance-specific ownership context, list creation, same-list updates, summary rendering, and preservation of unrelated quickfix history during display.

### 3. Clean The Quickfix Projection
- **Behavior:** ReviewUi can idempotently clean only its owned quickfix list and window, and failed display attempts roll back their partial changes without disturbing prior owned or unrelated quickfix state.
- **Boundary:** Ownership-validated quickfix cleanup and display rollback join the existing ReviewUi resource cleanup interface.
- **Depends on:** 2.
- **Proof:** Automated coverage demonstrates owned cleanup, foreign-list preservation, conditional window closure, repeated cleanup safety, and rollback after failures at each mutating display stage.

### 4. Expose The Review Lifecycle
- **Behavior:** Explicit single-use setup exposes the configured public Lua functions and `ReviewStart`/`ReviewStop` commands, rejects later setup calls, starts one review asynchronously through the diffs and UI modules, reports empty or failed comparisons, rejects conflicting starts, and allows stop to cancel startup or clean an active review.
- **Boundary:** `init.lua` owns public argument adaptation and configuration entry, `review.lua` owns lifecycle state and notifications, and cancellable async execution prevents stopped operations from committing late results.
- **Depends on:** 1, 2, and 3.
- **Proof:** Automated integration and functional coverage demonstrates initial setup and repeated-setup rejection, command and Lua argument handling, cwd selection, successful quickfix display, empty and failure behavior, active-review rejection, cancellation before activation, normal stop cleanup, idle-stop notification, and preservation of unrelated editor state.

## Risks
- Cancellation must coordinate process termination, coroutine completion, and lifecycle generation checks so a scheduled callback cannot resume or activate obsolete work.
- Neovim quickfix lists are global history; cleanup must use the retained stable list ID and ownership context rather than clearing all lists or blindly closing the current quickfix window.
- Branch classification and default-branch discovery must distinguish local/remote branch refs from other commit-ish expressions without guessing a missing default.
- Untracked summary counting may inspect large files transiently, so it must avoid retaining content and preserve binary handling without turning startup into eager snapshot loading.
