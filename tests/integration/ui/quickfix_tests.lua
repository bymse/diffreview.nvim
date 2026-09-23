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

---@param id integer
---@return table
local function quickfix_list(id)
  return vim.fn.getqflist({ id = id, items = 1, title = 1, context = 1, quickfixtextfunc = 1, qfbufnr = 1 })
end

---@return integer|nil
local function current_quickfix_window()
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local info = vim.fn.getwininfo(window)[1]
    if info.quickfix == 1 and info.loclist == 0 then
      return window
    end
  end
end

---@return integer
local function create_unrelated_list()
  vim.fn.setqflist({}, ' ', {
    nr = '$',
    title = 'Unrelated list',
    items = { { text = 'unrelated' } },
    context = { plugin = 'other' },
  })
  return vim.fn.getqflist({ id = 0 }).id
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
  assert(context == 'diffreview:files:' .. review_ui.instance_id, 'expected exact instance ownership context')
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
  assert(review.context == 'diffreview:files:' .. review_ui.instance_id, 'expected instance context after update')
end

M.cleanup_should_empty_owned_list_and_close_only_owned_current_tab_window = function()
  reset_quickfix()
  local review_ui = ui.get_ui()
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local owned_id = review_ui.quickfix_id
  ---@cast owned_id integer
  local owner_tab = vim.api.nvim_get_current_tabpage()

  vim.cmd('tabnew')
  local foreign_id = create_unrelated_list()
  vim.cmd('botright copen')
  local foreign_window = current_quickfix_window()
  ---@cast foreign_window integer
  vim.api.nvim_set_current_tabpage(owner_tab)
  vim.cmd('silent colder')

  review_ui:cleanup()

  local owned = quickfix_list(owned_id)
  assert(#owned.items == 0, 'expected owned list to be emptied')
  assert(owned.title == 'Diff Review', 'expected owned list title to remain unchanged')
  assert(owned.context == 'diffreview:files:' .. review_ui.instance_id, 'expected owned context to remain unchanged')
  assert(current_quickfix_window() == nil, 'expected owned current-tab quickfix window to close')
  vim.api.nvim_set_current_tabpage(vim.api.nvim_win_get_tabpage(foreign_window))
  assert(vim.api.nvim_win_is_valid(foreign_window), 'expected foreign-tab quickfix window to remain open')
  assert(quickfix_list(foreign_id).items[1].text == 'unrelated', 'expected foreign list to remain unchanged')
end

M.cleanup_should_preserve_foreign_context_when_identity_is_reused = function()
  reset_quickfix()
  local review_ui = ui.get_ui()
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local owned_id = review_ui.quickfix_id
  ---@cast owned_id integer
  ---@type any
  local properties = { id = owned_id, context = 'other' }
  vim.fn.setqflist({}, 'u', properties)

  review_ui:cleanup()

  assert(quickfix_list(owned_id).items[1].text:match('owned.lua'), 'expected foreign-context list to remain unchanged')
  assert(review_ui.quickfix_id == nil, 'expected facade identity to clear after cleanup')
end

M.cleanup_should_empty_owned_list_when_it_is_not_current = function()
  reset_quickfix()
  local review_ui = ui.get_ui()
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local owned_id = review_ui.quickfix_id
  ---@cast owned_id integer
  local foreign_id = create_unrelated_list()
  vim.cmd('cclose')
  vim.cmd('botright copen')
  local foreign_window = current_quickfix_window()
  ---@cast foreign_window integer

  review_ui:cleanup()

  assert(#quickfix_list(owned_id).items == 0, 'expected non-current owned list to be emptied')
  assert(quickfix_list(foreign_id).items[1].text == 'unrelated', 'expected current foreign list to remain unchanged')
  assert(vim.api.nvim_win_is_valid(foreign_window), 'expected foreign current-tab quickfix window to remain open')
end

M.cleanup_should_be_safe_when_repeated_or_partially_acquired = function()
  reset_quickfix()
  local partial_ui = ui.get_ui()
  partial_ui:cleanup()
  partial_ui:cleanup()

  local review_ui = ui.get_ui()
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  review_ui:cleanup()
  review_ui:cleanup()

  assert(review_ui.quickfix_id == nil, 'expected repeated cleanup to retain no identity')
end

M.show_review_files_should_replace_stale_or_foreign_stored_id_without_mutating_foreign_list = function()
  reset_quickfix()
  local foreign_id = create_unrelated_list()
  local review_ui = ui.get_ui()
  review_ui.quickfix_id = foreign_id

  review_ui:show_review_files({ changed_file('replacement.lua', false) })

  assert(review_ui.quickfix_id ~= foreign_id, 'expected foreign stored identity to be replaced')
  assert(quickfix_list(foreign_id).items[1].text == 'unrelated', 'expected foreign list to remain unchanged')
  review_ui.quickfix_id = 999999
  review_ui:show_review_files({ changed_file('stale.lua', false) })
  assert(review_ui.quickfix_id ~= 999999, 'expected stale identity to be replaced')
end

return M
