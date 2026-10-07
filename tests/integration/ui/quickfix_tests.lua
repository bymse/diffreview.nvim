local ui = require('diffreview.ui')
local M = {}
local handlers = require('helpers.ui_handlers')

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
  return vim.fn.getqflist({ id = id, items = 1, title = 1, nr = 0 })
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
  local review_ui = ui.get_ui(handlers)
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
  local review_ui = ui.get_ui(handlers)
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

M.show_review_files_should_preserve_unrelated_list_contents_and_history_when_updating = function()
  reset_quickfix()
  vim.fn.setqflist({}, ' ', {
    nr = '$',
    title = 'Unrelated list',
    items = { { text = 'unrelated' } },
  })
  local unrelated_id = vim.fn.getqflist({ id = 0 }).id
  local review_ui = ui.get_ui(handlers)
  review_ui:show_review_files({ changed_file('original.lua', false) })
  local review_id = vim.fn.getqflist({ id = 0 }).id

  review_ui:show_review_files({ changed_file('replacement.lua', true) })

  local unrelated = vim.fn.getqflist({ id = unrelated_id, items = 1, nr = 0 })
  local review = quickfix_list(review_id)
  assert(unrelated.items[1].text == 'unrelated', 'expected unrelated list contents to be preserved')
  assert(unrelated.nr < review.nr, 'expected unrelated quickfix history to be preserved')
  assert(review.id == review_id, 'expected updates to retain the owned quickfix list')
  assert(review.items[1].text:match('replacement.lua'), 'expected updated review file in history')
end

