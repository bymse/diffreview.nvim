local async_operation = require('diffreview.async_operation')
local diffs = require('diffreview.diffs')
local ui = require('diffreview.ui')

---@class StartingReview
---@field kind 'starting'
---@field operation AsyncOperation
---@field ui ReviewUi|nil
---@class ActiveReview
---@field kind 'active'
---@field loaded LoadedDiffs
---@field ui ReviewUi
---@field operation AsyncOperation
---@field selection_request table|nil
---@alias ReviewState { kind: 'idle' }|StartingReview|ActiveReview

local M = {}

---@class ReviewSession
---@field config Config
---@field state ReviewState
local ReviewSession = {}
ReviewSession.__index = ReviewSession

---@param session ReviewSession
---@param operation AsyncOperation
---@return boolean
local function is_start_operation_current(session, operation)
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
  if is_start_operation_current(session, operation) then
    session.state = { kind = 'idle' }
    vim.notify(message, vim.log.levels.ERROR)
  end
end

---@param session ReviewSession
---@param active ActiveReview
---@param request table
---@return boolean
local function is_selection_current(session, active, request)
  return session.state == active
    and active.selection_request == request
    and not async_operation.is_canceled(active.operation)
end

---@param session ReviewSession
---@param file_id string
---@return nil
local function select_file(session, file_id)
  local active = session.state
  if active.kind ~= 'active' then
    return
  end
  if session.config.view == 'inline' then
    vim.notify('Inline review view is not supported', vim.log.levels.WARN)
    return
  end

  local request = {}
  active.selection_request = request

  local running = coroutine.create(function()
    local ok, err = xpcall(function()
      local diff = diffs.load_selected_view(active.loaded, file_id, active.operation)
      if diff == nil or not is_selection_current(session, active, request) then
        return
      end
      active.ui:display_diff_side_by_side(diff, session.config.layout)
    end, debug.traceback)
    if not ok and is_selection_current(session, active, request) then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
    if active.selection_request == request then
      active.selection_request = nil
    end
  end)
  local resumed, err = coroutine.resume(running)
  if not resumed and is_selection_current(session, active, request) then
    active.selection_request = nil
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

---@param session ReviewSession
---@param tab_closed boolean
---@return nil
local function stop_review(session, tab_closed)
  local state = session.state
  session.state = { kind = 'idle' }
  async_operation.cancel(state.operation)
  if state.kind == 'active' then
    state.selection_request = nil
  end
  local review_ui = state.ui
  local ok, err = true, nil
  if review_ui ~= nil then
    ok, err = pcall(review_ui.cleanup, review_ui)
  end
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
  if state.kind == 'starting' then
    vim.notify('Review start canceled', vim.log.levels.INFO)
  elseif ok or tab_closed then
    vim.notify('Review stopped', vim.log.levels.INFO)
  end
end

---@param options ReviewStartOptions
---@return nil
function ReviewSession:start(options)
  if self.state.kind ~= 'idle' then
    vim.notify('A review is already starting or active', vim.log.levels.ERROR)
    return
  end

  local operation = async_operation.new()
  self.state = { kind = 'starting', operation = operation }
  local running = coroutine.create(function()
    local review_ui
    local ok, err = xpcall(function()
      local result, loaded =
        diffs.load_diffs({ cwd = options.cwd or vim.fn.getcwd(), from = options.from, to = options.to }, operation)
      if not is_start_operation_current(self, operation) then
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
        vim.notify('No changes to review', vim.log.levels.INFO)
        return
      end
      review_ui = ui.get_ui({
        on_file_selected = function(file_id)
          select_file(self, file_id)
        end,
        on_tab_closed = function()
          local state = self.state
          if
            (state.kind == 'starting' and state.operation == operation and state.ui == review_ui)
            or (state.kind == 'active' and state.ui == review_ui)
          then
            stop_review(self, true)
          end
        end,
      })
      self.state.ui = review_ui
      if not is_start_operation_current(self, operation) then
        review_ui:cleanup()
        return
      end
      review_ui:show_review_files(loaded.files)
      if not is_start_operation_current(self, operation) then
        return
      end
      self.state = {
        kind = 'active',
        loaded = loaded,
        ui = review_ui,
        operation = operation,
        selection_request = nil,
      }
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
    vim.notify('No review is active', vim.log.levels.INFO)
    return
  end
  stop_review(self, false)
end

---@param config Config
---@return ReviewSession
function M.new(config)
  return setmetatable({ config = config, state = { kind = 'idle' } }, ReviewSession)
end

return M
