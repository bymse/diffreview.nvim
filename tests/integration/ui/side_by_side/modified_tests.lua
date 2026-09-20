local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

M.display_side_by_side_should_render_mode_information_when_modified_content_is_unchanged = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'modified',
    old = helpers.snapshot('script.sh', { 'run' }, '100644'),
    current = helpers.snapshot('script.sh', { 'run' }, '100755'),
    content_changed = false,
  }, 'vertical')
  assert(
    vim.deep_equal(helpers.lines(review_ui), {
      'Mode-only change',
      'Operation: modified',
      'Path: script.sh',
      'Old mode: file (100644)',
      'Current mode: executable file (100755)',
      'Text content is unchanged.',
    }),
    'expected mode-only information'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_render_old_left_of_current_when_modified_content_changes = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'modified',
    old = helpers.snapshot('a.txt', { 'old' }),
    current = helpers.snapshot('a.txt', { 'current' }),
    content_changed = true,
  }, 'vertical')
  local state = review_ui.side_by_side
  assert(#vim.api.nvim_tabpage_list_wins(state.tabpage) == 2, 'expected exactly two review windows')
  assert(vim.api.nvim_get_current_win() == state.main_window, 'expected current content focus')
  assert(
    vim.api.nvim_win_get_position(state.companion_window)[2] < vim.api.nvim_win_get_position(state.main_window)[2],
    'expected old left'
  )
  assert(vim.wo[state.main_window].diff and vim.wo[state.companion_window].diff, 'expected native diff')
  assert(
    vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.companion_window), 0, -1, false)[1] == 'old',
    'expected old buffer'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_render_old_above_current_when_modified_layout_is_horizontal = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'modified',
    old = helpers.snapshot('a.txt', { 'old' }),
    current = helpers.snapshot('a.txt', { 'current' }),
    content_changed = true,
  }, 'horizontal')
  local state = review_ui.side_by_side
  assert(
    vim.api.nvim_win_get_position(state.companion_window)[1] < vim.api.nvim_win_get_position(state.main_window)[1],
    'expected old above'
  )
  helpers.cleanup(review_ui)
end

return M
