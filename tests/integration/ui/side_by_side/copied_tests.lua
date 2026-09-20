local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

M.display_side_by_side_should_render_path_backed_current_buffer_when_copied_content_changes = function()
  local path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile({ 'working tree' }, path)
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'copied',
    old = helpers.snapshot('source.txt', { 'old snapshot' }),
    current = helpers.path(path),
    content_changed = true,
  }, 'vertical')
  assert(vim.api.nvim_buf_get_name(helpers.main_buffer(review_ui)) == path, 'expected real current buffer')
  assert(
    vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(review_ui.side_by_side.companion_window), 0, -1, false)[1]
      == 'old snapshot',
    'expected old scratch buffer'
  )
  helpers.cleanup(review_ui)
  vim.fn.delete(path)
end

return M
