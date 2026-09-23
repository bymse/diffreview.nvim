local async_operation = require('diffreview.async_operation')
local diffs = require('diffreview.diffs')
local ui = require('diffreview.ui')

---@class StartingReview
---@field kind 'starting'
---@field operation AsyncOperation
---@class ActiveReview
---@field kind 'active'
---@field loaded LoadedDiffs
---@field ui ReviewUi
---@alias ReviewState { kind: 'idle' }|StartingReview|ActiveReview

local M = {}

---@class ReviewSession
---@field config Config
---@field state ReviewState
local ReviewSession = {}
ReviewSession.__index = ReviewSession

---@param message string
---@param level integer
---@return nil
local function notify(message, level)
  vim.notify(message, level)
end

---@param session ReviewSession
---@param operation AsyncOperation
---@return boolean
local function is_current(session, operation)
  return session.state.kind == 'starting'
    and session.state.operation == operation
    and not async_operation.is_canceled(operation)
end

---@param session ReviewSession
---@param operation AsyncOperation
---@param review_ui ReviewUi|nil
---@param message string
---@return nil
local function fail_start(session, operation, review_ui, message)
  if review_ui ~= nil then
    pcall(review_ui.cleanup, review_ui)
  end
  if is_current(session, operation) then
    session.state = { kind = 'idle' }
    notify(message, vim.log.levels.ERROR)
  end
end

---@param options DiffLoadOptions
---@return nil
function ReviewSession:start(options)
  if self.state.kind ~= 'idle' then
    notify('A review is already starting or active', vim.log.levels.ERROR)
    return
  end

  local operation = async_operation.new()
  self.state = { kind = 'starting', operation = operation }
  local running = coroutine.create(function()
    local review_ui
    local ok, err = xpcall(function()
      local result, loaded = diffs.load_review(options, operation)
      if not is_current(self, operation) then
        return
      end
      if not result.ok then
        if result.error ~= nil and result.error.kind == 'canceled' then
          return
        end
        fail_start(self, operation, review_ui, result.error and result.error.message or 'Unable to load review')
        return
      end
      if loaded == nil then
        fail_start(self, operation, review_ui, 'Unable to load review')
        return
      end
      if #loaded.files == 0 then
        self.state = { kind = 'idle' }
        notify('No changes to review', vim.log.levels.INFO)
        return
      end
      review_ui = ui.get_ui()
      if not is_current(self, operation) then
        review_ui:cleanup()
        return
      end
      review_ui:show_review_files(loaded.files)
      if not is_current(self, operation) then
        review_ui:cleanup()
        return
      end
      self.state = { kind = 'active', loaded = loaded, ui = review_ui }
    end, debug.traceback)
    if not ok then
      fail_start(self, operation, review_ui, tostring(err))
    end
  end)
  local resumed, err = coroutine.resume(running)
  if not resumed then
    fail_start(self, operation, nil, tostring(err))
  end
end

---@return nil
function ReviewSession:stop()
  if self.state.kind == 'idle' then
    notify('No review is active', vim.log.levels.INFO)
    return
  end
  if self.state.kind == 'starting' then
    local operation = self.state.operation
    self.state = { kind = 'idle' }
    async_operation.cancel(operation)
    notify('Review start canceled', vim.log.levels.INFO)
    return
  end

  local active = self.state
  self.state = { kind = 'idle' }
  local ok, err = pcall(active.ui.cleanup, active.ui)
  if ok then
    notify('Review stopped', vim.log.levels.INFO)
  else
    notify(tostring(err), vim.log.levels.ERROR)
  end
end

---@param config Config
---@return ReviewSession
function M.new(config)
  return setmetatable({ config = config, state = { kind = 'idle' } }, ReviewSession)
end

return M
