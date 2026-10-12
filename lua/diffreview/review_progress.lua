local M = {}
local comments = require('diffreview.comments')

---@class ReviewIdentity
---@field repository_root string
---@field source string
---@field baseline string
---@field target string

---@class ReviewFileRecord
---@field id string
---@field display_path string
---@field added_lines integer
---@field removed_lines integer
---@field fingerprint string
---@field viewed_fingerprint string|nil

---@class ReviewProgress
---@field version integer
---@field identity ReviewIdentity
---@field from_oid string
---@field to_oid string|nil
---@field head_oid string|nil
---@field files ReviewFileRecord[]
---@field comments ReviewComment[]

---@param previous ReviewProgress|nil
---@param loaded LoadedDiffs
---@param views table<string, DiffViewModel>|nil
---@return ReviewProgress
function M.reconcile(previous, loaded, views)
  local records = {}
  local by_id = {}
  if previous then
    for _, record in ipairs(previous.files) do
      local copy = vim.deepcopy(record)
      records[#records + 1] = copy
      by_id[copy.id] = copy
    end
  end
  for _, summary in ipairs(loaded.files) do
    local record = by_id[summary.id]
    if not record then
      record = { id = summary.id }
      records[#records + 1] = record
    end
    record.display_path = summary.display_path
    record.added_lines = summary.added_lines
    record.removed_lines = summary.removed_lines
    record.fingerprint = assert(loaded.entries_by_id[summary.id].fingerprint)
    summary.viewed = record.viewed_fingerprint == record.fingerprint
  end
  return {
    version = 2,
    identity = loaded.identity,
    from_oid = loaded.comparison.from_oid,
    to_oid = loaded.comparison.to_oid,
    head_oid = loaded.comparison.head_oid,
    files = records,
    comments = comments.reconcile(previous and previous.comments or {}, loaded, views or {}),
  }
end

return M
