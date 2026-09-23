# Learnings Draft: 002-own-quickfix-projection

## Durable Findings
- Neovim quickfix list updates retain the supplied context when `setqflist` is called with the existing list ID and update action.

## Repo Conventions Discovered
- Quickfix projection tests reset global quickfix state locally and inspect list metadata through `vim.fn.getqflist`.

## Things Future Specs Should Know
- Spec 003 should use `ReviewUi.quickfix_id` and `ReviewUi.quickfix_context` to validate ownership before cleanup; it must not infer ownership from the current quickfix list.
