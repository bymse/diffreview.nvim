local M = {}

---@class AsyncOperation
---@field canceled boolean

---@return AsyncOperation
function M.new()
  return { canceled = false }
end

---@param operation AsyncOperation
---@return nil
function M.cancel(operation)
  operation.canceled = true
end

---@param operation AsyncOperation|nil
---@return boolean
function M.is_canceled(operation)
  return operation ~= nil and operation.canceled
end

return M
