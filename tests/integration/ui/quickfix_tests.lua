local ui = require('diffreview.ui')
local M = {}

local function reset_quickfix()
  vim.cmd('silent! cclose')
  vim.fn.setqflist({}, 'f')
end

---@param display_path string
---@param viewed boolean
---@return ChangedFileViewModel
local function changed_file(display_path, viewed)
  return {
    id = display_path,
    display_path = display_path,
    added_lines = 123,
    removed_lines = 123,
    viewed = viewed,
  }
end

---@return string[]
local function get_displayed_lines()
  local buffer = vim.fn.getqflist({ qfbufnr = 0 }).qfbufnr
  return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

M.show_review_files_should_display_viewed_and_unviewed_files_when_creating_list = function()
  reset_quickfix()
  local review_ui = ui.get_ui()
  local unviewed = changed_file('path/relative', false)
  local viewed = changed_file('viewed/path/relative', true)

  review_ui:show_review_files({ unviewed, viewed })

  assert(
    vim.deep_equal(get_displayed_lines(), {
      '[ ] -123/+123 path/relative',
      '[x] -123/+123 viewed/path/relative',
    }),
    'expected viewed and unviewed files to be displayed'
  )
end

M.show_review_files_should_order_unviewed_before_viewed_when_states_are_mixed = function()
  reset_quickfix()
  local review_ui = ui.get_ui()
  local viewed_first = changed_file('viewed-first.lua', true)
  local unviewed_first = changed_file('unviewed-first.lua', false)
  local viewed_second = changed_file('viewed-second.lua', true)
  local unviewed_second = changed_file('unviewed-second.lua', false)

  review_ui:show_review_files({ viewed_first, unviewed_first, viewed_second, unviewed_second })

  assert(
    vim.deep_equal(get_displayed_lines(), {
      '[ ] -123/+123 ' .. unviewed_first.display_path,
      '[ ] -123/+123 ' .. unviewed_second.display_path,
      '[x] -123/+123 ' .. viewed_first.display_path,
      '[x] -123/+123 ' .. viewed_second.display_path,
    }),
    'expected unviewed files before viewed files while preserving their order'
  )
end

M.show_review_files_should_store_file_id_without_file_location = function()
  reset_quickfix()
  local review_ui = ui.get_ui()
  local deleted = changed_file('deleted.lua', false)

  review_ui:show_review_files({ deleted })

  local item = vim.fn.getqflist({ items = 1 }).items[1]
  assert(item.bufnr == 0, 'expected entry not to reference a file buffer')
  assert(item.module == '', 'expected entry not to use the module field')
  assert(item.user_data.file_id == deleted.id, 'expected entry to reference review state by file ID')
end

M.show_review_files_should_update_same_list_when_other_lists_exist = function()
  reset_quickfix()
  local review_ui = ui.get_ui()
  local original = changed_file('original.lua', false)
  review_ui:show_review_files({ original })
  vim.fn.setqflist({}, ' ', {
    nr = '$',
    title = 'Unrelated list',
    items = { { text = 'unrelated' } },
  })
  local replacement = changed_file('replacement.lua', true)

  review_ui:show_review_files({ replacement })

  assert(
    vim.deep_equal(get_displayed_lines(), {
      '[x] -123/+123 ' .. replacement.display_path,
    }),
    'expected the updated review files to be displayed'
  )
  vim.cmd('silent! cnewer')
  vim.cmd('silent! colder')
  assert(
    vim.deep_equal(get_displayed_lines(), {
      '[x] -123/+123 ' .. replacement.display_path,
    }),
    'expected the existing review list to contain the updated display'
  )
end

M.show_review_files_should_store_exact_instance_context_when_creating_list = function()
  reset_quickfix()
  local review_ui = ui.get_ui()

  review_ui:show_review_files({ changed_file('owned.lua', false) })

  local context = vim.fn.getqflist({ id = review_ui.quickfix_id, context = 1 }).context
  assert(vim.deep_equal(context, review_ui.quickfix_context), 'expected exact instance ownership context')
end

M.show_review_files_should_preserve_unrelated_list_contents_and_history_when_updating = function()
  reset_quickfix()
  vim.fn.setqflist({}, ' ', {
    nr = '$',
    title = 'Unrelated list',
    items = { { text = 'unrelated' } },
  })
  local unrelated_id = vim.fn.getqflist({ id = 0 }).id
  local review_ui = ui.get_ui()
  review_ui:show_review_files({ changed_file('original.lua', false) })
  local review_id = review_ui.quickfix_id

  review_ui:show_review_files({ changed_file('replacement.lua', true) })

  local unrelated = vim.fn.getqflist({ id = unrelated_id, items = 1, nr = 0 })
  local review = vim.fn.getqflist({ id = review_id, items = 1, context = 1, nr = 0 })
  assert(unrelated.items[1].text == 'unrelated', 'expected unrelated list contents to be preserved')
  assert(unrelated.nr < review.nr, 'expected unrelated quickfix history to be preserved')
  assert(review.id == review_id, 'expected updates to retain the owned quickfix list')
  assert(vim.deep_equal(review.context, review_ui.quickfix_context), 'expected instance context after update')
end

return M
