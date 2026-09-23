# Learnings Draft: 004-expose-review-lifecycle

## Durable Findings
- An `AsyncOperation` can safely invalidate a scheduled process completion by marking cancellation before process termination and checking identity at lifecycle commit points.
- Optional Git metadata remains best-effort for ordinary command failures, but cancellation must propagate as a terminal repository result.
- A direct lifecycle test can use a real temporary repository and `ReviewUi`; only process scheduling needs a narrow fake for a genuinely suspended start.
- `async.system` must mark process completion before scheduling its continuation so duplicated system callbacks cannot resume a coroutine twice.

## Repo Conventions Discovered
- Public setup is process-scoped in the isolated test harness, so lifecycle tests call `review.lua` directly while one plugin test owns setup assertions.

## Things Future Specs Should Know
- Keep cancellation separate from validated diff-load options; Git repository method signatures remain stable by retaining the operation on `GitRepo`.
- Treat multi-command public setup as a transaction: retain the configuration marker only after every command is registered and remove only resources acquired by the failed attempt.
