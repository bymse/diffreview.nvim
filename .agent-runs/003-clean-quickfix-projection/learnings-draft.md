# Learnings Draft: 003-clean-quickfix-projection

## Durable Findings
- Quickfix history lists share a quickfix buffer; the currently selected stable list ID identifies the list displayed by current-tab quickfix windows, while before/after stable window-ID sets identify a `copen` window introduced during a failed display.

## Repo Conventions Discovered
- Integration tests can inject narrow display failures by temporarily wrapping `vim.cmd`, calling the original command, then raising an error and restoring the callable through `xpcall` cleanup.

## Things Future Specs Should Know
- Preserve quickfix ownership by exact context equality and stable list IDs; never infer it from title, current history position, or buffer identity.
