local quickfix = require('diffreview.ui.quickfix')
local native_diff = require('diffreview.ui.native_diff')
local side_by_side = require('diffreview.ui.side_by_side')
local M = {}

---@class ReviewSideBySideState
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
---@field instance_id integer
---@field side_by_side ReviewSideBySideState
---@field quickfix_id quickfix_id|nil
local ReviewUi = {}
ReviewUi.__index = ReviewUi

local next_instance_id = 0

---@param files ChangedFileViewModel[]
---@return nil
function ReviewUi:show_review_files(files)
  self.quickfix_id = quickfix.show_review_files(self.quickfix_id, self.instance_id, files)
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
  local ok, err = pcall(side_by_side.cleanup, self)
  quickfix.cleanup(self.quickfix_id, self.instance_id)
  self.quickfix_id = nil
  if not ok then
    error(err, 0)
  end
end

---@return ReviewUi
function M.get_ui()
  next_instance_id = next_instance_id + 1
  return setmetatable({
    instance_id = next_instance_id,
    quickfix_id = nil,
    side_by_side = {
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
