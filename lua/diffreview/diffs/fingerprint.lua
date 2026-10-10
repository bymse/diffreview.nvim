local content = require('diffreview.diffs.content')
local async_operation = require('diffreview.async_operation')

local M = {}

---@param repo GitRepo
---@param comparison ResolvedComparison
---@param entry LoadedDiffEntry
---@param operation AsyncOperation|nil
---@param snapshot WorktreeFingerprintInput|nil
---@return string|nil, string|nil
function M.compute(repo, comparison, entry, operation, snapshot)
  local diff = entry.git_diff
  local fields = {}
  local unmerged = false
  if diff then
    fields =
      { diff.status, diff.old_path or diff.current_path, diff.current_path, diff.old_mode, diff.new_mode, diff.old_oid }
    if comparison.target_is_worktree then
      local result, stages = repo:unmerged_stages(diff.current_path)
      if not result.ok or stages == nil then
        return nil, result.error or 'Unable to read index stages'
      end
      fields[#fields + 1] = stages
      unmerged = stages ~= ''
    end
  else
    fields = { 'untracked', '', assert(entry.untracked_path), '000000', '000000', '' }
  end
  if diff and ((diff.status == 'D' and not unmerged) or not comparison.target_is_worktree) then
    fields[#fields + 1] = diff.new_oid
  else
    local bytes, err, mode
    if snapshot then
      bytes, mode = snapshot.bytes, snapshot.mode
    else
      bytes, err, mode = content.read_worktree_bytes(assert(entry.absolute_path))
    end
    if bytes == nil or mode == nil then
      return nil, err
    end
    fields[#fields + 1] = mode
    fields[#fields + 1] = vim.fn.sha256(bytes)
  end
  if async_operation.is_canceled(operation) then
    return nil, 'Canceled'
  end
  local serialized = {}
  for _, field in ipairs(fields) do
    serialized[#serialized + 1] = #field .. ':' .. field
  end
  return vim.fn.sha256(table.concat(serialized)), nil
end

return M
