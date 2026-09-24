local M = {}

---@param path string
---@return string|nil, string|nil
function M.ensure_accessible_directory(path)
  local stat = vim.uv.fs_stat(path)
  if stat == nil or stat.type ~= 'directory' then
    return nil, 'unable to access directory: ' .. path
  end

  local readable, read_error = vim.uv.fs_access(path, 'R')
  if not readable then
    return nil, read_error or ('unable to read directory: ' .. path)
  end

  local traversable, traverse_error = vim.uv.fs_access(path, 'X')
  if not traversable then
    return nil, traverse_error or ('unable to traverse directory: ' .. path)
  end

  local resolved_path = vim.uv.fs_realpath(path)
  if resolved_path == nil then
    return nil, 'unable to access directory: ' .. path
  end

  return resolved_path, nil
end

return M
