local ui = require('diffreview.ui')
local quickfix = require('diffreview.ui.quickfix.comments_list')
local handlers = require('helpers.ui_handlers')
local M = {}

M.update_review_comments_should_preserve_active_files_when_comments_are_inactive = function()
  local view = ui.get_ui(handlers)
  view:show_review_files({ { id = 'file', display_path = 'file', added_lines = 1, removed_lines = 0, viewed = false } })
  local files = vim.fn.getqflist({ id = 0 }).id
  local records = { { id = 'note', file_id = 'file', body = 'preview', status = 'resolved' } }
  view:update_review_comments(records)
  assert(vim.fn.getqflist({ id = 0 }).id == files and view:files_open())
  view:show_review_comments(records)
  local notes = vim.fn.getqflist({ id = 0, items = 1, context = 1 })
  assert(notes.id ~= files and notes.context ~= vim.fn.getqflist({ id = files, context = 1 }).context)
  assert(notes.items[1].text:find('resolved') and notes.items[1].text:find('preview'))
  assert(quickfix.comment_row_id(notes.id, view.instance_id, view.tabpage, 1) == 'note')
  vim.fn.setqflist(
    {},
    'r',
    { id = notes.id, items = { { valid = true, text = 'replacement', user_data = { comment_id = 'other' } } } }
  )
  assert(quickfix.comment_row_id(notes.id, view.instance_id, view.tabpage, 1) == nil)
  view:show_review_files({})
  view:update_review_comments(records)
  assert(vim.fn.getqflist({ id = 0 }).id == files)
  view:cleanup()
  assert(#vim.fn.getqflist({ id = notes.id, items = 1 }).items == 0)
end

return M
