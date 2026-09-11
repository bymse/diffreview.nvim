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
  local unviewed = changed_file('lua/unviewed.lua', false)
  local viewed = changed_file('lua/viewed.lua', true)

  ui.show_review_files(nil, { unviewed, viewed })

  assert(
    vim.deep_equal(get_displayed_lines(), {
      '[ ] ' .. unviewed.display_path,
      '[x] ' .. viewed.display_path,
    }),
    'expected viewed and unviewed files to be displayed'
  )
end

M.show_review_files_should_order_unviewed_before_viewed_when_states_are_mixed = function()
  reset_quickfix()
  local viewed_first = changed_file('viewed-first.lua', true)
  local unviewed_first = changed_file('unviewed-first.lua', false)
  local viewed_second = changed_file('viewed-second.lua', true)
  local unviewed_second = changed_file('unviewed-second.lua', false)

  ui.show_review_files(nil, { viewed_first, unviewed_first, viewed_second, unviewed_second })

  assert(
    vim.deep_equal(get_displayed_lines(), {
      '[ ] ' .. unviewed_first.display_path,
      '[ ] ' .. unviewed_second.display_path,
      '[x] ' .. viewed_first.display_path,
      '[x] ' .. viewed_second.display_path,
    }),
    'expected unviewed files before viewed files while preserving their order'
  )
end

M.show_review_files_should_store_file_id_without_file_location = function()
  reset_quickfix()
  local deleted = changed_file('deleted.lua', false)

  ui.show_review_files(nil, { deleted })

  local item = vim.fn.getqflist({ items = 1 }).items[1]
  assert(item.bufnr == 0, 'expected entry not to reference a file buffer')
  assert(item.user_data.file_id == deleted.id, 'expected entry to reference review state by file ID')
end

M.show_review_files_should_update_same_list_when_other_lists_exist = function()
  reset_quickfix()
  local original = changed_file('original.lua', false)
  local id = ui.show_review_files(nil, { original })
  vim.fn.setqflist({}, ' ', {
    nr = '$',
    title = 'Unrelated list',
    items = { { text = 'unrelated' } },
  })
  local replacement = changed_file('replacement.lua', true)

  ui.show_review_files(id, { replacement })

  assert(
    vim.deep_equal(get_displayed_lines(), {
      '[x] ' .. replacement.display_path,
    }),
    'expected the updated review files to be displayed'
  )
  vim.cmd('silent! cnewer')
  vim.cmd('silent! colder')
  assert(
    vim.deep_equal(get_displayed_lines(), {
      '[x] ' .. replacement.display_path,
    }),
    'expected the existing review list to contain the updated display'
  )
end

return M
