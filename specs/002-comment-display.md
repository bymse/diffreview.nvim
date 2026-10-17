# Spec 002: Comments in Displayed Diff Panes

## Goal

Render caller-supplied comments as virtual lines in both displayed diff sides, including whole-file comments and stale-anchor fallbacks, with isolated projection cleanup.

## Prerequisites

Complete `specs/001-sideless-file-comments.md`.

## Context

Read `specs/CONTEXT.md`. UI code consumes `ReviewComment` data but does not require or invoke the comments collection. This is an explicit-input API, with no commands, cursor lookup, comment list, or controller wiring.

## Tasks

### 1. Associate an explicit file identity with a displayed diff

Modify `lua/diffreview/ui/init.lua` at `ReviewUi:display_diff_side_by_side`, `refresh_selected_diff`, `clear_selected_diff`, `cleanup`, and state/type initialization. Modify `lua/diffreview/ui/side_by_side.lua` at `display_side_by_side`, `cleanup`, and `clear` to retain the actual pane/source associations needed by comments.

- Extend `ReviewUi:display_diff_side_by_side(diff, layout, keep_drawer?, file_id?)` with an optional fourth `file_id: string|nil` argument. Existing positional arguments and callers retain their behavior.
- Extend `ReviewUi:refresh_selected_diff(diff, layout, file_id?)` with an optional third file ID and forward it to display. Both methods keep their existing nil return.
- A provided ID must be a nonempty string. An omitted ID leaves that presentation unassociated for comment APIs; do not infer it from a path or carry the previous file's identity into a fresh display.
- Track the explicit file identity and actual main/companion buffer/window source roles; do not retain the diff model. Main is old for deleted text, current for normal source views, and has no source side for information views. A missing companion is not a displayed old side, even if the diff model contains old content.
- Distinguish real source-line counts from Neovim's artificial first row for an empty snapshot. Path-backed source bounds use the displayed buffer's lines.
- Clear prior comment projections and identity/pane associations on presentation replacement, refresh, clear, and cleanup. Do not change native diff layouts or existing file highlighting.

### 2. Add the public comment projection API

Add `ReviewUi:show_comments(file_id, comments)` and `ReviewUi:clear_comments()` in `lua/diffreview/ui/init.lua`, with LuaLS signatures and delegation to `lua/diffreview/ui/comments/decorations.lua`.

- `show_comments` parameters are `file_id: string` and `comments: ReviewComment[]`; return `boolean, string|nil`. Success replaces the entire comment projection for the matching displayed file, including clearing it for an empty list. Records targeting other file IDs are not displayed.
- A missing associated presentation, a mismatched file ID, or a lost/replaced source pane returns false with a nonempty error rather than decorating an unrelated buffer. Validate association before clearing the previous projection.
- `clear_comments` takes no parameters, returns nil, and idempotently clears this UI instance's comment decorations and tracked projection resources. It does not clear diff decorations or discard the current diff identity.
- Give comments a separate per-instance namespace. Keep rendering details out of the facade and keep them separate from the existing `decorations` module's diff-line namespace.
- Do not retain caller tables by reference or mutate targets. No automatic loading, model calls, or automatic redraw after external saves.

### 3. Project the agreed display semantics

Implement virtual-line projection in `lua/diffreview/ui/comments/decorations.lua`, evaluating existing namespace/extmark usage in `lua/diffreview/ui/decorations.lua` for reuse of native patterns.

- Render open and stale comments; omit resolved comments. Preserve every body line, including blank lines, without inserting source-buffer text. Use existing highlight groups for comment text and stale emphasis; no new configuration or dependency is required.
- Put line/range comment blocks below the original inclusive final line on their matching displayed side. Include enough visible context to distinguish a range and identify stale feedback's original coordinates. Preserve supplied order for blocks sharing an anchor.
- Put explicit-side whole-file blocks above that side's displayed source content. Put side-less whole-file blocks above the main pane once. Information views support side-less whole-file blocks; their rows are never line-comment anchors.
- Omit side-specific records whose side is not displayed; never open a companion merely to render a comment or project an old-side comment onto current source text.
- For stale line/range records, clamp only the display anchor to the nearest available source row; preserve their original target and visible original range. Empty text uses its first display row for this fallback. Omit non-stale out-of-bounds ranges rather than clamping them or marking them stale in the UI.
- Repeated rendering replaces rather than duplicates blocks. Empty/resolved-only/unrelated-file input clears the previous projection for the supplied displayed file.

### 4. Integrate ownership cleanup

Clear the comments namespace from every previously decorated valid buffer on replacement and teardown, including borrowed file buffers. Handle manually closed windows and deleted buffers without touching their replacements.

Ensure new comment resources are released when the owned review tab closes, even when the supplied `on_tab_closed` handler does not invoke `ReviewUi:cleanup`. Preserve existing handler notification behavior and tolerate later explicit/reentrant cleanup. Keep existing side-by-side resource handling otherwise unchanged.

### 5. Add real-editor projection tests

Create `tests/integration/ui/comments/display_tests.lua`, `tests/integration/ui/comments/targets_tests.lua`, and `tests/integration/ui/comments/cleanup_tests.lua`; register all in `tests/integration/init.lua`. If shared setup is needed, keep it local to `tests/integration/ui/comments/helpers.lua` and evaluate reuse of `tests/helpers/diff_view_model.lua`, `tests/helpers/git_repo.lua`, `tests/helpers/ui_handlers.lua`, and the cleanup conventions in `tests/integration/ui/side_by_side/helpers.lua`.

Exercise the public `ReviewUi` facade and inspect actual pane buffers, window positions, source lines, and extmark virtual-line details. Find observable panes through their buffers/layout rather than asserting private comment state. Use real Git-backed file buffers where ownership matters. Cover both layouts and source roles, unchanged source lines, line/range/file targets, full multiline text, state filtering, stale bounds/empty text, missing sides, information views, mismatched/unassociated file identities, projection replacement, and explicit/tab-close cleanup.

## Verification

- **Normal journey:** Display a modified text diff with an explicit file ID through `display_diff_side_by_side`, call `show_comments` with comments for both sides and unchanged lines, and inspect virtual blocks on the actual old/current buffers. Assert full text, correct side, placement below range ends, and unchanged source lines.
- **Whole-file journey:** Display a file-level record without a side once above main content; demonstrate the same behavior for a binary/information view. Explicit-side blocks follow actual displayed source roles, including deleted files.
- **Replacement journey:** Replace the supplied projection, switch files, clear the selected diff, and close the UI/tab. Assert no duplicate/leaked comment extmarks, preserved diff highlights and native diff behavior, and surviving unmodified borrowed buffers.
- **Failure boundaries:** Wrong file identity or lost pane cannot decorate a replacement/unrelated buffer. Stale fallback preserves original target data; resolved comments are absent.
- **Gates:** Run `just lint`, `just format`, and `just format-check` in that order. Have the `test-runner` agent run `just test`. Existing callers without file IDs and all prior side-by-side tests must continue to pass.
