local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

M.display_side_by_side_should_render_deleted_snapshot_when_file_is_removed = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(
    { operation = 'deleted', old = helpers.snapshot('deleted.txt', { 'gone' }) },
    'vertical'
  )
  assert(vim.deep_equal(helpers.lines(review_ui), { 'gone' }), 'expected deleted content')
  local marks = vim.api.nvim_buf_get_extmarks(
    helpers.main_buffer(review_ui),
    review_ui.side_by_side.namespace,
    0,
    -1,
    { details = true }
  )
  assert(
    #marks == 1
      and marks[1][2] == 0
      and marks[1][3] == 0
      and marks[1][4].end_row == 1
      and marks[1][4].hl_group == 'DiffDelete',
    'expected full-line DiffDelete mark'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_restore_read_only_snapshot_options_when_reusing_buffer = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(
    { operation = 'deleted', old = helpers.snapshot('unknown.no_match', {}) },
    'vertical'
  )
  local buffer = helpers.main_buffer(review_ui)

  assert(vim.api.nvim_get_option_value('buftype', { buf = buffer }) == 'nofile', 'expected nofile buffer')
  assert(not vim.api.nvim_get_option_value('buflisted', { buf = buffer }), 'expected unlisted buffer')
  assert(not vim.api.nvim_get_option_value('swapfile', { buf = buffer }), 'expected no swapfile')
  assert(not vim.api.nvim_get_option_value('modifiable', { buf = buffer }), 'expected immutable buffer')
  assert(vim.api.nvim_get_option_value('readonly', { buf = buffer }), 'expected read-only buffer')
  assert(vim.api.nvim_get_option_value('filetype', { buf = buffer }) == '', 'expected empty unmatched filetype')
  helpers.cleanup(review_ui)
end

return M
