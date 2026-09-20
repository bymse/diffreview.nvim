local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

M.display_side_by_side_should_render_two_windows_when_renamed_content_changes = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'renamed',
    old = helpers.snapshot('old.txt', { 'old' }, '100644'),
    current = helpers.snapshot('new.txt', { 'new' }, '100755'),
    content_changed = true,
  }, 'horizontal')
  local state = review_ui.side_by_side
  assert(
    vim.api.nvim_win_get_position(state.companion_window)[1] < vim.api.nvim_win_get_position(state.main_window)[1],
    'expected old above'
  )
  assert(vim.wo[state.main_window].diff and vim.wo[state.companion_window].diff, 'expected native diff')
  helpers.cleanup(review_ui)
end

return M
