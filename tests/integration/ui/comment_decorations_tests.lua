local presentation = require('diffreview.ui.comment_presentation')
local tracker = require('diffreview.ui.decoration_tracker')
local ui = require('diffreview.ui')
local helpers = require('integration.ui.side_by_side.helpers')
local handlers = require('helpers.ui_handlers')
local M = {}

M.render_should_keep_stale_text_at_file_level_and_clear_only_comments_when_reused = function()
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'one', 'two', 'three' })
  local diff = vim.api.nvim_create_namespace('test.diff')
  vim.api.nvim_buf_set_extmark(buffer, diff, 1, 0, {})
  local namespace = vim.api.nvim_create_namespace('test.comments')
  local state = tracker.new_state()
  local window = vim.api.nvim_get_current_win()
  local views = { { window = window, buffer = buffer, file_id = 'file', side = 'current', file_notes = true } }
  presentation.update(views, state, namespace, {
    {
      comment_id = 'valid',
      file_id = 'file',
      body = 'range',
      start_line = 2,
      end_line = 3,
      status = 'open',
    },
    {
      comment_id = 'stale',
      file_id = 'file',
      body = 'lost',
      start_line = 3,
      end_line = 3,
      status = 'stale',
    },
  })
  local marks = vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true })
  assert(#marks == 2 and marks[1][2] == 0 and marks[2][2] == 1)
  assert(marks[1][4].virt_text[1][1]:find('stale') and marks[2][4].virt_text[1][1]:find('open'))
  assert(marks[2][4].end_row == 3)
  presentation.update({}, state, namespace, {})
  assert(#vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}) == 0)
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
    { comment_id = 'note', file_id = 'first', body = 'note', status = 'open' },
  })
  local namespace = view.comment_namespace
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

M.cleanup_should_clear_all_review_namespaces_and_preserve_unrelated_marks_when_buffers_are_borrowed = function()
  local first_path = vim.fn.tempname() .. '.txt'
  local second_path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile({ 'first' }, first_path)
  vim.fn.writefile({ 'second' }, second_path)
  local view = ui.get_ui(handlers)
  local unrelated = vim.api.nvim_create_namespace('test.unrelated')
  local buffers = {}
  for _, path in ipairs({ first_path, second_path }) do
    view:display_diff_side_by_side({ operation = 'added', current = helpers.path(path) }, 'vertical', nil, path)
    local buffer = helpers.main_buffer(view)
    buffers[#buffers + 1] = buffer
    vim.api.nvim_buf_set_extmark(buffer, unrelated, 0, 0, {})
    view:update_review_comments({ { comment_id = path, file_id = path, body = 'note', status = 'open' } })
    assert(#vim.api.nvim_buf_get_extmarks(buffer, view.comment_namespace, 0, -1, {}) == 1)
    assert(#vim.api.nvim_buf_get_extmarks(buffer, view.side_by_side.namespace, 0, -1, {}) == 1)
  end
  view:cleanup()
  for index, buffer in ipairs(buffers) do
    assert(vim.api.nvim_buf_is_valid(buffer))
    assert(#vim.api.nvim_buf_get_extmarks(buffer, view.comment_namespace, 0, -1, {}) == 0)
    assert(#vim.api.nvim_buf_get_extmarks(buffer, view.side_by_side.namespace, 0, -1, {}) == 0)
    assert(#vim.api.nvim_buf_get_extmarks(buffer, unrelated, 0, -1, {}) == 1)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { index == 1 and 'first' or 'second' }))
    vim.api.nvim_buf_delete(buffer, { force = true })
  end
  vim.fn.delete(first_path)
  vim.fn.delete(second_path)
end

M.comment_text_matches_should_reject_replaced_buffers_when_review_window_remains_owned = function()
  local view = ui.get_ui(handlers)
  view:display_diff_side_by_side(
    { operation = 'untracked', current = helpers.snapshot('empty.txt', {}) },
    'vertical',
    nil,
    'file'
  )
  assert(view:comment_text_matches('file', 'current', {}))
  assert(not view:comment_text_matches('other', 'current', {}))
  assert(not view:comment_text_matches('file', 'old', {}))
  local window = vim.api.nvim_get_current_win()
  local replacement = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(window, replacement)
  assert(not view:comment_text_matches('file', 'current', {}))
  assert(view:comment_context() == nil)
  assert(not view:focus_comment({ comment_id = 'note', file_id = 'file', body = 'note', status = 'open' }))
  view:cleanup()
  if vim.api.nvim_buf_is_valid(replacement) then
    vim.api.nvim_buf_delete(replacement, { force = true })
  end
end

return M
