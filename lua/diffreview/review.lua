local async_operation = require('diffreview.async_operation')
local diffs = require('diffreview.diffs')
local ui = require('diffreview.ui')
local storage = require('diffreview.storage')
local review_progress = require('diffreview.review_progress')
local files_list = require('diffreview.ui.quickfix.files_list')
local comments = require('diffreview.comments')
local comment_editor = require('diffreview.ui.comment_editor')

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
---@field comments Comments
---@field options DiffLoadOptions
---@field refresh_request AsyncOperation|nil
---@field editor CommentEditor|nil
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
local function select_file(session, file_id, comment)
  local active = session.state
  if active.kind ~= 'active' then
    return
  end
  if active.editor and active.editor.saving then
    vim.notify('Comment save is pending', vim.log.levels.ERROR)
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
      local diff = diffs.load_selected_view_model(active.loaded, file_id, active.operation)
      if diff == nil or not is_selection_current(session, active, request) then
        return
      end
      active.ui:display_diff_side_by_side(diff, session.config.layout, nil, file_id)
      if diff.operation ~= 'error' and is_selection_current(session, active, request) then
        active.selected_id = file_id
        active.selected_presented = true
        active.ui:update_review_comments(active.progress.comments, active.progress.files)
        if comment then
          active.ui:focus_comment(comment)
        end
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
    if state.editor then
      state.editor:cleanup()
    end
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

---@param loaded LoadedDiffs
---@param id string
---@param operation AsyncOperation
---@param current fun(): boolean
---@return DiffViewModel|nil
local function load_matching_view_model(loaded, id, operation, current)
  local diff, snapshot, nontext = diffs.load_selected_view_model(loaded, id, operation, true)
  if not current() then
    return nil
  end
  local metadata = loaded.entries_by_id[id].git_diff
  local submodule = metadata and (metadata.old_mode == '160000' or metadata.new_mode == '160000')
  if diff == nil or (diff.operation == 'error' and not (submodule and nontext)) then
    error('Unable to load comparison content')
  end
  local matches = diffs.selected_fingerprint_matches(loaded, id, operation, snapshot)
  if not current() then
    return nil
  end
  if not matches then
    error('Comparison content changed')
  end
  return diff
end

