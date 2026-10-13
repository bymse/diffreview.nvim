local decorations = require('diffreview.ui.decorations')
local diff_information = require('diffreview.ui.diff_information')
local native_diff = require('diffreview.ui.native_diff')
local scratch_buffer = require('diffreview.ui.scratch_buffer')
local statusline = require('diffreview.ui.statusline')
local comment_decorations = require('diffreview.ui.comment_decorations')

local M = {}

local owner_variable = 'diffreview_side_by_side_owner'

---@param resource integer
---@param getter fun(integer, string): any
---@param instance_id integer
---@return boolean
local function is_owned(resource, getter, instance_id)
  local ok, value = pcall(getter, resource, owner_variable)
  return ok and value == instance_id
end

---@param state ReviewSideBySideState
---@param window integer|nil
---@param instance_id integer
---@return boolean
local function has_owned_window(state, window, instance_id)
  return window ~= nil and vim.api.nvim_win_is_valid(window) and is_owned(window, vim.api.nvim_win_get_var, instance_id)
end

---@param state ReviewSideBySideState
---@param instance_id integer
---@param release_active boolean
---@param active_window_lost boolean
---@return NativeDiffTransition
local function clear_previous_presentation(state, instance_id, release_active, active_window_lost)
  comment_decorations.clear(state.comments)
  if state.decorated_buffer ~= nil and vim.api.nvim_buf_is_valid(state.decorated_buffer) then
    decorations.clear(state.decorated_buffer, state.namespace)
  end
  state.decorated_buffer = nil

  local diff_windows = {}
  for _, window in ipairs({ state.main_window, state.companion_window }) do
    if has_owned_window(state, window, instance_id) then
      statusline.clear(window)
      table.insert(diff_windows, window)
    end
  end
  return native_diff.reset(state.native_diff, diff_windows, release_active, active_window_lost)
end

---@param state ReviewSideBySideState
---@param instance_id integer
---@param layout ViewLayout
local function ensure_review_window(state, instance_id, layout)
  if not has_owned_window(state, state.main_window, instance_id) then
    if has_owned_window(state, state.companion_window, instance_id) then
      local split = layout == 'vertical' and 'right' or 'below'
      state.main_window = vim.api.nvim_open_win(0, true, { win = state.companion_window, split = split })
    elseif state.main_window == nil then
      local anchor = vim.api.nvim_get_current_win()
      state.main_window = anchor
    else
      local anchor = vim.api.nvim_get_current_win()
      state.main_window = vim.api.nvim_open_win(0, true, { win = anchor, split = 'below' })
    end
    vim.api.nvim_win_set_var(state.main_window, owner_variable, instance_id)
  end
end

---@param state ReviewSideBySideState
---@param instance_id integer
local function dispose_companion(state, instance_id)
  if has_owned_window(state, state.companion_window, instance_id) then
    vim.api.nvim_win_close(state.companion_window, false)
  end
  state.companion_window = nil
end

---@param content DiffPathTextContent
---@return integer
local function path_buffer(content)
  local buffer = vim.fn.bufadd(content.absolute_path)
  if not vim.api.nvim_buf_is_loaded(buffer) then
    vim.fn.bufload(buffer)
  end
  return buffer
end

---@param state ReviewSideBySideState
---@param content DiffFileContent
---@param instance_id integer
---@return integer
local function main_content_buffer(state, content, instance_id)
  if content.kind == 'binary' then
    error('binary content cannot be rendered as text')
  end
  if content.source == 'path' then
    return path_buffer(content)
  end
  local buffer = scratch_buffer.snapshot(instance_id, state.main_snapshot_buffer, 'main-snapshot', content)
  state.main_snapshot_buffer = buffer
  return buffer
end

---@param state ReviewSideBySideState
---@param content DiffSnapshotTextContent
---@param instance_id integer
---@return integer
local function companion_content_buffer(state, content, instance_id)
  local buffer = scratch_buffer.snapshot(instance_id, state.companion_snapshot_buffer, 'companion-snapshot', content)
  state.companion_snapshot_buffer = buffer
  return buffer
