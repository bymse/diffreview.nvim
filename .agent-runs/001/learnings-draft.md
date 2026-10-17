# Learnings Draft: 001

## Durable Findings
- Explicit-side comment IDs are SHA-256 of the JSON tuple `{ file_id, side, line_start or 0, line_end or 0 }`. Side-less targets use JSON null (`vim.NIL`) in the side slot; returned targets still omit the side field.
- The comments model's existing side validator already enforces operation-specific availability and content validity. Calling it for current and then old supports file-level availability without accepting operation-disallowed versions or weakening snapshot range checks.

## Repo Conventions Discovered
- Comment tests use focused modules registered explicitly in the category's `init.lua`, with public collection operations and real Git-loaded integration fixtures.
- LuaLS contextual typing can reject malformed inline fixtures passed directly to typed interfaces; inferred local fixture tables match the existing validation-test style.

## Things Future Specs Should Know
- Default selected worktree views are path-backed; request `load_selected_view(loaded, id, nil, true)` when collection line comments need snapshots. Side-less whole-file comments do not need that conversion.
- The test-runner instructions live at `/home/bymse/.config/opencode/agents/test-runner.md`. CLI `opencode run --agent test-runner` falls back because the agent is subagent-only; actual delegation requires a primary agent invoking its Task tool with test-runner.
