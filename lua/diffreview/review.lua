local async = require('diffreview.async')
local diffs = require('diffreview.diffs')
local ui = require('diffreview.ui')

---@class ReviewStartOptions
---@field cwd string|nil
---@field from string|nil
---@field to string|nil

---@class StartingReview
---@field kind 'starting'
---@field operation AsyncOperation
---@class ActiveReview
---@field kind 'active'
---@field config Config
---@field loaded LoadedDiffs
---@field ui ReviewUi
---@alias ReviewState { kind: 'idle' }|StartingReview|ActiveReview

local M = {}
---@type ReviewState
local state = { kind = 'idle' }

---@param message string
---@param level integer
---@return nil
local function notify(message, level)
  vim.notify(message, level)
end

---@param options any
---@return DiffLoadOptions|nil
local function validate_options(options)
  if type(options) ~= 'table' then
    return nil
  end
  for key, value in pairs(options) do
    if (key ~= 'cwd' and key ~= 'from' and key ~= 'to') or type(value) ~= 'string' or value == '' then
      return nil
    end
  end
  if options.to ~= nil and options.from == nil then
    return nil
  end
  return options
end

---@param operation AsyncOperation
---@return boolean
local function is_current(operation)
  return state.kind == 'starting' and state.operation == operation and not async.is_canceled(operation)
end

---@param operation AsyncOperation
---@param review_ui ReviewUi|nil
---@param message string
---@return nil
local function fail_start(operation, review_ui, message)
  if review_ui ~= nil then
    pcall(review_ui.cleanup, review_ui)
  end
  if is_current(operation) then
    state = { kind = 'idle' }
    notify(message, vim.log.levels.ERROR)
  end
end

---@param config Config
---@param options ReviewStartOptions
---@return nil
function M.start(config, options)
  local valid_options = validate_options(options)
  if valid_options == nil then
    notify('Invalid review start options', vim.log.levels.ERROR)
    return
  end
  if state.kind ~= 'idle' then
    notify('A review is already starting or active', vim.log.levels.ERROR)
    return
  end

  local operation = async.new_operation()
  state = { kind = 'starting', operation = operation }
  local running = coroutine.create(function()
    local review_ui
    local ok, err = xpcall(function()
      local result, loaded = diffs.load_review(valid_options, operation)
      if not is_current(operation) then
        return
      end
      if not result.ok then
        if result.error ~= nil and result.error.kind == 'canceled' then
          return
        end
        fail_start(operation, review_ui, result.error and result.error.message or 'Unable to load review')
        return
      end
      if loaded == nil then
        fail_start(operation, review_ui, 'Unable to load review')
        return
      end
      if #loaded.files == 0 then
        state = { kind = 'idle' }
        notify('No changes to review', vim.log.levels.INFO)
        return
      end
      review_ui = ui.get_ui()
      if not is_current(operation) then
        review_ui:cleanup()
        return
      end
      review_ui:show_review_files(loaded.files)
      if not is_current(operation) then
        review_ui:cleanup()
        return
      end
      state = { kind = 'active', config = config, loaded = loaded, ui = review_ui }
    end, debug.traceback)
    if not ok then
      fail_start(operation, review_ui, tostring(err))
    end
  end)
  local resumed, err = coroutine.resume(running)
  if not resumed then
    fail_start(operation, nil, tostring(err))
  end
end

---@return nil
function M.stop()
  if state.kind == 'idle' then
    notify('No review is active', vim.log.levels.INFO)
    return
  end
  if state.kind == 'starting' then
    local operation = state.operation
    state = { kind = 'idle' }
    async.cancel(operation)
    notify('Review start canceled', vim.log.levels.INFO)
    return
  end

  local active = state
  state = { kind = 'idle' }
  local ok, err = pcall(active.ui.cleanup, active.ui)
  if ok then
    notify('Review stopped', vim.log.levels.INFO)
  else
    notify(tostring(err), vim.log.levels.ERROR)
  end
end

return M
