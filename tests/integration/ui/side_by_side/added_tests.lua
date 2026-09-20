local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

---@param tabpage integer
---@return table
local function tab_state(tabpage)
  local windows = vim.api.nvim_tabpage_list_wins(tabpage)
  local assignments = {}
  local options = {}
  for _, window in ipairs(windows) do
    assignments[window] = vim.api.nvim_win_get_buf(window)
    options[window] = vim.api.nvim_win_call(window, function()
      return {
        diff = vim.wo.diff,
        scrollbind = vim.wo.scrollbind,
        cursorbind = vim.wo.cursorbind,
      }
    end)
  end
  return {
    windows = windows,
    assignments = assignments,
    layout = vim.api.nvim_win_call(windows[1], vim.fn.winlayout),
    options = options,
  }
end

M.display_side_by_side_should_render_added_snapshot_when_text_is_present = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(
    { operation = 'added', current = helpers.snapshot('added.txt', { 'one', 'two' }) },
    'vertical'
  )
  local buffer = helpers.main_buffer(review_ui)
  assert(vim.deep_equal(helpers.lines(review_ui), { 'one', 'two' }), 'expected snapshot lines')
  local marks = vim.api.nvim_buf_get_extmarks(buffer, review_ui.side_by_side.namespace, 0, -1, { details = true })
  assert(#marks == 2, 'expected add decorations')
  assert(
    marks[1][2] == 0 and marks[1][3] == 0 and marks[1][4].end_row == 1 and marks[1][4].hl_group == 'DiffAdd',
    'expected first full-line DiffAdd mark'
  )
  assert(
    marks[2][2] == 1 and marks[2][4].end_row == 2 and marks[2][4].hl_group == 'DiffAdd',
    'expected second full-line DiffAdd mark'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_recreate_deleted_scratch_buffer_when_displaying_again = function()
  local review_ui = ui.get_ui()
  local diff = { operation = 'added', current = helpers.snapshot('first.txt', { 'first' }) }
  review_ui:display_diff_side_by_side(diff, 'vertical')
  local first_buffer = helpers.main_buffer(review_ui)
  vim.api.nvim_buf_delete(first_buffer, { force = true })

  review_ui:display_diff_side_by_side(
    { operation = 'added', current = helpers.snapshot('second.txt', { 'second' }) },
    'vertical'
  )

  assert(helpers.main_buffer(review_ui) ~= first_buffer, 'expected recreated scratch buffer')
  assert(vim.deep_equal(helpers.lines(review_ui), { 'second' }), 'expected replacement content')
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_leave_tab_and_buffers_unchanged_when_layout_is_invalid = function()
  local review_ui = ui.get_ui()
  local tab_count = #vim.api.nvim_list_tabpages()
  local buffer_count = #vim.api.nvim_list_bufs()
  local ok = pcall(
    review_ui.display_diff_side_by_side,
    review_ui,
    { operation = 'added', current = helpers.snapshot('file.txt') },
    'diagonal'
  )

  assert(not ok, 'expected invalid layout error')
  assert(#vim.api.nvim_list_tabpages() == tab_count, 'expected no tab creation')
  assert(#vim.api.nvim_list_bufs() == buffer_count, 'expected no buffer creation')
end

M.display_side_by_side_should_reuse_and_recover_owned_review_resources_when_externally_closed = function()
  local invoking_tab = vim.api.nvim_get_current_tabpage()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('first.txt') }, 'vertical')
  local first_tab = review_ui.side_by_side.tabpage
  local first_window = review_ui.side_by_side.main_window
  local first_buffer = helpers.main_buffer(review_ui)
  assert(first_window ~= nil, 'expected initial main window')

  review_ui:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('second.txt') }, 'vertical')
  assert(review_ui.side_by_side.tabpage == first_tab, 'expected review tab reuse')
  assert(helpers.main_buffer(review_ui) == first_buffer, 'expected snapshot buffer reuse')
  vim.cmd('vsplit')
  vim.api.nvim_win_close(first_window, true)
  review_ui:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('third.txt') }, 'vertical')
  assert(vim.api.nvim_win_is_valid(review_ui.side_by_side.main_window), 'expected recovered main window')
  vim.cmd('tabclose!')
  vim.api.nvim_set_current_tabpage(invoking_tab)
  review_ui:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('fourth.txt') }, 'vertical')
  assert(review_ui.side_by_side.tabpage ~= first_tab, 'expected recovered review tab')
  assert(vim.api.nvim_get_current_win() == review_ui.side_by_side.main_window, 'expected main focus')
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_isolate_multiple_instance_namespaces_and_scratch_names = function()
  local first_ui = ui.get_ui()
  local second_ui = ui.get_ui()
  first_ui:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('first.txt') }, 'vertical')
  second_ui:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('second.txt') }, 'vertical')
  local first_name = vim.api.nvim_buf_get_name(helpers.main_buffer(first_ui))
  local second_name = vim.api.nvim_buf_get_name(helpers.main_buffer(second_ui))

  assert(first_ui.side_by_side.namespace ~= second_ui.side_by_side.namespace, 'expected distinct namespaces')
  assert(first_name ~= second_name, 'expected distinct scratch names')
  assert(first_name:match('^diffreview://%d+/main%-snapshot$') ~= nil, 'expected stable scratch name')
  local owner_variable = 'diffreview_side_by_side_owner'
  local first_owner = first_ui.side_by_side.instance_id
  local second_owner = second_ui.side_by_side.instance_id
  assert(
    vim.api.nvim_tabpage_get_var(first_ui.side_by_side.tabpage, owner_variable) == first_owner,
    'expected first tab ownership'
  )
  assert(
    vim.api.nvim_win_get_var(first_ui.side_by_side.main_window, owner_variable) == first_owner,
    'expected first window ownership'
  )
  assert(
    vim.api.nvim_buf_get_var(helpers.main_buffer(first_ui), owner_variable) == first_owner,
    'expected first scratch ownership'
  )
  assert(
    vim.api.nvim_tabpage_get_var(second_ui.side_by_side.tabpage, owner_variable) == second_owner,
    'expected second tab ownership'
  )
  assert(
    vim.api.nvim_win_get_var(second_ui.side_by_side.main_window, owner_variable) == second_owner,
    'expected second window ownership'
  )
  assert(
    vim.api.nvim_buf_get_var(helpers.main_buffer(second_ui), owner_variable) == second_owner,
    'expected second scratch ownership'
  )
  assert(first_owner ~= second_owner, 'expected distinct ownership markers')
  helpers.cleanup(first_ui)
  helpers.cleanup(second_ui)
