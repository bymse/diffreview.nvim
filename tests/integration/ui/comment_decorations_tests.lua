local decorations = require('diffreview.ui.comment_decorations')
local ui = require('diffreview.ui')
local helpers = require('integration.ui.side_by_side.helpers')
local handlers = require('helpers.ui_handlers')
local M = {}

M.render_should_keep_stale_text_at_file_level_and_clear_only_comments_when_reused = function()
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'one', 'two', 'three' })
  local diff = vim.api.nvim_create_namespace('test.diff')
  vim.api.nvim_buf_set_extmark(buffer, diff, 1, 0, {})
  local state = decorations.new_state(999)
  decorations.render(state, buffer, {
    {
      id = 'valid',
      file_id = 'file',
      body = 'range',
      start_line = 2,
      end_line = 3,
      status = 'open',
    },
    {
      id = 'stale',
      file_id = 'file',
      body = 'lost',
      start_line = 3,
      end_line = 3,
      status = 'stale',
    },
  }, 'file', 'current', true)
  local marks = vim.api.nvim_buf_get_extmarks(buffer, state.namespace, 0, -1, { details = true })
  assert(#marks == 2 and marks[1][2] == 0 and marks[2][2] == 1)
  assert(marks[1][4].virt_text[1][1]:find('stale') and marks[2][4].virt_text[1][1]:find('open'))
  assert(marks[2][4].end_row == 3)
  decorations.clear(state)
  assert(#vim.api.nvim_buf_get_extmarks(buffer, state.namespace, 0, -1, {}) == 0)
  assert(#vim.api.nvim_buf_get_extmarks(buffer, diff, 0, -1, {}) == 1)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'one', 'two', 'three' }))
  vim.api.nvim_buf_delete(buffer, { force = true })
end

M.update_review_comments_should_clear_prior_buffers_and_preserve_diff_marks_when_selection_changes = function()
  local view = ui.get_ui(handlers)
  view:display_diff_side_by_side(
    { operation = 'untracked', current = helpers.snapshot('first.txt', { 'one', 'two' }) },
    'vertical',
    nil,
    'first'
  )
  local buffer = helpers.main_buffer(view)
  local diff_marks = vim.api.nvim_buf_get_extmarks(buffer, view.side_by_side.namespace, 0, -1, {})
  assert(#diff_marks > 0)
  view:update_review_comments({
    { id = 'note', file_id = 'first', body = 'note', status = 'open' },
  })
  local namespace = view.side_by_side.comments.namespace
  assert(#vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}) == 1)
  assert(vim.deep_equal(vim.api.nvim_buf_get_extmarks(buffer, view.side_by_side.namespace, 0, -1, {}), diff_marks))
  view:display_diff_side_by_side(
    { operation = 'untracked', current = helpers.snapshot('second.txt', { 'second' }) },
    'vertical',
    nil,
    'second'
  )
  assert(#vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}) == 0)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'second' }))
  view:cleanup()
end

return M