M.cleanup_should_close_foreign_tab_window_when_it_displays_review_list = function()
  reset_quickfix()
  local review_ui = ui.get_ui(handlers)
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local owned_id = vim.fn.getqflist({ id = 0 }).id
  local owner_tab = vim.api.nvim_get_current_tabpage()
  local owned_window = current_quickfix_window()
  assert(owned_window ~= nil, 'expected owned drawer')
  ---@cast owned_window integer

  vim.cmd('tabnew')
  local foreign_tab = vim.api.nvim_get_current_tabpage()
  local foreign_id = create_unrelated_list()
  vim.cmd('botright copen')
  local foreign_window = current_quickfix_window()
  ---@cast foreign_window integer
  vim.api.nvim_set_current_tabpage(owner_tab)
  vim.cmd('silent colder')
  assert(vim.fn.getqflist({ id = 0 }).id == owned_id, 'expected review list to be displayed')

  review_ui:cleanup()

  local owned = quickfix_list(owned_id)
  assert(#owned.items == 0, 'expected owned list to be emptied')
  assert(owned.title == 'Diff Review', 'expected owned list title to remain unchanged')
  assert(not vim.api.nvim_win_is_valid(owned_window), 'expected owned drawer to close with tab')
  assert(not vim.api.nvim_tabpage_is_valid(owner_tab), 'expected owned tab to close')
  assert(vim.api.nvim_tabpage_is_valid(foreign_tab), 'expected foreign tab to remain open')
  assert(not vim.api.nvim_win_is_valid(foreign_window), 'expected review list window to close in foreign tab')
  assert(quickfix_list(foreign_id).items[1].text == 'unrelated', 'expected foreign list to remain unchanged')
end

M.cleanup_should_preserve_foreign_tab_window_when_it_displays_unrelated_list = function()
  reset_quickfix()
  local review_ui = ui.get_ui(handlers)
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local review_id = vim.fn.getqflist({ id = 0 }).id
  vim.cmd('tabnew')
  local foreign_id = create_unrelated_list()
  vim.cmd('botright copen')
  local foreign_window = current_quickfix_window()
  assert(foreign_window ~= nil, 'expected unrelated quickfix window')
  assert(vim.fn.getqflist({ id = 0 }).id == foreign_id, 'expected unrelated list to be displayed')

  review_ui:cleanup()

  assert(vim.api.nvim_win_is_valid(foreign_window), 'expected unrelated quickfix window to remain open')
  assert(#quickfix_list(review_id).items == 0, 'expected review list cleared')
  assert(quickfix_list(foreign_id).items[1].text == 'unrelated', 'expected unrelated list unchanged')
end

M.cleanup_should_preserve_foreign_context_when_identity_is_reused = function()
  reset_quickfix()
  local review_ui = ui.get_ui(handlers)
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local owned_id = vim.fn.getqflist({ id = 0 }).id
  ---@type any
  local properties = { id = owned_id, context = 'other' }
  vim.fn.setqflist({}, 'u', properties)

  review_ui:cleanup()

  assert(quickfix_list(owned_id).items[1].text:match('owned.lua'), 'expected foreign-context list to remain unchanged')
end

M.cleanup_should_empty_owned_list_when_it_is_not_current = function()
  reset_quickfix()
  local review_ui = ui.get_ui(handlers)
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local owned_id = vim.fn.getqflist({ id = 0 }).id
  local foreign_id = create_unrelated_list()
  vim.cmd('cclose')
  vim.cmd('botright copen')
  local foreign_window = current_quickfix_window()
  ---@cast foreign_window integer

  review_ui:cleanup()

  assert(#quickfix_list(owned_id).items == 0, 'expected non-current owned list to be emptied')
  assert(quickfix_list(foreign_id).items[1].text == 'unrelated', 'expected current foreign list to remain unchanged')
  assert(not vim.api.nvim_win_is_valid(foreign_window), 'expected windows in owned tab to close')
end

M.cleanup_should_be_safe_when_repeated_or_partially_acquired = function()
  reset_quickfix()
  local partial_ui = ui.get_ui(handlers)
  partial_ui:cleanup()
  partial_ui:cleanup()

  local review_ui = ui.get_ui(handlers)
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local owned_id = vim.fn.getqflist({ id = 0 }).id
  review_ui:cleanup()
  review_ui:cleanup()

  assert(#quickfix_list(owned_id).items == 0, 'expected repeated cleanup to leave review list empty')
  assert(#vim.api.nvim_list_tabpages() >= 1, 'expected a remaining tab')
end

M.cleanup_should_release_tab_when_initial_list_presentation_fails = function()
  local original = vim.api.nvim_get_current_tabpage()
  local count = #vim.api.nvim_list_tabpages()
  local review_ui = ui.get_ui(handlers)
  ---@type any
  local malformed = {}
  local ok = pcall(review_ui.show_review_files, review_ui, { changed_file('valid.lua', false), malformed })
  assert(not ok, 'expected invalid changed-file data to fail list presentation')
  assert(#vim.api.nvim_list_tabpages() == count + 1, 'expected acquired tab before failure')
  review_ui:cleanup()
  review_ui:cleanup()
  assert(#vim.api.nvim_list_tabpages() == count, 'expected failed review tab cleanup')
  assert(vim.api.nvim_get_current_tabpage() == original, 'expected original tab focus')
end

M.cleanup_should_clear_owned_list_when_initial_presentation_fails_after_list_creation = function()
  reset_quickfix()
  local foreign_id = create_unrelated_list()
  local original = vim.api.nvim_get_current_tabpage()
  local count = #vim.api.nvim_list_tabpages()
  local review_ui = ui.get_ui(handlers)
  local malformed = changed_file('missing-id.lua', false)
  ---@type any
  local invalid = malformed
  invalid.id = nil
  local ok = pcall(review_ui.show_review_files, review_ui, { invalid })
  assert(not ok, 'expected invalid file ID to fail after list creation')
  local id = vim.fn.getqflist({ id = 0 }).id
  assert(id ~= foreign_id, 'expected a newly acquired review list')
  assert(#quickfix_list(id).items == 1, 'expected list contents before cleanup')
  review_ui:cleanup()
  review_ui:cleanup()
  assert(#quickfix_list(id).items == 0, 'expected owned list emptied after failed presentation')
  assert(quickfix_list(foreign_id).items[1].text == 'unrelated', 'expected foreign list preserved')
  assert(#vim.api.nvim_list_tabpages() == count, 'expected acquired tab closed')
  assert(vim.api.nvim_get_current_tabpage() == original, 'expected original focus')
end

M.cleanup_should_replace_review_tab_when_it_is_the_only_tab = function()
  local review_ui = ui.get_ui(handlers)
  review_ui:show_review_files({ changed_file('owned.lua', false) })
  local review_tab = vim.api.nvim_get_current_tabpage()
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= review_tab then
      vim.api.nvim_set_current_tabpage(tab)
      vim.cmd('tabclose!')
    end
  end
  vim.api.nvim_set_current_tabpage(review_tab)
  assert(#vim.api.nvim_list_tabpages() == 1, 'expected review to be the only tab')
  review_ui:cleanup()
  assert(#vim.api.nvim_list_tabpages() == 1, 'expected replacement tab')
  assert(not vim.api.nvim_tabpage_is_valid(review_tab), 'expected owned tab closed')
  assert(vim.api.nvim_get_current_tabpage() ~= review_tab, 'expected replacement focused')
end

return M