---@param loaded LoadedDiffs
---@param records CommentLocation[]
---@param operation AsyncOperation
---@param current fun(): boolean
---@return table<string, DiffViewModel>|nil
local function load_comment_view_models(loaded, records, operation, current)
  local view_models_by_file_id, seen = {}, {}
  for _, record in ipairs(records) do
    local id = record.file_id
    local entry = loaded.entries_by_id[id]
    if record.start_line ~= nil and entry ~= nil and not seen[id] then
      seen[id] = true
      local diff = load_matching_view_model(loaded, id, operation, current)
      if diff == nil then
        return nil
      end
      view_models_by_file_id[id] = diff
    end
  end
  return view_models_by_file_id
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
      local view_models_by_file_id = load_comment_view_models(
        loaded,
        previous and previous.comments or {},
        operation,
        function()
          return is_start_operation_current(self, operation)
        end
      )
      if view_models_by_file_id == nil or not is_start_operation_current(self, operation) then
        return
      end
      local progress = review_progress.reconcile(previous, loaded, view_models_by_file_id)
      if
        (#loaded.files > 0 or previous ~= nil)
        and not vim.deep_equal(previous, progress)
        and is_start_operation_current(self, operation)
      then
        local saved, save_error = storage.save(loaded.storage_path, progress)
        if not saved then
          fail_start(self, operation, review_ui, save_error or 'Unable to save review state')
          return
        end
      end
      if #loaded.files == 0 and #progress.comments == 0 then
        self.state = { kind = 'idle' }
        vim.notify('No changes to review', vim.log.levels.INFO)
        return
      end
      local function comment_handler(action)
        return function(id)
          coroutine.wrap(function()
            local active = self.state
            if active.kind ~= 'active' or (active.editor and active.editor:blocked()) then
              vim.notify('Save or close the comment editor', vim.log.levels.ERROR)
              return
            end
            local accepted, action_error = action(self, id)
            if not accepted then
              vim.notify(action_error or 'Comment action unavailable', vim.log.levels.ERROR)
            end
          end)()
        end
      end
      review_ui = ui.get_ui({
        on_comment_navigate = comment_handler(self.navigate_comment),
        on_comment_edit = comment_handler(self.edit_comment_by_id),
        on_comment_delete = comment_handler(self.delete_comment),
        on_comment_toggle_resolution = comment_handler(self.toggle_comment_resolution),
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
        comments = comments.new(progress.comments),
        ui = review_ui,
        operation = operation,
        selection_request = nil,
        selected_id = nil,
        selected_presented = false,
        options = options_copy,
        refresh_request = nil,
      }
      review_ui:update_review_comments(progress.comments, progress.files)
      if #loaded.files == 0 then
        review_ui:show_review_comments(progress.comments)
      end
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
  if active.editor and active.editor:blocked() then
    return false, 'Save or close the comment editor before refreshing'
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
      local view_models_by_file_id = load_comment_view_models(loaded, active.progress.comments, request, current)
      if view_models_by_file_id == nil or not current() then
        return
      end
      local candidate = review_progress.reconcile(active.progress, loaded, view_models_by_file_id)
      local selected = active.selected_id
      local diff
      if selected ~= nil and loaded.entries_by_id[selected] ~= nil then
        diff = view_models_by_file_id[selected] or load_matching_view_model(loaded, selected, request, current)
        if not current() then
          return
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
      local files_open, comments_open = active.ui:files_open(), active.ui:comments_open()
      active.loaded = loaded
      active.progress = candidate
      active.comments = comments.new(candidate.comments)
      active.selected_id = selected ~= nil and loaded.entries_by_id[selected] ~= nil and selected or nil
      if selected ~= nil and diff == nil then
        active.selected_presented = false
        active.ui:clear_selected_diff()
      end
      active.ui:update_review_files(loaded.files)
      if diff ~= nil then
        active.selected_presented = diff.operation ~= 'error'
        active.ui:refresh_selected_diff(diff, self.config.layout, selected)
      end
      active.ui:update_review_comments(candidate.comments, candidate.files)
      if #loaded.files == 0 and #candidate.comments > 0 then
        active.ui:show_review_comments(candidate.comments)
      elseif comments_open then
        active.ui:show_review_comments(candidate.comments)
      elseif files_open then
        active.ui:show_review_files(loaded.files)
      elseif selected ~= nil and diff == nil and #candidate.comments == 0 then
        active.ui:show_review_files(loaded.files)
      end
    end, debug.traceback)
    if not ok and current() then
      vim.notify(tostring(err), vim.log.levels.ERROR)
    end
    if active.refresh_request == request then
      active.refresh_request = nil
    end
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
function ReviewSession:toggle_comments()
  local active = self.state
  if active.kind ~= 'active' or not active.ui:toggle_review_comments(active.progress.comments) then
    return false, 'Review comments unavailable'
  end
  return true, nil
end

---@param session ReviewSession
---@param id string
---@return ReviewComment|nil, string|nil
local function actionable_comment(session, id)
  local active = session.state
  if active.kind ~= 'active' or (active.editor and active.editor:blocked()) then
    return nil, 'Save or close the comment editor'
  end
  for _, candidate in ipairs(active.progress.comments) do
    if candidate.comment_id == id then
      return candidate, nil
    end
  end
  return nil, 'Unknown comment ID'
end

---@param id string
---@return boolean|nil, string|nil
function ReviewSession:navigate_comment(id)
  local record, err = actionable_comment(self, id)
  if not record then
    return nil, err
  end
  local active = self.state
  if active.kind == 'active' and active.loaded.entries_by_id[record.file_id] then
    select_file(self, record.file_id, vim.deepcopy(record))
  end
  return true, nil
end

---@param id string
---@return boolean|nil, string|nil
---Text comments must be reopened from a coroutine, like the comparison loader.
function ReviewSession:toggle_comment_resolution(id)
  local record, err = actionable_comment(self, id)
  if not record then
    return nil, err
  end
  local result
  if record.status == 'resolved' then
    result, err = self:reopen_comment(id)
  else
    result, err = self:resolve_comment(id)
  end
  return result ~= nil, err
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
  local ordered = files_list.ordered_ids(active.loaded.files)
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
  active.comments = comments.new(candidate.comments)
  for _, summary in ipairs(active.loaded.files) do
    if requested[summary.id] then
      summary.viewed = viewed
    end
  end
  active.ui:update_review_files(active.loaded.files)
  active.ui:update_review_comments(active.progress.comments, active.progress.files)
  return true, nil
end

---@param session ReviewSession
---@param prepare fun(state: Comments, context: CommentCaptureContext, view_models_by_file_id: table<string, DiffViewModel>): (ReviewComment|boolean|nil, string|nil)
---@param id string|nil
---@param preview_lines string[]|nil
---@return ReviewComment|boolean|nil, string|nil
local function mutate_comment(session, prepare, id, preview_lines, editor_write, invalidate, verify_record)
  local active = session.state
  if active.kind ~= 'active' then
    return nil, 'No active review'
  end
  if not editor_write and active.editor and active.editor:blocked() then
    return nil, 'Save or close the comment editor'
  end
  local loaded, progress, selected = active.loaded, active.progress, active.selected_id
  local function current()
    return session.state == active
      and not async_operation.is_canceled(active.operation)
      and active.selection_request == nil
      and active.refresh_request == nil
      and active.loaded == loaded
      and active.progress == progress
      and active.selected_id == selected
      and (editor_write or active.editor == nil or not active.editor:blocked())
      and (active.editor == nil or not active.editor.saving or active.editor:valid())
  end
  if not current() then
    return nil, 'Review mutation unavailable'
  end
  ---@type CommentCaptureContext
  local context = {
    loaded = loaded,
    selected_id = selected,
    selected_presented = active.selected_presented,
    preview_lines = preview_lines,
    load_current_view = function(file_id)
      local diff, snapshot = diffs.load_selected_view_model(loaded, file_id, active.operation, true)
      if not current() then
        return nil, 'Review changed during comment loading'
      end
      if
        diff == nil
        or diff.operation == 'error'
        or not diffs.selected_fingerprint_matches(loaded, file_id, active.operation, snapshot)
      then
        return nil, 'Comparison content changed; refresh the review'
      end
      if not current() then
        return nil, 'Review changed during comment loading'
      end
      return diff, nil
    end,
    text_matches = function(file_id, lines)
      return current() and active.selected_presented and active.ui:comment_text_matches(file_id, 'current', lines)
    end,
  }
  ---@type table<string, DiffViewModel>|nil
  local view_models_by_file_id = {}
  if verify_record then
    local record
    for _, item in ipairs(progress.comments) do
      if item.comment_id == id then
        record = item
        break
      end
    end
    if not record then
      return nil, 'Unknown comment ID'
    end
    local ok, result = pcall(load_comment_view_models, loaded, { record }, active.operation, current)
    if not ok or result == nil then
      return nil, 'Unable to verify comment location; refresh the review'
    end
    view_models_by_file_id = result
    local view = view_models_by_file_id[record.file_id]
    local version = view and view.current
    if
      editor_write
      and selected == record.file_id
      and active.selected_presented
      and version
      and version.content.kind == 'text'
      and version.content.source == 'snapshot'
      and not active.ui:comment_text_matches(record.file_id, 'current', version.content.lines)
    then
      return nil, 'Displayed text does not match the comparison'
    end
  end
  local comment_state = active.comments:fork()
  local result, err = prepare(comment_state, context, assert(view_models_by_file_id))
  if result == nil then
    return nil, err
  end
  if not current() then
    return nil, 'Review changed during comment loading'
  end
  local candidate = vim.deepcopy(progress)
  candidate.comments = comment_state.records
  local saved, save_error = storage.save(loaded.storage_path, candidate)
  if not saved then
    return nil, save_error
  end
  active.progress = candidate
  active.comments = comment_state
  if invalidate and id ~= nil then
    if not editor_write and active.editor and active.editor.comment_id == id then
      active.editor:cleanup()
      active.editor = nil
    end
  end
  active.ui:update_review_files(active.loaded.files)
  active.ui:update_review_comments(candidate.comments, candidate.files)
  return result, nil
end

---@param location CommentLocation
---@param body string
---@return ReviewComment|nil, string|nil
---Text locations must be called from a coroutine, like the comparison loader.
function ReviewSession:add_comment(location, body)
  local result, err = mutate_comment(self, function(state, context)
    return state:add(location, body, context)
  end)
  ---@cast result ReviewComment|nil
  return result, err
end

---@param id string
---@param body string
---@return ReviewComment|nil, string|nil
---Stale text comments must be edited from a coroutine, like the comparison loader.
function ReviewSession:edit_comment(id, body)
  local active = self.state
  if active.kind ~= 'active' then
    return nil, 'No active review'
  end
  local stale = false
  for _, record in ipairs(active.progress.comments) do
    if record.comment_id == id then
      stale = record.status == 'stale'
      break
    end
  end
  local result, err = mutate_comment(self, function(state, _, view_models_by_file_id)
    return state:edit(id, body, active.loaded, view_models_by_file_id)
  end, id, nil, false, false, stale)
  ---@cast result ReviewComment|nil
  return result, err
end

---@param id string
---@return boolean|nil, string|nil
function ReviewSession:delete_comment(id)
  local result, err = mutate_comment(self, function(state)
    return state:delete(id)
  end, id, nil, false, true)
  ---@cast result boolean|nil
  return result, err
end

---@param id string
---@return ReviewComment|nil, string|nil
function ReviewSession:resolve_comment(id)
  local result, err = mutate_comment(self, function(state)
    return state:resolve(id)
  end, id)
  ---@cast result ReviewComment|nil
  return result, err
end

---@param id string
---@return ReviewComment|nil, string|nil
---Text comments must be reopened from a coroutine, like the comparison loader.
function ReviewSession:reopen_comment(id)
  local active = self.state
  if active.kind ~= 'active' then
    return nil, 'No active review'
  end
  local result, err = mutate_comment(self, function(state, _, view_models_by_file_id)
    return state:reopen(id, active.loaded, view_models_by_file_id)
  end, id, nil, false, false, true)
  ---@cast result ReviewComment|nil
  return result, err
end

---@param session ReviewSession
---@param target CommentLocation
---@param id string|nil
---@param body string
---@return boolean|nil, string|nil
local function open_editor(session, target, id, body)
  local active = session.state
  if active.kind ~= 'active' or async_operation.is_canceled(active.operation) then
    return nil, 'No active review'
  end
  if active.selection_request or active.refresh_request then
    return nil, 'Review context is changing'
  end
  local editor = active.editor
  if editor then
    if
      editor:valid()
      and ((id == nil and vim.deep_equal(editor.target, target)) or (id ~= nil and editor.comment_id == id))
    then
      editor:focus()
      return true, nil
    end
    if editor:blocked() then
      return nil, 'Save or close the current comment editor'
    end
  end
  local comparison = active.loaded
  local progress = active.progress
  local function current()
    return session.state == active
      and active.loaded == comparison
      and active.progress == progress
      and active.editor == editor
      and not async_operation.is_canceled(active.operation)
      and active.selection_request == nil
      and active.refresh_request == nil
      and (editor == nil or not editor:blocked())
  end
  local view_models_by_file_id = {}
  if id ~= nil then
    local ok, loaded_view_models_by_file_id =
      pcall(load_comment_view_models, comparison, { target }, active.operation, current)
    if not ok or loaded_view_models_by_file_id == nil or not current() then
      return nil, 'Unable to verify comment location; refresh the review'
    end
    view_models_by_file_id = loaded_view_models_by_file_id
  end
  local preview =
    { target.file_id .. (target.start_line and (':' .. target.start_line .. '-' .. target.end_line) or '') }
  local view = view_models_by_file_id[target.file_id]
  local version = view and view.current
  local preview_lines
  if id == nil and target.start_line then
    preview_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  elseif version and version.content.kind == 'text' and version.content.source == 'snapshot' then
    preview_lines = version.content.lines
  end
  if target.start_line then
    if preview_lines and target.end_line <= #preview_lines then
      for line = target.start_line, target.end_line do
        preview[#preview + 1] = line .. ': ' .. preview_lines[line]
      end
    else
      preview[#preview + 1] = 'Location unavailable; saving will not reopen a stale comment.'
    end
  elseif comparison.entries_by_id[target.file_id] == nil then
    preview[#preview + 1] = 'File unavailable; saving will not reopen a stale comment.'
  end
  if editor and editor:valid() then
    editor:cleanup()
  end
  active.editor = comment_editor.open(assert(active.ui.tabpage), target, id, body, preview, function(draft, text)
    if
      session.state ~= active
      or async_operation.is_canceled(active.operation)
      or draft.detached
      or active.editor ~= draft
    then
      return nil, 'Comment editor no longer owns an active review'
    end
    if (draft.comment_id == nil or draft.target.start_line ~= nil) and active.loaded ~= comparison then
      return nil, 'Comment comparison changed; open a new editor'
    end
    local result, err
    if vim.trim(text) == '' then
      if draft.comment_id ~= nil then
        result, err = mutate_comment(session, function(state)
          return state:delete(draft.comment_id)
        end, draft.comment_id, nil, true, true)
        if not result then
          return nil, err
        end
        draft.comment_id = nil
      end
      return true, nil
    elseif draft.comment_id ~= nil then
      local stale = false
      for _, record in ipairs(active.progress.comments) do
        if record.comment_id == draft.comment_id then
          stale = record.status == 'stale'
          break
        end
      end
      result, err = mutate_comment(session, function(state, _, view_models_by_file_id)
        return state:edit(draft.comment_id, text, active.loaded, view_models_by_file_id)
      end, draft.comment_id, nil, true, false, stale)
    else
      result, err = mutate_comment(session, function(state, context)
        return state:add(draft.target, text, context)
      end, nil, preview_lines, true)
    end
    if not result then
      return nil, err
    end
    ---@cast result ReviewComment
    draft.comment_id = result.comment_id
    return true, nil
  end)
  return true, nil
end

---@param first integer|nil
---@param last integer|nil
---@return boolean|nil, string|nil
function ReviewSession:open_comment_editor(first, last)
  local active = self.state
  if active.kind ~= 'active' then
    return nil, 'No active review'
  end
  local location = active.ui:comment_context(first, last)
  if location == nil or active.loaded.entries_by_id[location.file_id] == nil then
    return nil, 'No owned review location'
  end
  if location.start_line ~= nil and (not active.selected_presented or active.selected_id ~= location.file_id) then
    return nil, 'No presented review text'
  end
  return open_editor(self, location, nil, '')
end

---@param id string
---@return boolean|nil, string|nil
---Text comments must be opened from a coroutine, like the comparison loader.
function ReviewSession:edit_comment_by_id(id)
  local active = self.state
  if active.kind ~= 'active' then
    return nil, 'No active review'
  end
  for _, record in ipairs(active.progress.comments) do
    if record.comment_id == id then
      return open_editor(self, {
        file_id = record.file_id,
        start_line = record.start_line,
        end_line = record.end_line,
      }, id, record.body)
    end
  end
  return nil, 'Unknown comment ID'
end

---@return nil
function ReviewSession:stop()
  if self.state.kind == 'idle' then
    vim.notify('No review is active', vim.log.levels.INFO)
    return
  end
  if self.state.kind == 'active' and self.state.editor and self.state.editor:blocked() then
    vim.notify('Save or close the comment editor before stopping', vim.log.levels.ERROR)
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