end

---@param state ReviewSideBySideState
---@param instance_id integer
---@param layout ViewLayout
---@return integer
local function open_companion_window(state, instance_id, layout)
  local split = layout == 'vertical' and 'left' or 'above'
  local window = vim.api.nvim_open_win(0, false, { win = state.main_window, split = split })
  vim.api.nvim_win_set_var(window, owner_variable, instance_id)
  state.companion_window = window
  return window
end

---@param diff DiffViewModel
---@return boolean
local function has_binary_version(diff)
  return (diff.old ~= nil and diff.old.content.kind == 'binary')
    or (diff.current ~= nil and diff.current.content.kind == 'binary')
end

---@param diff DiffViewModel
---@return boolean
local function is_reserved_two_window(diff)
  return (diff.operation == 'modified' or diff.operation == 'renamed' or diff.operation == 'copied')
    and diff.content_changed
end

---@param ui ReviewUi
---@param diff DiffViewModel
---@param layout ViewLayout
---@return nil
function M.display_side_by_side(ui, diff, layout)
  local state = ui.side_by_side
  local instance_id = ui.instance_id
  local will_use_two_windows = is_reserved_two_window(diff) and not has_binary_version(diff)
  local active_window_lost = state.native_diff.active
    and (
      not has_owned_window(state, state.main_window, instance_id)
      or not has_owned_window(state, state.companion_window, instance_id)
    )
  local release_active = not will_use_two_windows or active_window_lost
  local native_diff_transition = clear_previous_presentation(state, instance_id, release_active, active_window_lost)
  if not will_use_two_windows or (state.active_layout ~= nil and state.active_layout ~= layout) then
    dispose_companion(state, instance_id)
  elseif not has_owned_window(state, state.companion_window, instance_id) then
    state.companion_window = nil
  end
  ensure_review_window(state, instance_id, layout)

  local buffer
  local old_buffer
  if
    diff.operation == 'error'
    or diff.operation == 'type_changed'
    or has_binary_version(diff)
    or (diff.operation == 'modified' and not diff.content_changed)
  then
    buffer = scratch_buffer.information(
      instance_id,
      state.information_buffer,
      'main-information',
      diff_information.lines(diff)
    )
    state.information_buffer = buffer
  elseif diff.operation == 'added' or diff.operation == 'untracked' then
    buffer = main_content_buffer(state, diff.current.content, instance_id)
  elseif diff.operation == 'deleted' then
    buffer = main_content_buffer(state, diff.old.content, instance_id)
  elseif diff.operation == 'unmerged' then
    buffer = main_content_buffer(state, diff.current.content, instance_id)
  else
    buffer = main_content_buffer(state, diff.current.content, instance_id)
    if will_use_two_windows then
      local old_content = diff.old.content
      ---@cast old_content DiffSnapshotTextContent
      old_buffer = companion_content_buffer(state, old_content, instance_id)
    end
  end

  vim.api.nvim_win_set_buf(state.main_window, buffer)
  statusline.set(state.main_window, diff)
  if old_buffer ~= nil then
    local companion = state.companion_window
    if not has_owned_window(state, companion, instance_id) then
      companion = open_companion_window(state, instance_id, layout)
    end
    ---@cast companion integer
    vim.api.nvim_win_set_buf(companion, old_buffer)
    statusline.clear(companion)
    native_diff.enable(state.native_diff, { companion, state.main_window }, native_diff_transition)
  end
  if decorations.set(buffer, state.namespace, diff) then
    state.decorated_buffer = buffer
  end
  state.active_layout = layout
  state.main_buffer = buffer
  state.companion_buffer = old_buffer
  state.main_side = nil
  if buffer ~= state.information_buffer then
    state.main_side = diff.operation == 'deleted' and 'old' or 'current'
  end
  vim.api.nvim_set_current_win(state.main_window)
end