end

M.display_side_by_side_should_preserve_invoking_tab_windows_layout_and_options = function()
  local invoking_tab = vim.api.nvim_get_current_tabpage()
  local before = tab_state(invoking_tab)
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('file.txt') }, 'vertical')
  assert(vim.api.nvim_tabpage_is_valid(invoking_tab), 'expected invoking tab to remain valid')
  assert(vim.deep_equal(tab_state(invoking_tab), before), 'expected invoking tab state preservation')
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_preserve_snapshot_endofline_fileformat_and_filetype = function()
  local review_ui = ui.get_ui()
  for _, fileformat in ipairs({ 'unix', 'dos', 'mac' }) do
    local current = helpers.snapshot('script.sh', { '#!/bin/sh' })
    current.content.endofline = false
    current.content.fileformat = fileformat
    review_ui:display_diff_side_by_side({ operation = 'added', current = current }, 'vertical')
    local buffer = helpers.main_buffer(review_ui)
    assert(not vim.api.nvim_get_option_value('endofline', { buf = buffer }), 'expected no final newline')
    assert(vim.api.nvim_get_option_value('fileformat', { buf = buffer }) == fileformat, 'expected file format')
    assert(vim.api.nvim_get_option_value('filetype', { buf = buffer }) == 'sh', 'expected detected filetype')
  end
  helpers.cleanup(review_ui)
end

return M
