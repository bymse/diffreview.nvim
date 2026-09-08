local quickfix = require('diffreview.ui.quickfix')
local M = {}

---@class ChangedFileViewModel
---@field absolute_path string
---@field relative_path string
---@field viewed boolean
---@param id quickfix_id|nil
---@param files ChangedFileViewModel[]
---@return quickfix_id
function M.show_review_files(id, files)
  return quickfix.show_review_files(id, files)
end

return M
