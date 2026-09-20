local file_mode = require('diffreview.file_mode')

local M = {}

---@param value string
---@return string
local function safe_display_text(value)
  return (value:gsub('[%z\1-\31\127]', function(character)
    return ('\\x%02X'):format(string.byte(character))
  end))
end

---@param old DiffFileVersion|nil
---@param current DiffFileVersion|nil
---@return string[]
local function path_lines(old, current)
  if old ~= nil and current ~= nil and old.display_path == current.display_path then
    return { 'Path: ' .. safe_display_text(current.display_path) }
  end
  local lines = {}
  if old ~= nil then
    table.insert(lines, 'Old path: ' .. safe_display_text(old.display_path))
  end
  if current ~= nil then
    table.insert(lines, 'Current path: ' .. safe_display_text(current.display_path))
  end
  return lines
end

---@param prefix string
---@param version DiffFileVersion
---@return string[]
local function binary_lines(prefix, version)
  local content = version.content
  local oid = content.kind == 'binary' and content.oid or nil
  local size = content.kind == 'binary' and content.size or nil
  return {
    prefix .. ' object: ' .. (oid or 'Unavailable'),
    prefix .. ' size: ' .. (size and (size .. ' bytes') or 'Unavailable'),
  }
end

---@param diff DiffViewModel
---@return string[]
function M.lines(diff)
  if diff.operation == 'error' then
    local lines = {
      'Content load error',
      'Attempted operation: ' .. diff.attempted_operation,
      'Path: ' .. safe_display_text(diff.path),
      'Error:',
    }
    vim.list_extend(lines, vim.split(diff.message, '\n', { plain = true }))
    return lines
  end

  local old = diff.old
  local current = diff.current
  if
    diff.operation == 'modified'
    and not diff.content_changed
    and old.content.kind ~= 'binary'
    and current.content.kind ~= 'binary'
  then
    return {
      'Mode-only change',
      'Operation: modified',
      'Path: ' .. safe_display_text(current.display_path),
      ('Old mode: %s (%s)'):format(file_mode.display_label(old.mode), old.mode),
      ('Current mode: %s (%s)'):format(file_mode.display_label(current.mode), current.mode),
      'Text content is unchanged.',
    }
  end
  if diff.operation == 'type_changed' then
    local lines = { 'Type change', 'Operation: type_changed' }
    vim.list_extend(lines, path_lines(old, current))
    vim.list_extend(lines, {
      'Old type: ' .. file_mode.classify_file_type(old.mode),
      ('Old mode: %s (%s)'):format(file_mode.display_label(old.mode), old.mode),
    })
    if old.content.kind == 'binary' then
      vim.list_extend(lines, binary_lines('Old', old))
    end
    vim.list_extend(lines, {
      'Current type: ' .. file_mode.classify_file_type(current.mode),
      ('Current mode: %s (%s)'):format(file_mode.display_label(current.mode), current.mode),
    })
    if current.content.kind == 'binary' then
      vim.list_extend(lines, binary_lines('Current', current))
    end
    table.insert(lines, 'Text diff is unavailable for a type change.')
    return lines
  end
  local lines = { 'Binary file', 'Operation: ' .. diff.operation }
  vim.list_extend(lines, path_lines(old, current))
  if old ~= nil then
    vim.list_extend(lines, binary_lines('Old', old))
  end
  if current ~= nil then
    vim.list_extend(lines, binary_lines('Current', current))
  end
  table.insert(lines, 'Text diff is unavailable for binary content.')
  return lines
end

return M
