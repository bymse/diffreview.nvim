local async_operation = require('diffreview.async_operation')
local file_mode = require('diffreview.file_mode')
local status = require('diffreview.diffs.status')

local M = {}

---@class WorktreeFingerprintInput
---@field bytes string
---@field mode DiffFileMode

---@param entry LoadedDiffEntry
---@return DiffOperation
local function get_operation(entry)
  if entry.git_diff == nil then
    return 'untracked'
  end
  local operations = {
    [status.added] = 'added',
    [status.copied] = 'copied',
    [status.deleted] = 'deleted',
    [status.modified] = 'modified',
    [status.renamed] = 'renamed',
    [status.type_changed] = 'type_changed',
    [status.unmerged] = 'unmerged',
  }
  return assert(operations[entry.git_diff.status])
end

---@param operation DiffOperation
---@param path string
---@param message string
---@return ErrorDiff
local function error_view(operation, path, message)
  return { operation = 'error', attempted_operation = operation, path = path, message = message }
end

---@param bytes string
---@param path string
---@return DiffSnapshotTextContent
local function text_snapshot(bytes, path)
  local fileformat = 'unix'
  local separator = '\n'
  if bytes:find('\r\n', 1, true) then
    fileformat = 'dos'
    bytes = bytes:gsub('\r\n', '\n')
  elseif not bytes:find('\n', 1, true) and bytes:find('\r', 1, true) then
    fileformat = 'mac'
    separator = '\r'
  end

  local endofline = bytes:sub(-#separator) == separator
  if endofline then
    bytes = bytes:sub(1, -#separator - 1)
  end
  if fileformat == 'mac' then
    bytes = bytes:gsub('\r', '\n')
  end

  local lines = {}
  if bytes ~= '' then
    local start = 1
    while true do
      local finish = bytes:find('\n', start, true)
      if finish == nil then
        table.insert(lines, bytes:sub(start))
        break
      end
      table.insert(lines, bytes:sub(start, finish - 1))
      start = finish + 1
    end
  elseif endofline then
    lines = { '' }
  end

  return {
    kind = 'text',
    source = 'snapshot',
    lines = lines,
    endofline = endofline,
    fileformat = fileformat,
    filetype_path = path,
  }
end

---@param path string
---@param mode DiffFileMode
---@param bytes string
---@param oid string|nil
---@param binary boolean
---@return DiffFileVersion
local function snapshot_file(path, mode, bytes, oid, binary)
  local content
  if file_mode.classify_file_type(mode) == 'symlink' then
    content = text_snapshot(bytes, path)
  elseif binary then
    content = { kind = 'binary', oid = oid, size = #bytes }
  else
    content = text_snapshot(bytes, path)
  end
  return { display_path = path, mode = mode, content = content }
end

---@param path string
---@return string|nil, string|nil, DiffFileMode|nil
function M.read_worktree_bytes(path)
  local stat, stat_error = vim.uv.fs_lstat(path)
  if stat == nil then
    return nil, stat_error or 'Selected file is no longer available', nil
  end
  if stat.type == 'link' then
    local target, readlink_error = vim.uv.fs_readlink(path)
    if target == nil then
      return nil, readlink_error or 'Unable to read symbolic link target', nil
    end
    return target, nil, '120000'
  end
  if stat.type ~= 'file' then
    return nil, 'Selected path is not a regular file or symbolic link', nil
  end

  local descriptor, open_error = vim.uv.fs_open(path, 'r', 438)
  if descriptor == nil then
    return nil, open_error or 'Unable to read selected file', nil
  end
  local bytes, read_error = vim.uv.fs_read(descriptor, stat.size, 0)
  vim.uv.fs_close(descriptor)
  if bytes == nil then
    return nil, read_error or 'Unable to read selected file', nil
  end
  local permissions = stat.mode % 512
  local executable = permissions % 8 > 0 or math.floor(permissions / 8) % 8 > 0 or math.floor(permissions / 64) % 8 > 0
  return bytes, nil, executable and '100755' or '100644'
end

---@param repo GitRepo
---@param entry LoadedDiffEntry
---@param path string
---@param mode DiffFileMode
---@param oid string
---@param operation AsyncOperation|nil
---@return DiffFileVersion|nil, string|nil, string|nil
local function load_blob(repo, entry, path, mode, oid, operation)
  if async_operation.is_canceled(operation) then
    return nil, nil, nil
  end
  if mode == '160000' then
    return nil, nil, 'Submodule content is outside the supported review scope'
  end
  if oid == string.rep('0', #oid) then
    return nil, nil, 'Selected Git blob is absent'
  end
  local result, bytes = repo:load_blob(oid)
  if async_operation.is_canceled(operation) then
    return nil, nil, nil
  end
  if not result.ok or bytes == nil then
    return nil, nil, result.error or 'Unable to load selected Git content'
  end
  return snapshot_file(path, mode, bytes, oid, entry.binary), bytes, nil
end

---@param entry LoadedDiffEntry
---@param path string
---@param mode DiffFileMode|nil
---@param operation AsyncOperation|nil
---@return DiffFileVersion|nil, string|nil, string|nil, DiffFileMode|nil
local function load_worktree(entry, path, mode, operation, snapshot)
  if async_operation.is_canceled(operation) then
    return nil, nil, nil
  end
  if mode == '160000' then
    return nil, nil, 'Submodule content is outside the supported review scope'
  end
  local worktree_path = entry.absolute_path or entry.root .. '/' .. path
  local bytes, read_error, worktree_mode = M.read_worktree_bytes(worktree_path)
  if async_operation.is_canceled(operation) then
    return nil, nil, nil
  end
  if bytes == nil then
    return nil, nil, read_error
  end
  mode = mode or assert(worktree_mode)
  if entry.git_diff ~= nil and entry.git_diff.status == status.unmerged then
    if entry.binary or file_mode.classify_file_type(mode) ~= 'regular' then
      return nil, nil, 'Unmerged content is not a regular text file'
    end
  end

  local kind = file_mode.classify_file_type(mode)
  local diff_status = entry.git_diff and entry.git_diff.status
  if snapshot then
    return snapshot_file(path, assert(worktree_mode), bytes, nil, entry.binary), bytes, nil, worktree_mode
  end
  if
    kind == 'regular'
    and not entry.binary
    and (
      diff_status == nil
      or diff_status == status.added
      or diff_status == status.modified
      or diff_status == status.renamed
      or diff_status == status.copied
      or diff_status == status.unmerged
    )
  then
    return {
      display_path = path,
      mode = mode,
      content = { kind = 'text', source = 'path', absolute_path = worktree_path },
    },
      bytes,
      nil,
      worktree_mode
  end
  return snapshot_file(path, mode, bytes, nil, entry.binary), bytes, nil, worktree_mode
end

---@param repo GitRepo
---@param target_is_worktree boolean
---@param entry LoadedDiffEntry
---@param operation AsyncOperation|nil
---@param snapshot_worktree boolean|nil
---@return DiffViewModel|nil, WorktreeFingerprintInput|nil
function M.load(repo, target_is_worktree, entry, operation, snapshot_worktree)
  if async_operation.is_canceled(operation) then
    return nil
  end
  local operation_name = get_operation(entry)
  local display_path = entry.summary.display_path
  local diff = entry.git_diff
  if diff == nil then
    local current, bytes, read_error, mode =
      load_worktree(entry, assert(entry.untracked_path), nil, operation, snapshot_worktree)
    if current == nil then
      return read_error and error_view(operation_name, display_path, read_error) or nil
    end
    return { operation = 'untracked', current = current }, { bytes = assert(bytes), mode = assert(mode) }
  end

  local old, old_bytes
  if operation_name ~= 'added' and operation_name ~= 'unmerged' then
    local read_error
    old, old_bytes, read_error =
      load_blob(repo, entry, diff.old_path or diff.current_path, diff.old_mode, diff.old_oid, operation)
    if old == nil then
      return read_error and error_view(operation_name, display_path, read_error) or nil
    end
  end
  if operation_name == 'deleted' then
    return { operation = operation_name, old = assert(old) }
  end

  local current, current_bytes, read_error, worktree_mode
  if target_is_worktree then
    current, current_bytes, read_error, worktree_mode =
      load_worktree(entry, diff.current_path, diff.new_mode, operation, snapshot_worktree)
  else
    current, current_bytes, read_error =
      load_blob(repo, entry, diff.current_path, diff.new_mode, diff.new_oid, operation)
  end
  if current == nil then
    return read_error and error_view(operation_name, display_path, read_error) or nil
  end
  local snapshot = worktree_mode and { bytes = assert(current_bytes), mode = worktree_mode } or nil
  if operation_name == 'added' or operation_name == 'unmerged' then
    return { operation = operation_name, current = current }, snapshot
  end

  old = assert(old)
  local content_changed = old_bytes ~= current_bytes
  if operation_name == 'modified' and not content_changed and old.mode == current.mode then
    return error_view(operation_name, display_path, 'Selected file no longer differs from its baseline')
  end
  return { operation = operation_name, old = old, current = current, content_changed = content_changed }, snapshot
end

return M
