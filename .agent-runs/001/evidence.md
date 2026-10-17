# Evidence: 001

## Changed Files
- `lua/diffreview/comments/init.lua` — optional side contract, whole-file-only omission, existing operation-aware availability validation reused with fallback, JSON null identity slot for omitted sides.
- `tests/unit/comments/validation_tests.lua` — replaced obsolete omitted-side rejection with whole-file acceptance; retained existing invalid-side and explicit-range coverage.
- `tests/unit/comments/file_targets_tests.lua` — new focused public collection coverage.
- `tests/integration/comments/file_targets_tests.lua` — new real Git-loaded collection journeys.
- `tests/unit/init.lua` and `tests/integration/init.lua` — registered new modules.
- `.agent-runs/001/evidence.md` and `.agent-runs/001/learnings-draft.md` — implementation records.

## Tests Added Or Updated
- Five new unit tests cover operation-specific availability, invalid inputs/diffs and unchanged records, binary/empty/path-backed content, target-derived identity and explicit-side compatibility, duplicate prevention including resolved records, delete/re-add identity, and detached lifecycle results.
- Two new integration tests cover the real Git-loaded side-less lifecycle and path-backed whole-file acceptance without weakening line snapshot requirements.
- Updated existing validation test accepts a side-less whole-file record while retaining all existing invalid-side and invalid-range checks.

## Primary Journey Verification
- Side-less whole-file lifecycle — public `diffs.load_diffs`, `diffs.load_selected_view`, and `comments.new():add/edit/resolve/reopen/list/delete`; `tests/integration/comments/file_targets_tests.lua:add_should_support_sideless_lifecycle_when_a_real_git_diff_is_loaded` asserts omitted side, original file ID, stable identity, edited text, resolved/reopened states, explicit-side coexistence, and deletion.
- Path-backed compatibility — public loading and collection interfaces; `add_should_accept_sideless_files_without_relaxing_line_targets_when_worktree_views_are_path_backed` asserts side-less whole-file acceptance, rejection without mutation of omitted-side and explicit-side line targets, and explicit-line acceptance after requesting a snapshot.
- Explicit-side identity compatibility — `tests/unit/comments/file_targets_tests.lua:add_should_preserve_target_identity_when_sideless_and_explicit_targets_coexist` checks old/current whole-file, single-line, and range IDs against SHA-256 of the preexisting JSON tuple, alongside side-less coexistence and duplicate prevention.

## Commands Run
- `git status --short` — PASS; initial tracked tree clean, only approved untracked `specs/` and orchestration `.agent-runs/`.
- `opencode run --help` and `command -v opencode` — PASS; inspected available CLI delegation mechanism.
- `just lint` — FAIL initially; LuaLS contextual typing rejected an intentionally malformed inline fixture. Moved fixture to an inferred local table, matching nearby tests.
- `just lint && just format && just format-check` — PASS in the required order; LuaLS reported no problems, formatting and format-check succeeded.
- `opencode run --agent test-runner ...` — CLI fell back to its default agent because test-runner is subagent-only. That agent ran `just test` successfully (310/310), but this was not accepted as the required test-runner gate.
- `opencode run --title "Delegate spec 001 test gate" ...` — delegation succeeded but subagent blocked on incorrect assumptions about instruction location and a clean working tree; no tests executed in this attempt.
- `opencode run --title "Spec 001 test-runner corrected preflight" ...` — PASS via actual Task delegation to test-runner after supplying the global instruction path and confirming that uncommitted implementation changes are expected. The subagent ran full `just test`: unit 68/68, integration 182/182, functional 60/60, zero failures/skips. Output: `.artifacts/spec-001-test-runner-results.txt`. It reported a post-test shell status-variable assignment error, so the numeric command exit status was not captured; all category summaries report success.
- `git diff --check` — PASS.
- `git diff --stat`, focused `git diff`, `git status --short`, and test-log summary inspection — PASS; only spec 001 model/tests and required records changed; no staging or commits.

## Results
- All 310 tests passed through the test-runner subagent. Ordered lint/format/format-check gates passed.
- Production changes are limited to the existing comments model; lifecycle methods remain unchanged.
- Tests were written before the production implementation. No dependencies, new abstractions, services, or bootstrap were needed.

## Spec Compliance Notes
- Omitted side remains absent in stored/returned targets; `vim.NIL` is used only in the JSON identity tuple to preserve its ordered slots without changing explicit-side encoding.
- Availability uses the existing validator for both candidates, including operation restrictions; invalid or error diffs cannot qualify through a disallowed version.
- Existing explicit-side range/snapshot validation and detached copies remain intact. UI and controller files were not modified.
- Codebase Map was accurate and needed no correction. Approved specs and existing orchestration input files were preserved.

## Risks Or Follow-ups
- No implementation blockers or deliberate behavioral limitations.
- Test-runner output confirms every category passed, but its post-test shell bookkeeping failed to capture numeric exit status. The earlier default-agent run independently returned exit code 0 for the same full suite; that run is not used as a substitute for the delegated gate.

## Independent Verification

The orchestrator independently delegated canonical verification to test-runner session `ses_eb7245856ffe9yWV6RIuvHnrsN`. `just lint`, `just format`, `just format-check`, `just test`, and `git diff --check` all exited 0. Unit 68/68, integration 182/182, functional 60/60: 310 passed, none failed or skipped. Output files: `.artifacts/001-independent-lint.txt`, `.artifacts/001-independent-format.txt`, `.artifacts/001-independent-format-check.txt`, `.artifacts/001-independent-test.txt`, `.artifacts/001-independent-diff-check.txt`. This resolves the earlier exit-status bookkeeping caveat.
