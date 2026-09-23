local M = {}

---@class AsyncOperation
---@field canceled boolean
---@field process vim.SystemObj|nil

---@return AsyncOperation
function M.new_operation()
  return { canceled = false, process = nil }
end

---@param operation AsyncOperation
---@return nil
function M.cancel(operation)
  operation.canceled = true
  if operation.process ~= nil then
    pcall(operation.process.kill, operation.process, 15)
  end
end

---@param operation AsyncOperation|nil
---@return boolean
function M.is_canceled(operation)
  return operation ~= nil and operation.canceled
end

---@param cmd string[]
---@param opts vim.SystemOpts|nil
---@param operation AsyncOperation|nil
---@return vim.SystemCompleted
function M.system(cmd, opts, operation)
  local running = assert(coroutine.running(), 'async.system must be called inside coroutine')
  if M.is_canceled(operation) then
    return { code = -1, signal = 0, stdout = '', stderr = '', canceled = true }
  end

  local completed = false
  local process
  process = vim.system(cmd, opts or {}, function(result)
    if completed then
      return
    end
    completed = true
    vim.schedule(function()
      if operation ~= nil and operation.process == process then
        operation.process = nil
      end
      if coroutine.status(running) == 'suspended' then
        coroutine.resume(running, result)
      end
    end)
  end)
  if operation ~= nil then
    operation.process = process
  end

  return coroutine.yield()
end

return M
