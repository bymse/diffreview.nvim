# Spec 003: Writable Comment Editor

## Goal

Provide one bottom-split comment editor per review UI, accepting explicit targets and saving/deleting through a supplied handler, with reliable native write/quit semantics and draft ownership.

## Prerequisites

Complete `specs/001-sideless-file-comments.md` and `specs/002-comment-display.md`.

## Context

Read `specs/CONTEXT.md`. The editor accepts targets and callback implementations from the caller; it does not call the comments model, update annotations automatically, infer targets from quickfix/cursor/visual mode, or introduce commands/mappings. The display API and file associations are defined by spec 002.

## Tasks

### 1. Pin the public editor and save contracts

Add public methods and state ownership in `lua/diffreview/ui/init.lua`, delegating implementation and editor-specific public types to new `lua/diffreview/ui/comment_editor.lua`.

- `ReviewUi:open_comment_editor(options)` takes `ReviewCommentEditorOptions` and returns `integer|nil, string|nil`: the editable buffer on success or nil with a nonempty error. It opens/focuses the editor in the existing review tab.
- `ReviewUi:write_comment_editor()` takes no parameters and returns `boolean, string|nil`. This is the programmatic write interface used by integration tests and the native write handler; it saves without closing and returns false/error when no draft exists.
- `ReviewUi:close_comment_editor(force?)` takes `force: boolean|nil` and returns `boolean, string|nil`. No active editor is a successful no-op; a modified draft refuses ordinary close, while explicit force discards it. Closing never implicitly invokes save/delete.
- Preserve `get_ui(handlers)` and `ReviewUiHandlers` requirements; the save handler is supplied per editor request, not added as a controller dependency.

Define and annotate these data contracts:

| Type | Fields or signature |
| --- | --- |
| `ReviewCommentEditorOptions` | `target: ReviewCommentTarget`, `display_path: string`, `comment: ReviewComment|nil`, `on_save: ReviewCommentSaveHandler`, `origin_window: integer|nil` |
| `ReviewCommentSaveRequest` | `action: 'save'|'delete'`, `target: ReviewCommentTarget`, `comment_id: string|nil`, `text: string|nil` |
| `ReviewCommentSaveResult` | `comment_id: string|nil` |
| `ReviewCommentSaveHandler` | Receives `ReviewCommentSaveRequest`; returns `ReviewCommentSaveResult|nil, string|nil` synchronously. |

For a save request, `text` is the exact nonblank body and the success result must contain a nonempty resulting `comment_id`. For deletion, `comment_id` is the existing identity, `text` is absent, and a success result has no identity. Success returns a result and no error; a nonempty returned error signals failure. A thrown handler error or malformed/missing success result also fails the write without changing saved identity.

### 2. Validate explicit requests and preserve target identity

Implement opening/validation in `lua/diffreview/ui/comment_editor.lua`, using the presentation association from spec 002 for new source-range targets.

- Require nonempty file ID and display path, a handler, and a well-formed target: both endpoints absent for whole-file targets; both valid endpoints and old/current side for line/range targets. Invalid side values and partial ranges are rejected before replacing any draft.
- New line/range targets must match the explicitly associated displayed file and an actual displayed source side, with endpoints within its source lines. Path-backed text is allowed; information rows and artificial empty-snapshot rows are not source targets.
- Whole-file requests may omit the side and may come from a supplied review quickfix entry before any diff is selected. They need no source-pane lookup or content load. Membership in the opened review diff/list and availability of an explicitly supplied side are caller preconditions, not new UI membership checks or quickfix inference.
- For existing comments, require agreement between the supplied target and record target and preload the body/identity. Preserve original stale targets when editing rather than applying display clamping to saved coordinates.
- Capture the originating window from `origin_window` or the current window; require a valid origin in this UI's review tab. Return focus to it on successful close if it still exists; otherwise leave a surviving review window focused without recreating the origin.
- Copy input data and callback request targets so caller mutation cannot retarget a draft. Once open, changing the selected diff cannot change the draft's target or saved identity.
- Reopening the same target focuses its existing editor and retains its body, existing identity, handler, and origin instead of reloading supplied data. Opening a different target refuses while the existing draft is modified; an unmodified editor may be replaced. These rules also apply if the owned draft buffer survives after its window is hidden or closed.
- Validate the options container and target shape first. Once that target matches a surviving owned draft, reuse it without validating against the current presentation or checking replacement display path, comment, handler, or origin payloads; those fields are ignored in favor of captured values. This also applies after a diff switch or loss of the original source/origin window. New or different targets undergo all request validation before replacement.

