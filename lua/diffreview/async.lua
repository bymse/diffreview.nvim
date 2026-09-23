local M = {}

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
