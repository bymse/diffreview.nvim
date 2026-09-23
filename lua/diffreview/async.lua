local M = {}

---@class AsyncOperation
---@field canceled boolean

---@return AsyncOperation
function M.new_operation()
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

---@param cmd string[]
---@param opts vim.SystemOpts|nil
---@return vim.SystemCompleted
function M.system(cmd, opts)
  local running = assert(coroutine.running(), 'async.system must be called inside coroutine')

  local completed = false
  vim.system(cmd, opts or {}, function(result)
    if completed then
      return
    end
    completed = true
    vim.schedule(function()
      if coroutine.status(running) == 'suspended' then
        coroutine.resume(running, result)
      end
    end)
  end)
  return coroutine.yield()
end

return M
