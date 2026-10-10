local async_operation = require('diffreview.async_operation')
local diffs = require('diffreview.diffs')
local ui = require('diffreview.ui')
local storage = require('diffreview.storage')
local review_progress = require('diffreview.review_progress')
local quickfix = require('diffreview.ui.quickfix')

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
---@field selected_id string|nil
---@field selected_presented boolean
---@field progress ReviewProgress
---@field options DiffLoadOptions
---@field refresh_request AsyncOperation|nil
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

  if active.refresh_request then
    async_operation.cancel(active.refresh_request)
    active.refresh_request = nil
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
      if diff.operation ~= 'error' and is_selection_current(session, active, request) then
        active.selected_id = file_id
        active.selected_presented = true
      elseif is_selection_current(session, active, request) then
        active.selected_presented = false
      end
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
    if state.refresh_request then
      async_operation.cancel(state.refresh_request)
    end
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
  local options_copy =
    { cwd = vim.fn.fnamemodify(options.cwd or vim.fn.getcwd(), ':p'), from = options.from, to = options.to }
  self.state = { kind = 'starting', operation = operation }
  local running = coroutine.create(function()
    local review_ui
    local ok, err = xpcall(function()
      local result, loaded = diffs.load_diffs(options_copy, operation)
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
      local previous, load_error = storage.load(loaded.storage_path, loaded.identity)
      if load_error then
        fail_start(self, operation, review_ui, load_error)
        return
      end
      local progress = review_progress.reconcile(previous, loaded)
      if (#loaded.files > 0 or previous ~= nil) and is_start_operation_current(self, operation) then
        local saved, save_error = storage.save(loaded.storage_path, progress)
        if not saved then
          fail_start(self, operation, review_ui, save_error or 'Unable to save review state')
          return
        end
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
        progress = progress,
        ui = review_ui,
        operation = operation,
        selection_request = nil,
        selected_id = nil,
        selected_presented = false,
        options = options_copy,
        refresh_request = nil,
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

---@param file_id string
---@return nil
function ReviewSession:select_file(file_id)
  select_file(self, file_id)
end

---@param preloaded LoadedDiffs|nil
---@return boolean, string|nil
function ReviewSession:refresh(preloaded)
  local active = self.state
  if active.kind ~= 'active' or async_operation.is_canceled(active.operation) then
    return false, 'Review refresh unavailable'
  end
  if active.refresh_request then
    async_operation.cancel(active.refresh_request)
  end
  active.selection_request = nil
  local request = async_operation.new()
  active.refresh_request = request
  local function current()
    return self.state == active and active.refresh_request == request and not async_operation.is_canceled(request)
  end
  local function perform()
    local ok, err = xpcall(function()
      local result, loaded
      if preloaded ~= nil then
        result, loaded = { ok = true }, preloaded
      else
        result, loaded = diffs.load_diffs(active.options, request)
      end
      if not current() then
        return
      end
      if not result.ok or loaded == nil then
        error(result.error and result.error.message or 'Unable to load review')
      end
      if
        not vim.deep_equal(loaded.identity, active.loaded.identity)
        or loaded.storage_path ~= active.loaded.storage_path
      then
        error('Review identity changed; start a new review')
      end
      local candidate = review_progress.reconcile(active.progress, loaded)
      local selected = active.selected_id
      local diff
      if selected ~= nil and loaded.entries_by_id[selected] ~= nil then
        local snapshot
        diff, snapshot = diffs.load_selected_view(loaded, selected, request, true)
        if not current() then
          return
        end
        if
          diff == nil
          or diff.operation == 'error'
          or not diffs.selected_fingerprint_matches(loaded, selected, request, snapshot)
        then
          error('Unable to load matching selected review content')
        end
      end
      if not current() then
        return
      end
      local saved, save_error = storage.save(loaded.storage_path, candidate)
      if not saved then
        error(save_error or 'Unable to save review state')
      end
      if not current() then
        return
      end
      local drawer_open = active.ui:files_open()
      active.loaded = loaded
      active.progress = candidate
      active.selected_id = selected ~= nil and loaded.entries_by_id[selected] ~= nil and selected or nil
      if selected ~= nil and diff == nil then
        active.selected_presented = false
        active.ui:clear_selected_diff()
        active.ui:show_review_files(loaded.files)
      else
        active.ui:update_review_files(loaded.files)
        if diff ~= nil then
          active.ui:refresh_selected_diff(diff, self.config.layout)
        end
        if drawer_open and not active.ui:files_open() then
          active.ui:show_review_files(loaded.files)
        end
      end
    end, debug.traceback)
    if not ok and current() then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
    if active.refresh_request == request then
      active.refresh_request = nil
    end
  end
  if preloaded ~= nil then
    perform()
    return true, nil
  end
  local running = coroutine.create(perform)
  local resumed, err = coroutine.resume(running)
  if not resumed and current() then
    active.refresh_request = nil
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
  return true, nil
end

---@return boolean, string|nil
function ReviewSession:toggle_files()
  local active = self.state
  if active.kind ~= 'active' or not active.ui:toggle_review_files(active.loaded.files) then
    return false, 'Review files unavailable'
  end
  return true, nil
end

---@param viewed boolean
---@return boolean, string|nil
function ReviewSession:mark_selected(viewed)
  local active = self.state
  if active.kind ~= 'active' then
    return false, 'No active review'
  end
  local context, id = active.ui:mark_context()
  if context == nil then
    return false, 'No review files in this context'
  end
  if context == 'quickfix' then
    return self:mark_files({ assert(id) }, viewed)
  end
  if
    active.selection_request ~= nil
    or active.selected_id == nil
    or not active.selected_presented
    or active.loaded.entries_by_id[active.selected_id] == nil
  then
    return false, 'No selected review file'
  end
  local selected = active.selected_id
  local ordered = quickfix.ordered_ids(active.loaded.files)
  local saved, err = self:mark_files({ selected }, viewed)
  if not saved then
    return false, err
  end
  if viewed then
    local position
    for index, id in ipairs(ordered) do
      if id == selected then
        position = index
        break
      end
    end
    if position then
      for step = 1, #ordered - 1 do
        local id = ordered[(position + step - 1) % #ordered + 1]
        for _, file in ipairs(active.loaded.files) do
          if file.id == id and not file.viewed then
            select_file(self, id)
            return true, nil
          end
        end
      end
    end
  end
  return true, nil
end

---@param file_ids string[]
---@param viewed boolean
---@return boolean, string|nil
function ReviewSession:mark_files(file_ids, viewed)
  local active = self.state
  if active.kind ~= 'active' or async_operation.is_canceled(active.operation) then
    return false, 'No active review'
  end
  if type(file_ids) ~= 'table' or type(viewed) ~= 'boolean' then
    return false, 'Invalid progress request'
  end
  for _, id in ipairs(file_ids) do
    if active.loaded.entries_by_id[id] == nil then
      return false, 'File is not in the current comparison'
    end
  end
  if active.refresh_request then
    async_operation.cancel(active.refresh_request)
    active.refresh_request = nil
  end
  local candidate = vim.deepcopy(active.progress)
  local requested = {}
  for _, id in ipairs(file_ids) do
    requested[id] = true
  end
  for _, record in ipairs(candidate.files) do
    if requested[record.id] then
      record.viewed_fingerprint = viewed and record.fingerprint or nil
    end
  end
  local saved, err = storage.save(active.loaded.storage_path, candidate)
  if not saved then
    return false, err
  end
  active.progress = candidate
  for _, summary in ipairs(active.loaded.files) do
    if requested[summary.id] then
      summary.viewed = viewed
    end
  end
  active.ui:update_review_files(active.loaded.files)
  return true, nil
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
