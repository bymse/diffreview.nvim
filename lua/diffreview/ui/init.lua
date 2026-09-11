local quickfix = require('diffreview.ui.quickfix')
local M = {}

---@class ChangedFileViewModel
---@field id string
---@field display_path string
---@field viewed boolean
---@param id quickfix_id|nil
---@param files ChangedFileViewModel[]
---@return quickfix_id
function M.show_review_files(id, files)
  return quickfix.show_review_files(id, files)
end

return M
