local M = {}

---@param path string
---@param lines string[]|nil
---@param mode DiffFileMode|nil
---@return DiffFileVersion
function M.snapshot(path, lines, mode)
  return {
    display_path = path,
    mode = mode or '100644',
    content = {
      kind = 'text',
      source = 'snapshot',
      lines = lines or { 'text' },
      endofline = true,
      fileformat = 'unix',
      filetype_path = path,
    },
  }
end

---@param path string
---@param mode DiffFileMode|nil
---@return DiffFileVersion
function M.binary(path, mode)
  return {
    display_path = path,
    mode = mode or '100644',
    content = { kind = 'binary', oid = 'a1b2', size = 12 },
  }
end

---@param path string
---@return DiffFileVersion
function M.path(path)
  return {
    display_path = path,
    mode = '100644',
    content = { kind = 'text', source = 'path', absolute_path = path },
  }
end

---@param old_lines string[]
---@param current_lines string[]
---@return ModifiedDiff
function M.modified(old_lines, current_lines)
  return {
    operation = 'modified',
    old = M.snapshot('file.txt', old_lines),
    current = M.snapshot('file.txt', current_lines),
    content_changed = true,
  }
end

return M
