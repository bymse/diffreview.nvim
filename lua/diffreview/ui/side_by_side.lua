local decorations = require('diffreview.ui.decorations')
local diff_information = require('diffreview.ui.diff_information')
local diff_view_model_validator = require('diffreview.ui.diff_view_model_validator')
local native_diff = require('diffreview.ui.native_diff')
local scratch_buffer = require('diffreview.ui.scratch_buffer')
local statusline = require('diffreview.ui.statusline')

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
---@return boolean
local function has_owned_tab(state)
  return state.tabpage ~= nil
    and vim.api.nvim_tabpage_is_valid(state.tabpage)
    and is_owned(state.tabpage, vim.api.nvim_tabpage_get_var, state.instance_id)
end

---@param state ReviewSideBySideState
---@param window integer|nil
---@return boolean
local function has_owned_window(state, window)
  return window ~= nil
    and vim.api.nvim_win_is_valid(window)
    and is_owned(window, vim.api.nvim_win_get_var, state.instance_id)
end

---@param state ReviewSideBySideState
---@param release_active boolean
---@param active_window_lost boolean
---@return NativeDiffTransition
local function clear_previous_presentation(state, release_active, active_window_lost)
  if state.decorated_buffer ~= nil and vim.api.nvim_buf_is_valid(state.decorated_buffer) then
    decorations.clear(state.decorated_buffer, state.namespace)
  end
  state.decorated_buffer = nil

  local diff_windows = {}
  for _, window in ipairs({ state.main_window, state.companion_window }) do
    if has_owned_window(state, window) then
      statusline.clear(window)
      table.insert(diff_windows, window)
    end
  end
  return native_diff.reset(state.native_diff, diff_windows, release_active, active_window_lost)
end

---@param state ReviewSideBySideState
---@param layout ViewLayout
local function ensure_review_window(state, layout)
  if not has_owned_tab(state) then
    state.tabpage = nil
    state.main_window = nil
    state.companion_window = nil
    vim.cmd('tabnew')
    state.tabpage = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_tabpage_set_var(state.tabpage, owner_variable, state.instance_id)
  else
    vim.api.nvim_set_current_tabpage(state.tabpage)
  end

  if not has_owned_window(state, state.main_window) then
    if has_owned_window(state, state.companion_window) then
      local split = layout == 'vertical' and 'right' or 'below'
      state.main_window = vim.api.nvim_open_win(0, true, { win = state.companion_window, split = split })
    elseif state.main_window == nil then
      local anchor = vim.api.nvim_get_current_win()
      state.main_window = anchor
    else
      local anchor = vim.api.nvim_get_current_win()
      state.main_window = vim.api.nvim_open_win(0, true, { win = anchor, split = 'below' })
    end
    vim.api.nvim_win_set_var(state.main_window, owner_variable, state.instance_id)
  end
end

---@param state ReviewSideBySideState
local function dispose_companion(state)
  if has_owned_window(state, state.companion_window) then
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
---@return integer
local function main_content_buffer(state, content)
  if content.kind == 'binary' then
    error('binary content cannot be rendered as text')
  end
  if content.source == 'path' then
    return path_buffer(content)
  end
  local buffer = scratch_buffer.snapshot(state.instance_id, state.main_snapshot_buffer, 'main-snapshot', content)
  state.main_snapshot_buffer = buffer
  return buffer
end

---@param state ReviewSideBySideState
---@param content DiffSnapshotTextContent
---@return integer
local function companion_content_buffer(state, content)
  local buffer =
    scratch_buffer.snapshot(state.instance_id, state.companion_snapshot_buffer, 'companion-snapshot', content)
  state.companion_snapshot_buffer = buffer
  return buffer
end

---@param state ReviewSideBySideState
---@param layout ViewLayout
---@return integer
local function open_companion_window(state, layout)
  local split = layout == 'vertical' and 'left' or 'above'
  local window = vim.api.nvim_open_win(0, false, { win = state.main_window, split = split })
  vim.api.nvim_win_set_var(window, owner_variable, state.instance_id)
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
  diff_view_model_validator.validate(diff)
  if layout ~= 'horizontal' and layout ~= 'vertical' then
    error('Invalid view layout: ' .. tostring(layout))
  end
  local state = ui.side_by_side
  local will_use_two_windows = is_reserved_two_window(diff) and not has_binary_version(diff)
  local active_window_lost = state.native_diff.active
    and (
      not has_owned_tab(state)
      or not has_owned_window(state, state.main_window)
      or not has_owned_window(state, state.companion_window)
    )
  local owned_tab = has_owned_tab(state)
  local release_active = not owned_tab or not will_use_two_windows or active_window_lost
  local native_diff_transition = clear_previous_presentation(state, release_active, active_window_lost)
  if not owned_tab then
    state.tabpage = nil
    state.main_window = nil
    state.companion_window = nil
  else
    if not will_use_two_windows or (state.active_layout ~= nil and state.active_layout ~= layout) then
      dispose_companion(state)
    elseif not has_owned_window(state, state.companion_window) then
      state.companion_window = nil
    end
  end
  ensure_review_window(state, layout)

  local buffer
  local old_buffer
  if
    diff.operation == 'error'
    or diff.operation == 'type_changed'
    or has_binary_version(diff)
    or (diff.operation == 'modified' and not diff.content_changed)
  then
    buffer = scratch_buffer.information(
      state.instance_id,
      state.information_buffer,
      'main-information',
      diff_information.lines(diff)
    )
    state.information_buffer = buffer
  elseif diff.operation == 'added' or diff.operation == 'untracked' then
    buffer = main_content_buffer(state, diff.current.content)
  elseif diff.operation == 'deleted' then
    buffer = main_content_buffer(state, diff.old.content)
  elseif diff.operation == 'unmerged' then
    buffer = main_content_buffer(state, diff.current.content)
  else
    buffer = main_content_buffer(state, diff.current.content)
    if will_use_two_windows then
      local old_content = diff.old.content
      ---@cast old_content DiffSnapshotTextContent
      old_buffer = companion_content_buffer(state, old_content)
    end
  end

  vim.api.nvim_win_set_buf(state.main_window, buffer)
  statusline.set(state.main_window, diff)
  if old_buffer ~= nil then
    local companion = state.companion_window
    if not has_owned_window(state, companion) then
      companion = open_companion_window(state, layout)
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
  vim.api.nvim_set_current_win(state.main_window)
end

return M
