# Learnings Draft: 001-load-lightweight-review-files

## Durable Findings
- `GitRepo:diff(from, nil)` already produces one baseline-to-working-state diff containing staged and unstaged tracked changes without double-counting paths.
- `git diff --no-index --numstat -z /dev/null <path>` provides transient untracked text counts and binary detection without retaining file content.
- Git copy detection requires a tracked added destination and a suitable changed source; genuine type-change coverage can use a staged regular-file-to-symlink transition.

## Repo Conventions Discovered
- Integration tests use `tests/helpers/git_repo.lua` temporary repositories and register modules in `tests/integration/init.lua`.
- LuaLS validation is run through `just lint`; formatting is enforced with StyLua through `just format` and `just format-check`.

## Things Future Specs Should Know
- Shared diff view-model aliases now live at `diffreview.diff_view_model`; the former UI path intentionally has no compatibility module.
