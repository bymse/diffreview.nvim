# Spec 001: Side-less Whole-file Comments

## Goal

Allow a whole-file comment to refer to the file independently of its old/current versions, while preserving explicit-side targets, their existing identities, and all range validation.

## Prerequisites

None. This implements the model phase before UI work.

## Context

Read `specs/CONTEXT.md`, especially target semantics, model compatibility, and shared verification rules. UI/controller wiring and changes to snapshot requirements are excluded.

## Tasks

### 1. Extend the public target contract

Modify `lua/diffreview/comments/init.lua` at `ReviewCommentInput`, `ReviewCommentTarget`, and `ReviewCommentCollection:add`.

- `ReviewCommentInput`: `file_id: string`, `side: ReviewCommentSide|nil`, `text: string`, `line_start: integer|nil`, `line_end: integer|nil`.
- `ReviewCommentTarget`: `file_id: string`, `side: ReviewCommentSide|nil`, `line_start: integer|nil`, `line_end: integer|nil`.
- `ReviewCommentSide`, `ReviewCommentState`, and the other `ReviewComment` fields remain unchanged.
- Document that an omitted side is legal only when both range endpoints are absent. An omitted side must remain omitted in returned/listed records rather than being defaulted to current or old.
- Preserve all existing collection method signatures and return conventions.

### 2. Validate side-less targets without weakening existing checks

Extend `ReviewCommentCollection:add`, reusing the existing availability/content validation around local `validate_side` and `valid_content`.

- A side-less whole-file target requires a nonempty file ID, nonblank text, a supported non-error diff operation, and at least one valid version available for that operation. Added/untracked/unmerged use current availability; deleted uses old; two-version operations can use either available valid version.
- A missing, unsupported, or error diff, or one without any valid available version, remains rejected. Do not accept an operation-disallowed version merely because it is present in the supplied table.
- Reject omitted sides when either endpoint is present, as well as invalid non-nil side values. Preserve positive finite integer, paired-endpoint, ordering, snapshot-content, and range-bound checks for explicit-side line targets.
- Preserve whole-file acceptance for binary, empty snapshot, and path-backed text content when an available valid version exists.
- Validation failures return a nonempty error and leave the collection unchanged; retain detached inputs/results.

### 3. Preserve target identity and lifecycle behavior

Modify target identity generation inside `ReviewCommentCollection:add` without changing the identity encoding for explicit old/current targets.

- Represent an absent side explicitly in the hashed target identity so it cannot collapse an ordered tuple or collide with either supported side.
- The same side-less file target produces the same ID regardless of text, insertion order, or display paths; different file IDs and explicit sides remain distinct.
- Side-less and old/current whole-file comments for the same file may coexist. A second add for the same exact target is rejected even after resolution; delete then add recreates that target's identity.
- Existing `edit`, `resolve`, `reopen`, `delete`, and `list` operate on side-less records without adding a side or altering target identity.

### 4. Add focused public-contract coverage

Modify `tests/unit/comments/validation_tests.lua` to replace its now-obsolete rejection of a side-less whole-file input while retaining invalid-side and invalid-range coverage. Add `tests/unit/comments/file_targets_tests.lua` for side-less validation, identity, lifecycle, and isolation behavior, and register it in `tests/unit/init.lua`.

Add `tests/integration/comments/file_targets_tests.lua` and register it in `tests/integration/init.lua`. Reuse `tests/helpers/diff_view_model.lua`, `tests/helpers/git_repo.lua`, and the public loading/collection patterns in `tests/integration/comments/targets_tests.lua`; keep new file-target coverage separate rather than enlarging that broad module. Leave existing target and lifecycle coverage intact unless an expectation genuinely changes.

Exercise availability categories, binary/empty/path-backed whole-file content, omitted/partial/invalid ranges, invalid supplied diffs, distinct identities, duplicate prevention, edit/resolve/reopen/delete/list, and detached result mutation at the lowest useful layer. Verify explicit-side ID compatibility against the preexisting target-identity contract, not merely inequality with new IDs.

## Verification

- **Normal journey:** Using a real Git diff through `diffs.load_diffs` / `load_selected_view`, add a side-less whole-file record through `comments.new():add`, then edit, resolve, reopen, list, and delete it. Assert that the target retains its file ID and omitted side and that identity stays stable until deletion.
- **Compatibility:** Public collection tests demonstrate coexistence of side-less and both explicit-side file comments where available, unchanged explicit-side IDs, unchanged snapshot requirements, and unchanged behavior of the existing unit/integration suites.
- **Rejections:** Invalid side-less range/diff inputs return an error without changing the prior public `list()` result.
- **Gates:** Run `just lint`, `just format`, and `just format-check` in that order. Have the `test-runner` agent run `just test`. All must pass under the shared verification rules.
