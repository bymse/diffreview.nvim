# Comment UI: Shared Context

## Issue Summary

The comments collection manages comment records and their lifecycle, but the review UI cannot display or edit them. Reviewers need feedback attached to either displayed diff side, unchanged source lines, ranges, or whole files, including whole-file feedback initiated from the review file quickfix list.

## Final Goal

Provide programmatic UI functions that render caller-supplied comments and open a writable virtual-file editor in a bottom split. Saving invokes a caller-supplied synchronous handler. Extend the comments collection to accept whole-file targets without a side, but do not connect that collection to the UI or controller.

Success means a caller can display comments on both panes, open or edit an explicitly targeted comment, save repeatedly without creating duplicate identities, delete by writing blank text, retain drafts after save failures, and close the editor using ordinary Neovim write/quit behavior.

Excluded: lifecycle/controller wiring, persistence, new commands or key mappings, cursor/selection/quickfix target inference, comment lists, stale detection, refresh deferral, other diff presentation modes, and comments on files outside the opened review diff/list. A quickfix-origin editor receives its file identity explicitly and does not require opening that file's diff first.

## Key Design Decisions

- **Authoritative data:** Comments and save outcomes come from the caller; buffers and annotations are projections. UI code never requires the comments lifecycle module, performs collection mutations, or writes comments to disk. Tests may supply real callback implementations as the intended UI boundary without replacing any component or editor API.
- **Targets:** `ReviewCommentTarget` has `file_id: string`, `side: ReviewCommentSide|nil`, and `line_start`/`line_end: integer|nil`. Sides are `old` and `current`. Both endpoints absent means a whole-file target, whose side may be absent; both present means a positive, ordered, inclusive source range requiring a side. A single line uses equal endpoints.
- **Model compatibility:** Side-less whole-file comments require a valid, available diff with at least one available version. Their identity differs from both explicit-side whole-file identities. Preserve existing explicit-side identity generation, validation, copy isolation, and lifecycle behavior. Line comments still require snapshot text in the collection.
- **Path-backed source:** The UI may target actual displayed file-buffer lines. It does not load snapshots for the collection; future wiring must satisfy the collection's snapshot requirement.
- **Display:** Full multiline comment bodies are virtual lines, below range ends or above content for whole-file comments. Hide resolved comments. Stale comments visibly retain their state and original target; out-of-bounds stale display anchors clamp to the nearest remaining line without changing the target. Use the empty buffer's first display row when necessary. Side-less whole-file comments appear once above the main pane, including information views; do not open a hidden side to show feedback.
- **Editor:** One plugin-owned virtual-file buffer in a bottom split per UI instance. Its editable body contains only comment text; target context is outside the body. The caller supplies the target, existing record when editing, and handler. Reopening the same target preserves its draft; a different target cannot replace a modified draft.
- **Writes:** `:w` saves and keeps the editor open; `:wq` saves and closes only on success. Save success establishes the returned identity for subsequent writes and clears the modified flag. Failure remains visible, preserves the draft and identity, and prevents `:wq` from closing. Empty or whitespace-only text deletes an existing comment; a blank new draft creates nothing. After deletion, the open editor becomes a new blank draft for the same target.
- **Rendering after saves:** The save handler does not implicitly update annotations. The caller explicitly supplies the next comment projection.
- **Ownership:** Ordinary close/replacement respects modified drafts; explicit force discards them. Diff transitions clear annotations without retargeting the editor. Cleanup releases owned buffers/windows/autocmds and comment decorations, never saves implicitly, and preserves borrowed file buffers and existing diff highlights. The editor is not a native-diff participant.
- **Technology:** Reuse native Neovim splits, virtual lines, write handling, and existing UI ownership patterns. No dependencies or real temporary comment files. Direct lifecycle calls are excluded by the UI boundary.
- **Material risks:** Native write failures must abort `:wq`; buffer-scoped extmarks on borrowed buffers need isolated cleanup; stale display clamping must never become saved coordinates. Refresh orchestration remains future work even while an editor is open.

## Codebase Map

### Production

