local quickfix = require('diffreview.ui.quickfix')
local M = {}

---@class ReviewUi
---@field main_window integer|nil
---@field companion_window integer|nil
---@field scratch_buffers_pool integer[]
local ReviewUi = {}
ReviewUi.__index = ReviewUi

---@param id quickfix_id|nil
---@param files ChangedFileViewModel[]
---@return quickfix_id
function ReviewUi:show_review_files(id, files)
  return quickfix.show_review_files(id, files)
end

---@param diff DiffViewModel
---@param layout ViewLayout
function ReviewUi:display_diff_side_by_side(diff, layout) end

---@param diff DiffViewModel
---@return nil
function ReviewUi:display_diff_inlinde(diff) end

function M.get_ui()
  return setmetatable({ scratch_buffers_pool = {} }, ReviewUi)
end

return M