### 3. Create the native writable virtual-file editor

Use native Neovim buffers/splits in `lua/diffreview/ui/comment_editor.lua`, evaluating instance tagging and virtual naming in `lua/diffreview/ui/scratch_buffer.lua` without changing its read-only projections.

- Use a distinct instance-owned, unlisted, swapless virtual buffer, with an identifying `diffreview://` name and `acwrite`-style native write handling. Create no backing temporary file.
- Open one bottom horizontal split and focus it without replacing either source pane or the quickfix buffer. Keep it out of native diff mode and preserve the source windows' diff settings/layout.
- Populate only the comment body, including exact internal/trailing blank lines; a new comment starts empty, and initial population is unmodified. Store target context in the editor window's winbar or equivalent non-body UI, including path, optional side, and original range or whole-file indication.
- Buffer-to-text conversion joins logical lines with newline separators without adding a filesystem end-of-file newline. Preserve nonblank whitespace verbatim; blank detection alone treats whitespace-only content as blank.
- Register buffer-local native write and lifecycle handling. Do not weaken global editor options or add new user commands/key mappings. Writable setup must not reuse the locked `nofile` semantics in a way that bypasses meaningful modified-buffer protection.

### 4. Implement save, deletion, and native write failure behavior

Route `write_comment_editor` and native `:write` through one save operation in `lua/diffreview/ui/comment_editor.lua`.

- A nonblank body sends a `save` request. New drafts omit `comment_id`; successful creation records the returned identity. Later saves supply the latest identity, including when the caller chooses a different resulting identity.
- Success marks the draft unmodified only after the handler succeeds. Keep the editor open for `:w`; do not refresh annotations unless the caller separately invokes the projection API.
- Blank existing content sends `delete`. Only after success clear its saved identity and normalize it to a new blank, unmodified draft for the same target. Subsequent nonblank text creates a new comment; repeated blank writes do not repeat deletion.
- A blank new draft invokes no handler, remains without identity, and is considered successfully written for native `:wq` behavior.
- Handler failure leaves the attempted body, previous identity, target, window, and modified status protected, with an observable nonempty error. `write_comment_editor` reports false/error; the native write path must propagate an actual write failure so `:wq` aborts rather than merely emitting a notification and closing.
- Save failures, including deletion failures, must be retryable. `:wq` closes only after a successful write; do not manually close from the write callback or apply annotation-clamped coordinates to requests.

### 5. Integrate cleanup without losing unrelated editor state

Modify `ReviewUi:cleanup` and owned-tab closure handling in `lua/diffreview/ui/init.lua` to release editor-owned buffers, windows, callbacks, and autocmds without saving. Teardown is an explicit discard boundary and is idempotent even after native close or manual buffer deletion.

For ordinary native close/hide, preserve modified-buffer protection and never silently delete a retained modified draft. Explicit forced close/discard may remove it without calling the handler. A clean successful close releases owned editor resources and returns origin focus. Manually lost windows/buffers must not leave callbacks attached to unrelated replacement resources.

Native `:q!` is an explicit discard: release that editor's draft and resources without invoking the handler. Reopening its target starts a fresh draft from the new request. This differs from non-discarding window hiding, which retains a surviving modified owned buffer for same-target reuse.

