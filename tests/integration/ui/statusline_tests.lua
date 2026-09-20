local statusline = require('diffreview.ui.statusline')

local M = {}

---@param path string
---@param mode DiffFileMode|nil
---@return DiffFileVersion
local function snapshot(path, mode)
  return {
    display_path = path,
    mode = mode or '100644',
    content = {
      kind = 'text',
      source = 'snapshot',
      lines = { 'text' },
      endofline = true,
      fileformat = 'unix',
      filetype_path = path,
    },
  }
end

---@param path string
---@return DiffFileVersion
local function binary(path)
  return {
    display_path = path,
    mode = '100644',
    content = { kind = 'binary', oid = 'a1b2', size = 12 },
  }
end

---@param diff DiffViewModel
---@param expected string
local function assert_changed_winbar(diff, expected)
  local window = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value('winbar', 'unchanged sentinel', { win = window })
  statusline.set(window, diff)
  local actual = vim.api.nvim_get_option_value('winbar', { win = window })
  assert(actual ~= 'unchanged sentinel', 'expected winbar to change')
  assert(actual == expected, ('expected winbar %q, got %q'):format(expected, actual))
  statusline.clear(window)
end

M.set_should_show_added_label_when_file_is_added_or_untracked = function()
  for _, operation in ipairs({ 'added', 'untracked' }) do
    assert_changed_winbar({ operation = operation, current = snapshot('file.txt') }, 'Added file')
  end
end

M.set_should_show_deleted_label_when_file_is_deleted = function()
  assert_changed_winbar({ operation = 'deleted', old = snapshot('file.txt') }, 'Deleted file')
end

M.set_should_show_unmerged_label_when_file_is_unmerged = function()
  assert_changed_winbar({
    operation = 'unmerged',
    current = {
      display_path = 'file.txt',
      mode = '100644',
      content = { kind = 'text', source = 'path', absolute_path = '/tmp/file.txt' },
    },
  }, 'Unmerged file')
end

M.set_should_show_mode_metadata_when_modified_mode_changes = function()
  assert_changed_winbar({
    operation = 'modified',
    old = snapshot('file.txt', '100644'),
    current = snapshot('file.txt', '100755'),
    content_changed = true,
  }, 'Mode: file (100644) -> executable file (100755)')
end

M.set_should_show_source_and_mode_metadata_when_file_is_renamed = function()
  assert_changed_winbar({
    operation = 'renamed',
    old = snapshot('old.txt', '100644'),
    current = snapshot('new.txt', '100755'),
    content_changed = false,
  }, 'Moved from old.txt | Mode: file (100644) -> executable file (100755)')
end

M.set_should_show_source_when_file_is_copied = function()
  assert_changed_winbar({
    operation = 'copied',
    old = snapshot('source.txt'),
    current = snapshot('copy.txt'),
    content_changed = false,
  }, 'Copied from source.txt')
end

M.set_should_escape_percent_and_control_characters_when_path_contains_statusline_syntax = function()
  assert_changed_winbar({
    operation = 'renamed',
    old = snapshot('old%\nname.txt'),
    current = snapshot('new.txt'),
    content_changed = false,
  }, 'Moved from old%%\\x0Aname.txt')
end

M.set_should_clear_winbar_when_diff_uses_information_view = function()
  local diffs = {
    { operation = 'error', attempted_operation = 'modified', path = 'file.txt', message = 'failed' },
    {
      operation = 'type_changed',
      old = snapshot('file.txt', '100644'),
      current = snapshot('file.txt', '120000'),
    },
    {
      operation = 'modified',
      old = snapshot('file.txt'),
      current = binary('file.txt'),
      content_changed = true,
    },
    {
      operation = 'modified',
      old = snapshot('file.txt', '100644'),
      current = snapshot('file.txt', '100755'),
      content_changed = false,
    },
  }
  for _, diff in ipairs(diffs) do
    assert_changed_winbar(diff, '')
  end
end

M.clear_should_clear_winbar_when_content_exists = function()
  local window = vim.api.nvim_get_current_win()
  vim.api.nvim_set_option_value('winbar', 'content', { win = window })
  statusline.clear(window)
  local actual = vim.api.nvim_get_option_value('winbar', { win = window })
  assert(actual ~= 'content', 'expected winbar to change')
  assert(actual == '', 'expected cleared winbar')
end

return M