- `lua/diffreview/comments/init.lua`: `comments.new()` and `ReviewCommentCollection:add/edit/resolve/reopen/delete/list`; public comment types, availability/range validation, target-derived identities, and detached record copies. Only this model module changes for side-less targets.
- `lua/diffreview/ui/init.lua`: `ReviewUi`, `ReviewUiHandlers`, and `get_ui(handlers)`; owns the review tab and facade methods, including `display_diff_side_by_side`, `refresh_selected_diff`, `clear_selected_diff`, and `cleanup`. Preserve existing handler requirements and existing positional arguments.
- `lua/diffreview/ui/side_by_side.lua`: `display_side_by_side`, `cleanup`, and `clear`; chooses main/companion buffers, knows their actual source-side roles, and owns presentation transitions. Main is old for deleted files, current for normal source views, and neither for information views.
- `lua/diffreview/ui/scratch_buffer.lua`: `snapshot` and `information`; instance-tagged, unlisted, no-swap virtual buffers. They are locked `nofile` projections, not writable editor buffers; evaluate ownership conventions without weakening their behavior.
- `lua/diffreview/ui/decorations.lua`: added/deleted diff-line extmarks and namespace-wide clear. Comments need a separate namespace so clearing them cannot clear diff highlights.
- `lua/diffreview/ui/comment_decorations.lua`: explicit caller-supplied comment projection, pane association validation, virtual-line rendering, and per-instance namespace cleanup; no collection or controller calls.
- `lua/diffreview/ui/native_diff.lua`: window-local native diff setup and option restoration. Comment-editor splits must not join or disturb the two source windows' native diff state.
- `lua/diffreview/ui/quickfix.lua`: native review file drawer and supplied file IDs. Reuse the public file-list UI for fixtures; add no comment-target lookup or bindings here.
- `lua/diffreview/diff_view_model.lua`: `ChangedFileViewModel`, `DiffViewModel`, source/version/content types. `ChangedFileViewModel.id` is separate from `DiffViewModel`, which has no file ID.
- `lua/diffreview/ui/diff_view_model_validator.lua`: validates operation/version/content structures for presentation. Comment support must not weaken existing validation.
- `lua/diffreview/review.lua` and `lua/diffreview/init.lua`: existing orchestration and public commands; reference for compatibility only, with no comment wiring in this work.

### Tests and Tooling

- `tests/unit/comments/validation_tests.lua`, `mutations_tests.lua`, `resolution_tests.lua`, and `isolation_tests.lua`: focused public collection contracts. Update the existing rejection of an omitted side with no range.
- `tests/integration/comments/targets_tests.lua` and `lifecycle_tests.lua`: public collection behavior against real Git-loaded diffs, including path-backed versus snapshot targets.
- `tests/integration/ui/side_by_side/`: operation-specific rendering and transition coverage; `helpers.lua` provides established UI fixture cleanup. Existing extmark inspection uses `nvim_buf_get_extmarks` with details.
- `tests/integration/ui/comments/`: public facade projection, target/source-role, and ownership cleanup tests; local helpers inspect real source panes and virtual-line extmarks.
- `tests/helpers/diff_view_model.lua`, `git_repo.lua`, and `ui_handlers.lua`: shared diff constructors, real temporary repositories, and required UI callbacks.
- `tests/functional/review_tab_lifecycle_test.lua` and `tests/helpers/functional_review.lua`: native editor interactions, window/tab observations, and repository cleanup patterns. New comment flows call the UI facade directly because controller wiring is excluded.
- `tests/functional/comment_tab_cleanup_test.lua`: native tab-close comment cleanup through the public UI facade with a notification-only handler and a real borrowed Git-backed buffer.
- `tests/unit/init.lua`, `tests/integration/init.lua`, and `tests/functional/init.lua`: explicit test-module registries; new modules must be registered.
- `justfile`, `scripts/lint.lua`, and `tests/run.lua`: pinned Neovim runner, LuaLS, formatting, and test categories.

## Shared Verification Rules

Follow applicable `AGENTS.md`: lowercase snake_case test names in the `method_should_expected_behavior_when_condition` pattern; no arrange/act/assert comments; real editor/Git fixtures; no replacement or interception of components, editor APIs, or notifications. Integration tests call module interfaces; key-driven and native user-command flows belong in functional tests. Inspect real buffers, window layout, extmarks, callback results, and modified flags instead of private state or exact incidental diagnostics.

Annotate every public Lua function, parameter, callback, and return value for LuaLS. Do not annotate primitive local variables unnecessarily. Keep test modules focused by behavior.

For every implementation spec, run `just lint`, then `just format`, then `just format-check`; fix all affected LuaLS issues. Run tests through the `test-runner` agent, never directly in the main conversation. These specs each affect multiple cases, so the required test gate is `just test`. Exact-name test commands may be used during focused development, but do not replace that gate. If the pinned Neovim artifact is absent, the test-runner performs the repository's `just bootstrap` preparation. Record gate results and public-behavior evidence for implementation review.
