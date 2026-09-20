local file_mode = require('diffreview.file_mode')

local M = {}

---@param value string
---@return string
local function escape(value)
  local safe_text = value:gsub('[%z\1-\31\127]', function(character)
    return ('\\x%02X'):format(string.byte(character))
  end)
  return (safe_text:gsub('%%', '%%%%'))
end

---@param diff ModifiedDiff|RenamedDiff|CopiedDiff
---@return string
local function operation_metadata(diff)
  local text = ''
  if diff.operation == 'renamed' then
    text = 'Moved from ' .. diff.old.display_path
  elseif diff.operation == 'copied' then
    text = 'Copied from ' .. diff.old.display_path
  end
  if diff.old.mode ~= diff.current.mode then
    text = text
      .. ('%sMode: %s (%s) -> %s (%s)'):format(
        text == '' and '' or ' | ',
        file_mode.display_label(diff.old.mode),
        diff.old.mode,
        file_mode.display_label(diff.current.mode),
        diff.current.mode
      )
  end
  return text
end

---@param diff DiffViewModel
---@return boolean
local function has_binary_version(diff)
  return (diff.old ~= nil and diff.old.content.kind == 'binary')
    or (diff.current ~= nil and diff.current.content.kind == 'binary')
end

---@param diff DiffViewModel
---@return string
local function text(diff)
  if
    diff.operation == 'error'
    or diff.operation == 'type_changed'
    or has_binary_version(diff)
    or (diff.operation == 'modified' and not diff.content_changed)
  then
    return ''
  end
  if diff.operation == 'added' or diff.operation == 'untracked' then
    return 'Added file'
  end
  if diff.operation == 'deleted' then
    return 'Deleted file'
  end
  if diff.operation == 'unmerged' then
    return 'Unmerged file'
  end
  local metadata_diff = diff
  ---@cast metadata_diff ModifiedDiff|RenamedDiff|CopiedDiff
  return operation_metadata(metadata_diff)
end

---@param window integer
---@param diff DiffViewModel
---@return nil
function M.set(window, diff)
  vim.api.nvim_set_option_value('winbar', escape(text(diff)), { win = window })
end

---@param window integer
---@return nil
function M.clear(window)
  vim.api.nvim_set_option_value('winbar', '', { win = window })
end

return M
