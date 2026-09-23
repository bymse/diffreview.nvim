# Learnings Draft: 001

## Durable Findings
- `GitRepo:diff(from, nil)` already produces the required single baseline-to-working-state tracked diff including staged and unstaged changes.
- `git ls-files --others --exclude-standard -z` provides the loader's untracked path set without retaining file content.
- `git diff --no-index --numstat -z -- /dev/null <path>` supplies Git's own empty-source text count and binary classification semantics.
- `origin/HEAD` must be validated as an `refs/remotes/origin/*` symbolic target before revision resolution; Git otherwise permits symbolic refs to unrelated namespaces.
- Validate directory read and traverse access with libuv before Git discovery. Access semantics follow effective credentials and ACLs rather than raw mode bits.

## Repo Conventions Discovered
- Integration tests execute in coroutines, allowing production `async.system` calls to be tested against temporary real Git repositories.
- Shared LuaLS types are workspace annotations and do not require a runtime module import by each UI consumer.

## Things Future Specs Should Know
- Loaded review entries retain Git records or untracked paths keyed by stable IDs, providing the intended seam for a future lazy `load_diff` implementation.
