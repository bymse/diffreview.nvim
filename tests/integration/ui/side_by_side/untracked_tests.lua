local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

M.display_side_by_side_should_not_decorate_empty_untracked_snapshot = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(
    { operation = 'untracked', current = helpers.snapshot('empty.txt', {}) },
    'vertical'
  )
  local buffer = helpers.main_buffer(review_ui)
  assert(
    #vim.api.nvim_buf_get_extmarks(buffer, review_ui.side_by_side.namespace, 0, -1, {}) == 0,
    'expected no empty-line decoration'
  )
  helpers.cleanup(review_ui)
end

return M
