local view_models = require('helpers.diff_view_model')
local M = { snapshot = view_models.snapshot, binary = view_models.binary, path = view_models.path }

---@param review_ui ReviewUi
---@return integer
function M.main_buffer(review_ui)
  local window = review_ui.side_by_side.main_window
  assert(window ~= nil, 'expected main window')
  return vim.api.nvim_win_get_buf(window)
end

---@param review_ui ReviewUi
---@return string[]
function M.lines(review_ui)
  return vim.api.nvim_buf_get_lines(M.main_buffer(review_ui), 0, -1, false)
end

---@param review_ui ReviewUi
function M.cleanup(review_ui)
  review_ui:cleanup()
end

return M
