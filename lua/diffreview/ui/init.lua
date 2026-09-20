local quickfix = require('diffreview.ui.quickfix')
local native_diff = require('diffreview.ui.native_diff')
local side_by_side = require('diffreview.ui.side_by_side')
local M = {}

---@class ReviewSideBySideState
---@field instance_id integer
---@field namespace integer
---@field tabpage integer|nil
---@field main_window integer|nil
---@field companion_window integer|nil
---@field main_snapshot_buffer integer|nil
---@field companion_snapshot_buffer integer|nil
---@field information_buffer integer|nil
---@field decorated_buffer integer|nil
---@field active_layout ViewLayout|nil
---@field native_diff NativeDiffState

---@class ReviewUi
---@field side_by_side ReviewSideBySideState
local ReviewUi = {}
ReviewUi.__index = ReviewUi

local next_instance_id = 0

---@param id quickfix_id|nil
---@param files ChangedFileViewModel[]
---@return quickfix_id
function ReviewUi:show_review_files(id, files)
  return quickfix.show_review_files(id, files)
end

---@param diff DiffViewModel
---@param layout ViewLayout
---@return nil
function ReviewUi:display_diff_side_by_side(diff, layout)
  side_by_side.display_side_by_side(self, diff, layout)
end

---@param diff DiffViewModel
---@return nil
function ReviewUi:display_diff_inlinde(diff) end

---@return nil
function ReviewUi:cleanup()
  side_by_side.cleanup(self)
end

---@return ReviewUi
function M.get_ui()
  next_instance_id = next_instance_id + 1
  return setmetatable({
    side_by_side = {
      instance_id = next_instance_id,
      namespace = vim.api.nvim_create_namespace('diffreview.side_by_side.' .. next_instance_id),
      tabpage = nil,
      main_window = nil,
      companion_window = nil,
      main_snapshot_buffer = nil,
      companion_snapshot_buffer = nil,
      information_buffer = nil,
      decorated_buffer = nil,
      active_layout = nil,
      native_diff = native_diff.new_state(),
    },
  }, ReviewUi)
end

return M
