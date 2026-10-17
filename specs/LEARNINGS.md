# Implementation Learnings

Durable discoveries from completed implementation phases are recorded here.

## 2026-10-17 — Comment target identity and source content

Finding: Explicit-side IDs are SHA-256 of the JSON tuple `{ file_id, side, line_start or 0, line_end or 0 }`; omitted sides use JSON null in that tuple while remaining absent in returned targets. The existing side validator enforces operation-aware availability and content validity.

Impact: Side-less whole-file support reuses validation and lifecycle behavior without weakening explicit-side contracts.

Use in future specs: Keep UI targets detached and preserve original target coordinates. Default selected worktree views are path-backed; collection line targets still require snapshots (`load_selected_view(loaded, id, nil, true)`). The UI may use actual displayed path-backed lines without changing that model contract. Malformed typed test inputs can be assigned to inferred local fixture tables for LuaLS-compatible negative tests.

Source: `.agent-runs/001/learnings-draft.md`; spec 001 implementation and judge review.
