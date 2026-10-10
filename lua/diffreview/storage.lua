local M = {}

---@param value any
---@return boolean
local function valid_oid(value)
  return type(value) == 'string' and (#value == 40 or #value == 64) and value:match('^%x+$') ~= nil
end

---@param value any
---@return boolean
local function valid_fingerprint(value)
  return type(value) == 'string' and #value == 64 and value:match('^%x+$') ~= nil
end

---@param identity ReviewIdentity
---@return string
local function key(identity)
  return vim.fn.sha256(
    vim.json.encode({ identity.repository_root, identity.source, identity.baseline, identity.target })
  )
end

---@param directory string
---@param identity ReviewIdentity
---@return string
function M.path(directory, identity)
  return directory .. '/' .. key(identity) .. '.json'
end

---@param directory string
---@param identity ReviewIdentity
---@return ReviewProgress|nil, string|nil
function M.load(directory, identity)
  local path = M.path(directory, identity)
  local stat, stat_error = vim.uv.fs_lstat(path)
  if stat == nil then
    if stat_error and not stat_error:match('ENOENT') then
      return nil, stat_error
    end
    return nil, nil
  end
  if stat.type ~= 'file' then
    return nil, 'Review state is not a file'
  end
  local descriptor, err = vim.uv.fs_open(path, 'r', 438)
  if descriptor == nil then
    return nil, err
  end
  local raw, read_error = vim.uv.fs_read(descriptor, stat.size, 0)
  vim.uv.fs_close(descriptor)
  if raw == nil then
    return nil, read_error
  end
  local ok, value = pcall(vim.json.decode, raw)
  if not ok or type(value) ~= 'table' then
    return nil, 'Invalid review state JSON'
  end
  if value.version ~= 1 then
    return nil, 'Unsupported review state version'
  end
  local saved = value.identity
  if
    type(saved) ~= 'table'
    or saved.repository_root ~= identity.repository_root
    or saved.source ~= identity.source
    or saved.baseline ~= identity.baseline
    or saved.target ~= identity.target
  then
    return nil, 'Review identity mismatch'
  end
  if
    not valid_oid(value.from_oid)
    or (value.to_oid ~= nil and not valid_oid(value.to_oid))
    or (value.head_oid ~= nil and not valid_oid(value.head_oid))
    or type(value.files) ~= 'table'
    or not vim.islist(value.files)
  then
    return nil, 'Invalid review state schema'
  end
  local seen = {}
  for _, record in ipairs(value.files) do
    if
      type(record) ~= 'table'
      or type(record.id) ~= 'string'
      or record.id == ''
      or seen[record.id]
      or type(record.display_path) ~= 'string'
      or not valid_fingerprint(record.fingerprint)
      or (record.viewed_fingerprint ~= nil and not valid_fingerprint(record.viewed_fingerprint))
      or type(record.added_lines) ~= 'number'
      or record.added_lines < 0
      or record.added_lines % 1 ~= 0
      or type(record.removed_lines) ~= 'number'
      or record.removed_lines < 0
      or record.removed_lines % 1 ~= 0
    then
      return nil, 'Invalid review file record'
    end
    seen[record.id] = true
  end
  if #value.files ~= vim.tbl_count(seen) then
    return nil, 'Invalid review file list'
  end
  return value, nil
end

---@param directory string
---@param state ReviewProgress
---@return boolean, string|nil
function M.save(directory, state)
  local created = vim.fn.mkdir(directory, 'p')
  if created == 0 and vim.fn.isdirectory(directory) ~= 1 then
    return false, 'Unable to create review storage directory'
  end
  local path = M.path(directory, state.identity)
  local temp = path .. '.' .. tostring(vim.uv.hrtime()) .. '.tmp'
  local descriptor, err = vim.uv.fs_open(temp, 'wx', 384)
  if descriptor == nil then
    return false, err
  end
  local raw = vim.json.encode(state)
  local written, write_error = vim.uv.fs_write(descriptor, raw, 0)
  local closed, close_error = vim.uv.fs_close(descriptor)
  if written ~= #raw or not closed then
    vim.uv.fs_unlink(temp)
    return false, write_error or close_error or 'Incomplete review state write'
  end
  local renamed, rename_error = vim.uv.fs_rename(temp, path)
  if not renamed then
    vim.uv.fs_unlink(temp)
    return false, rename_error
  end
  return true, nil
end

return M
