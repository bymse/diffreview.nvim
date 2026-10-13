local M = {}

---@class DecorationTracker
---@field decorated_buffers table<integer, table<integer, boolean>> Buffers keyed by namespace.

---@return DecorationTracker
function M.new_state()
  return { decorated_buffers = {} }
end

---@param state DecorationTracker
---@param namespace integer
---@param buffer integer
---@return nil
function M.track(state, namespace, buffer)
  state.decorated_buffers[namespace] = state.decorated_buffers[namespace] or {}
  state.decorated_buffers[namespace][buffer] = true
end

---@param state DecorationTracker
---@param namespace integer|nil Clear all tracked namespaces when omitted.
---@return nil
function M.clear(state, namespace)
  for tracked_namespace, buffers in pairs(state.decorated_buffers) do
    if namespace == nil or namespace == tracked_namespace then
      for buffer in pairs(buffers) do
        if vim.api.nvim_buf_is_valid(buffer) then
          vim.api.nvim_buf_clear_namespace(buffer, tracked_namespace, 0, -1)
        end
      end
      state.decorated_buffers[tracked_namespace] = nil
    end
  end
end

return M