Diff display/refresh/clear continues clearing annotations, but does not dispose of or retarget an open editor. Refresh deferral is excluded. If the editor's original source pane disappears, saves still address the captured target and close tolerates the missing origin. Preserve borrowed file buffers, quickfix entries, and native diff state throughout.

Evaluate and, where needed, modify `lua/diffreview/ui/side_by_side.lua` window recovery so it never adopts an editor window as a replacement source pane. Display retains its existing focus behavior, and an editor draft survives source-pane loss and a later display while the editor was focused.

### 6. Add focused integration and functional coverage

Create these integration modules under `tests/integration/ui/comments/` and register them in `tests/integration/init.lua`:

- `tests/integration/ui/comments/editor_tests.lua`: explicit target validation, new/preloaded bodies, bottom placement, same-target reuse, differing-target draft protection, quickfix-origin whole-file requests, and source/target separation.
- `tests/integration/ui/comments/saving_tests.lua`: public programmatic writes, exact text requests, returned identity propagation, repeated saves, blank/delete behavior, failures/retries, and no automatic annotation refresh.
- `tests/integration/ui/comments/editor_lifecycle_tests.lua`: public close/force behavior, diff-switch target stability, missing origins, and explicit/tab/native-resource cleanup.

Include public-interface regression coverage that modifies an editor, loses a source pane, displays another diff while the editor is focused, then verifies the preserved draft saves to its captured target. Reopening that same target after the switch must retain the original handler, origin, identity, and body without current-presentation validation.

Evaluate reuse of `tests/integration/ui/comments/helpers.lua` from spec 002 and existing real Git/UI fixtures. Supply callbacks as real implementations of the intended API; capture their requests/results without replacing modules, Neovim APIs, or notifications. Integration tests call the new open/write/close methods rather than simulating user keys or commands.

Create `tests/functional/comment_editor_write_test.lua` and `tests/functional/comment_editor_lifecycle_test.lua`; register them in `tests/functional/init.lua`. Use real editor commands for native `:w`, `:wq`, ordinary quit, and forced quit behavior, with fixtures that create the UI facade directly. Existing `tests/helpers/functional_review.lua` is a reference for setup/cleanup, but starting a controller-connected comment flow or adding production bindings is not required. Inspect actual buffers, windows, callbacks, modified flags, messages, and surviving source panes; do not assert exact incidental diagnostic wording.

Functional forced-quit coverage must assert `:q!` invokes no handler, releases the discarded draft, and a later open creates a fresh draft. Keep the public API force-close coverage separately in integration tests.

## Verification

- **Normal save journey:** Open an explicit range on a displayed diff through `open_comment_editor`, edit the returned buffer, and call `write_comment_editor`. Assert one save request with the exact file/side/range/body, an unmodified still-open editor, and subsequent writes using the returned identity rather than creating again.
- **Whole-file quickfix journey:** Show review files, open a side-less whole-file editor from its explicitly supplied entry while the drawer is focused and no diff is selected, save, and close. Assert the side remains absent, the drawer/entries survive, and focus returns to the origin.
- **Native write journey:** Functional tests prove `:w` keeps the editor open, successful `:wq` closes it and returns origin focus, and failed save/delete or thrown-handler errors abort `:wq` with unchanged draft text/identity and a protected modified buffer. A retry succeeds without duplicate creation/deletion.
- **Deletion journey:** Blank an existing comment and write; assert one deletion request and an identity-free blank draft. Writing a blank new draft creates nothing; entering text after successful deletion creates a new identity.
- **Ownership journey:** Demonstrate refusal to replace/close modified drafts without force, same-target reuse, stable saves after a diff switch, missing-origin tolerance, and teardown without handler calls or damage to source buffers, quickfix, or diff state.
- **Gates:** Run `just lint`, `just format`, and `just format-check` in that order. Have the `test-runner` agent run `just test`. All suites must pass, with native write failure/quit behavior verified functionally rather than inferred from callback-return tests.