---@param ui ReviewUi
---@param window integer
---@return string|nil, 'old'|'current'|nil
function M.comment_context(ui, window)
  local state = ui.side_by_side
  if not has_owned_window(state, window, ui.instance_id) then
    return nil, nil
  end
  local buffer = vim.api.nvim_win_get_buf(window)
  if window == state.main_window and buffer == state.main_buffer then
    return state.presented_id, state.main_side
  elseif window == state.companion_window and buffer == state.companion_buffer then
    return state.presented_id, 'old'
  end
  return nil, nil
end

---@param ui ReviewUi
---@param id string
---@param side 'old'|'current'
---@param lines string[]
---@return boolean
function M.text_matches(ui, id, side, lines)
  local state = ui.side_by_side
  local window = side == state.main_side and state.main_window or state.companion_window
  if window == nil or not vim.api.nvim_win_is_valid(window) then
    return false
  end
  local presented, actual_side = M.comment_context(ui, window)
  local expected = #lines == 0 and { '' } or lines
  return presented == id
    and actual_side == side
    and vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false), expected)
end

---@param ui ReviewUi
---@return nil
function M.cleanup(ui)
  local state = ui.side_by_side
  local instance_id = ui.instance_id
  local active_window_lost = state.native_diff.active
    and (
      not has_owned_window(state, state.main_window, instance_id)
      or not has_owned_window(state, state.companion_window, instance_id)
    )
  clear_previous_presentation(state, instance_id, true, active_window_lost)

  for _, field in ipairs({ 'main_snapshot_buffer', 'companion_snapshot_buffer', 'information_buffer' }) do
    local buffer = state[field]
    if
      buffer ~= nil
      and vim.api.nvim_buf_is_valid(buffer)
      and is_owned(buffer, vim.api.nvim_buf_get_var, instance_id)
    then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
    state[field] = nil
  end

  state.main_window = nil
  state.companion_window = nil
  state.decorated_buffer = nil
  state.active_layout = nil
  state.main_buffer = nil
  state.companion_buffer = nil
  state.main_side = nil
  state.presented_id = nil
end

---@param ui ReviewUi
---@return nil
function M.clear(ui)
  local state = ui.side_by_side
  if state.main_window == nil then
    return
  end
  local main = state.main_window
  local companion = state.companion_window
  local buffer
  if has_owned_window(state, main, ui.instance_id) then
    -- Keep the main window alive before deleting its displayed snapshot.
    buffer = scratch_buffer.information(ui.instance_id, state.information_buffer, 'main-information', {})
    state.information_buffer = nil
    vim.api.nvim_win_set_buf(assert(main), buffer)
  end
  M.cleanup(ui)
  if has_owned_window(state, companion, ui.instance_id) then
    vim.api.nvim_win_close(assert(companion), false)
  end
  if has_owned_window(state, main, ui.instance_id) then
    state.information_buffer = buffer
    state.main_window = main
  end
end

---@param ui ReviewUi
---@param records ReviewComment[]
---@return nil
function M.update_comments(ui, records)
  local state = ui.side_by_side
  comment_decorations.clear(state.comments)
  for _, window in ipairs({ state.main_window, state.companion_window }) do
    if has_owned_window(state, window, ui.instance_id) then
      local id, side = M.comment_context(ui, window)
      if id then
        comment_decorations.render(
          state.comments,
          vim.api.nvim_win_get_buf(window),
          records,
          id,
          side,
          window == state.main_window
        )
      end
    end
  end
end

---@param ui ReviewUi
---@param record ReviewComment
---@return boolean
function M.focus_comment(ui, record)
  local state = ui.side_by_side
  local window = state.main_window
  if record.start_line and record.status == 'open' then
    window = state.main_side == 'current' and state.main_window or state.companion_window
  end
  if not has_owned_window(state, window, ui.instance_id) then
    return false
  end
  ---@cast window integer
  local id, side = M.comment_context(ui, window)
  if id ~= record.file_id or (record.start_line and record.status == 'open' and side ~= 'current') then
    return false
  end
  vim.api.nvim_set_current_win(window)
  if
    record.start_line
    and record.status == 'open'
    and record.start_line <= vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window))
  then
    vim.api.nvim_win_set_cursor(window, { record.start_line, 0 })
  end
  return true
end

return M
