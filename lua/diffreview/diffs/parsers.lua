local file_mode = require('diffreview.diffs.file_mode')
local diff_status = require('diffreview.diffs.status')

---@class GitDiff
---@field old_oid string
---@field new_oid string
---@field old_mode string
---@field new_mode string
---@field status string
---@field similarity_score string|nil
---@field current_path string
---@field old_path string|nil
---@field added_lines integer|nil
---@field removed_lines integer|nil
---@field binary boolean

local M = {}
local colon_byte = string.byte(':')

---@param raw_meta string
---@return GitDiff
local function parse_diff_meta(raw_meta)
  local parts = {}
  for word in raw_meta:gmatch('%S+') do
    table.insert(parts, word)
  end

  if #parts ~= 5 then
    error('invalid git diff metadata: ' .. raw_meta)
  end

  local status = parts[5]:sub(1, 1)
  local similarity_score = nil
  if #parts[5] > 1 then
    similarity_score = parts[5]:sub(2)
  end

  return {
    old_mode = parts[1],
    new_mode = parts[2],
    old_oid = parts[3],
    new_oid = parts[4],
    status = status,
    similarity_score = similarity_score,
  }
end

---@param diff GitDiff
local function validate_diff(diff)
  if diff.old_oid == nil then
    error('missing required parsed diff field: old_oid')
  end

  if diff.new_oid == nil then
    error('missing required parsed diff field: new_oid')
  end

  if diff.old_mode == nil then
    error('missing required parsed diff field: old_mode')
  end

  if diff.new_mode == nil then
    error('missing required parsed diff field: new_mode')
  end

  if diff.status == nil then
    error('missing required parsed diff field: status')
  end

  if diff.current_path == nil or diff.current_path == '' then
    error('missing required parsed diff field: current_path')
  end

  if not file_mode.is_valid_mode(diff.old_mode) then
    error('invalid old file mode: ' .. tostring(diff.old_mode))
  end

  if not file_mode.is_valid_mode(diff.new_mode) then
    error('invalid new file mode: ' .. tostring(diff.new_mode))
  end

  if not diff.old_oid:match('^%x+$') then
    error('invalid old object ID: ' .. diff.old_oid)
  end

  if not diff.new_oid:match('^%x+$') then
    error('invalid new object ID: ' .. diff.new_oid)
  end

  if not diff_status.is_valid_status(diff.status) then
    error('unsupported diff status: ' .. diff.status)
  end

  if
    (diff.status == diff_status.copied or diff.status == diff_status.renamed)
    and (diff.old_path == nil or diff.old_path == '')
  then
    error('missing required parsed diff field: old_path')
  end
end

---@param raw_out string
---@param start integer
---@return string, integer
local function read_nul_section(raw_out, start)
  local finish = raw_out:find('\0', start, true)
  if finish == nil then
    error('git diff output expected to end with NUL')
  end

  return raw_out:sub(start, finish - 1), finish + 1
end

---@param raw_out string
---@param start integer
---@return GitDiff, integer
local function parse_raw_diff(raw_out, start)
  local raw_meta, next_start = read_nul_section(raw_out, start + 1)
  local diff = parse_diff_meta(raw_meta)
  local first_path
  first_path, next_start = read_nul_section(raw_out, next_start)

  if diff.status == diff_status.copied or diff.status == diff_status.renamed then
    diff.old_path = first_path
    diff.current_path, next_start = read_nul_section(raw_out, next_start)
  else
    diff.current_path = first_path
  end

  validate_diff(diff)
  return diff, next_start
end

---@param raw_numstat string
---@return integer|nil, integer|nil, boolean, string
local function parse_numstat_counts(raw_numstat)
  local added, removed, path = raw_numstat:match('^([^\t]+)\t([^\t]+)\t(.*)$')
  if added == nil or removed == nil or path == nil then
    error('invalid git diff numstat metadata: ' .. raw_numstat)
  end

  if added == '-' and removed == '-' then
    return nil, nil, true, path
  end

  if not added:match('^%d+$') or not removed:match('^%d+$') then
    error('invalid git diff numstat line counts: ' .. raw_numstat)
  end

  return tonumber(added), tonumber(removed), false, path
end

---@param diff GitDiff
---@param raw_out string
---@param start integer
---@return integer
local function parse_numstat_diff(diff, raw_out, start)
  local raw_numstat, next_start = read_nul_section(raw_out, start)
  local added_lines, removed_lines, binary, first_path = parse_numstat_counts(raw_numstat)

  if diff.status == diff_status.copied or diff.status == diff_status.renamed then
    if first_path ~= '' then
      error('git diff numstat rename or copy record expected an empty path')
    end

    first_path, next_start = read_nul_section(raw_out, next_start)
    local current_path
    current_path, next_start = read_nul_section(raw_out, next_start)
    if first_path ~= diff.old_path or current_path ~= diff.current_path then
      error('git diff raw and numstat paths are misaligned')
    end
  elseif first_path == '' or first_path ~= diff.current_path then
    error('git diff raw and numstat paths are misaligned')
  end

  diff.added_lines = added_lines
  diff.removed_lines = removed_lines
  diff.binary = binary
  return next_start
end

---@return GitDiff[]
---@param raw_out string
function M.parse_diff_output(raw_out)
  if raw_out == '' then
    return {}
  end

  if raw_out:byte(1) ~= colon_byte then
    error('git diff output expected to start with ":"')
  end

  local diffs = {}
  local position = 1
  while raw_out:byte(position) == colon_byte do
    local diff
    diff, position = parse_raw_diff(raw_out, position)
    table.insert(diffs, diff)
  end

  for _, diff in ipairs(diffs) do
    position = parse_numstat_diff(diff, raw_out, position)
  end

  if position <= #raw_out then
    error('git diff output contains trailing data')
  end

  return diffs
end

---@param raw_out string
---@return string[]
function M.parse_ls_files_output(raw_out)
  if raw_out == '' then
    return {}
  end

  if raw_out:byte(#raw_out) ~= 0 then
    error('git ls-files output expected to end with NUL')
  end

  local paths = {}
  local path_start = 1
  for i = 1, #raw_out do
    if raw_out:byte(i) == 0 then
      if i == path_start then
        error('git ls-files output contains an empty path')
      end

      table.insert(paths, raw_out:sub(path_start, i - 1))
      path_start = i + 1
    end
  end

  return paths
end

---@param raw_out string
---@return GitRemote[]
function M.parse_remote_output(raw_out)
  local remotes = {}
  local seen = {}

  for line in raw_out:gmatch('[^\n]+') do
    local name, url = line:match('^(%S+)%s+(%S+)%s+%([%w]+%)$')
    if name == nil or url == nil then
      error('invalid git remote output: ' .. line)
    end

    if not seen[name] then
      seen[name] = true
      table.insert(remotes, { name = name, url = url })
    end
  end

  return remotes
end

return M
