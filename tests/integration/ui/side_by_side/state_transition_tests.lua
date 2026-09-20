local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')

local M = {}

local function modified_diff()
  return {
    operation = 'modified',
    old = helpers.snapshot('file.txt', { 'old' }),
    current = helpers.snapshot('file.txt', { 'current' }),
    content_changed = true,
  }
end

M.display_side_by_side_should_restore_captured_window_options_when_leaving_two_window_mode = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  local main = review_ui.side_by_side.main_window
  local companion = review_ui.side_by_side.companion_window
  assert(companion ~= nil, 'expected companion window')
  ---@cast companion integer
  local expected = {}
  for _, option in ipairs({
    'diff',
    'scrollbind',
    'cursorbind',
    'wrap',
    'foldmethod',
    'foldcolumn',
    'foldenable',
    'foldlevel',
  }) do
    expected[option] = review_ui.side_by_side.native_diff.window_options[main][option]
  end
  local diffopt = vim.o.diffopt
  review_ui:display_diff_side_by_side({
    operation = 'added',
    current = helpers.snapshot('added.txt', { 'added' }),
  }, 'vertical')
  assert(not vim.api.nvim_win_is_valid(companion), 'expected companion cleanup')
  for option, value in pairs(expected) do
    assert(vim.api.nvim_get_option_value(option, { win = main }) == value, 'expected restored ' .. option)
  end
  assert(vim.o.diffopt == diffopt, 'expected diffopt preservation')
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_reuse_owned_two_window_handles_when_layout_is_unchanged = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  local state = review_ui.side_by_side
  local tab = state.tabpage
  local main = state.main_window
  local companion = state.companion_window
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(state.tabpage == tab, 'expected review tab reuse')
  assert(state.main_window == main, 'expected main window reuse')
  assert(state.companion_window == companion, 'expected companion window reuse')
  assert(#vim.api.nvim_tabpage_list_wins(state.tabpage) == 2, 'expected exactly two owned windows')
  assert(vim.api.nvim_get_current_win() == main, 'expected current focus')
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_recreate_lost_companion_and_tab_on_next_display = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  vim.api.nvim_win_close(review_ui.side_by_side.companion_window, true)
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(vim.api.nvim_win_is_valid(review_ui.side_by_side.companion_window), 'expected recreated companion')
  local tab = review_ui.side_by_side.tabpage
  assert(tab ~= nil, 'expected review tab')
  ---@cast tab integer
  vim.api.nvim_set_current_tabpage(tab)
  vim.cmd('tabclose!')
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(vim.api.nvim_tabpage_is_valid(review_ui.side_by_side.tabpage), 'expected recreated tab')
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_recreate_lost_main_window_and_scratch_buffer_on_next_display = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  local old_scratch = review_ui.side_by_side.companion_snapshot_buffer
  assert(old_scratch ~= nil, 'expected companion scratch buffer')
  ---@cast old_scratch integer
  vim.api.nvim_buf_delete(old_scratch, { force = true })
  vim.api.nvim_win_close(review_ui.side_by_side.main_window, true)
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(vim.api.nvim_win_is_valid(review_ui.side_by_side.main_window), 'expected recreated main window')
  assert(review_ui.side_by_side.companion_snapshot_buffer ~= old_scratch, 'expected recreated scratch buffer')
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_clear_diff_decorations_when_rendering_information = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  local old_buffer = vim.api.nvim_win_get_buf(review_ui.side_by_side.companion_window)
  review_ui:display_diff_side_by_side({
    operation = 'modified',
    old = helpers.snapshot('file.txt', { 'same' }, '100644'),
    current = helpers.snapshot('file.txt', { 'same' }, '100755'),
    content_changed = false,
  }, 'vertical')
  assert(
    vim.api.nvim_buf_get_extmarks(old_buffer, review_ui.side_by_side.namespace, 0, -1, {})[1] == nil,
    'expected cleared extmarks'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_reconcile_layout_and_one_window_transitions = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  local tab = review_ui.side_by_side.tabpage
  assert(tab ~= nil, 'expected review tab')
  ---@cast tab integer
  local vertical_companion = review_ui.side_by_side.companion_window
  review_ui:display_diff_side_by_side(modified_diff(), 'horizontal')
  assert(review_ui.side_by_side.tabpage == tab, 'expected tab preservation across layout')
  assert(review_ui.side_by_side.companion_window ~= vertical_companion, 'expected companion replacement for layout')
  assert(#vim.api.nvim_tabpage_list_wins(tab) == 2, 'expected two windows after layout change')
  review_ui:display_diff_side_by_side(
    { operation = 'added', current = helpers.snapshot('added.txt', { 'added' }) },
    'vertical'
  )
  assert(#vim.api.nvim_tabpage_list_wins(tab) == 1, 'expected decorated one-window transition')
  review_ui:display_diff_side_by_side({
    operation = 'modified',
    old = helpers.snapshot('file.txt', { 'same' }, '100644'),
    current = helpers.snapshot('file.txt', { 'same' }, '100755'),
    content_changed = false,
  }, 'vertical')
  assert(#vim.api.nvim_tabpage_list_wins(tab) == 1, 'expected information one-window transition')
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(#vim.api.nvim_tabpage_list_wins(tab) == 2, 'expected two-window recovery')
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_preserve_module_owned_scrollopt_until_last_instance_leaves = function()
  local initial = vim.o.scrollopt
  vim.o.scrollopt = 'ver,jump'
  local first = ui.get_ui()
  local second = ui.get_ui()
  first:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(vim.o.scrollopt == 'ver,jump,hor', 'expected module hor')
  vim.o.scrollopt = 'ver,jump'
  first:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(vim.tbl_contains(vim.split(vim.o.scrollopt, ',', { plain = true }), 'hor'), 'expected owned hor re-add')
  second:display_diff_side_by_side(modified_diff(), 'vertical')
  first:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('first.txt') }, 'vertical')
  assert(vim.tbl_contains(vim.split(vim.o.scrollopt, ',', { plain = true }), 'hor'), 'expected hor while second active')
  second:display_diff_side_by_side({ operation = 'added', current = helpers.snapshot('second.txt') }, 'vertical')
  assert(vim.o.scrollopt == 'ver,jump', 'expected owned hor removal')
  helpers.cleanup(first)
  helpers.cleanup(second)
  vim.o.scrollopt = initial
end

M.display_side_by_side_should_not_readd_preexisting_scrollopt_hor_after_external_removal = function()
  local initial = vim.o.scrollopt
  vim.o.scrollopt = 'ver,hor'
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  vim.o.scrollopt = 'ver'
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(vim.o.scrollopt == 'ver', 'expected pre-existing hor to remain externally removed')
  helpers.cleanup(review_ui)
  vim.o.scrollopt = initial
end

M.display_side_by_side_should_preserve_preexisting_scrollopt_hor_across_two_window_transitions = function()
  local initial = vim.o.scrollopt
  vim.o.scrollopt = 'ver,jump,hor'
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(vim.o.scrollopt == 'ver,jump,hor', 'expected pre-existing hor after two-window rendering')
  review_ui:display_diff_side_by_side(
    { operation = 'added', current = helpers.snapshot('added.txt', { 'added' }) },
    'vertical'
  )
  assert(vim.o.scrollopt == 'ver,jump,hor', 'expected pre-existing hor after one-window transition')
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  review_ui:display_diff_side_by_side(modified_diff(), 'horizontal')
  assert(vim.o.scrollopt == 'ver,jump,hor', 'expected pre-existing hor after layout change')
  vim.api.nvim_win_close(review_ui.side_by_side.companion_window, true)
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(vim.o.scrollopt == 'ver,jump,hor', 'expected pre-existing hor after companion-loss recovery')
  helpers.cleanup(review_ui)
  vim.o.scrollopt = initial
end

M.cleanup_should_release_owned_resources_and_restore_native_diff_when_active = function()
  local initial_scrollopt = vim.o.scrollopt
  vim.o.scrollopt = 'ver,jump'
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'error',
    attempted_operation = 'modified',
    path = 'error.txt',
    message = 'load failed',
  }, 'vertical')
  local information_buffer = review_ui.side_by_side.information_buffer
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  local state = review_ui.side_by_side
  local tabpage = state.tabpage
  local main_window = state.main_window
  local companion_window = state.companion_window
  local main_buffer = state.main_snapshot_buffer
  local companion_buffer = state.companion_snapshot_buffer
  assert(tabpage ~= nil, 'expected review tab')
  assert(main_window ~= nil, 'expected main window')
  assert(companion_window ~= nil, 'expected companion window')
  assert(information_buffer ~= nil, 'expected information buffer')
  assert(main_buffer ~= nil, 'expected main snapshot buffer')
  assert(companion_buffer ~= nil, 'expected companion snapshot buffer')
  ---@cast tabpage integer
  ---@cast main_window integer
  ---@cast companion_window integer
  ---@cast information_buffer integer
  ---@cast main_buffer integer
  ---@cast companion_buffer integer
  assert(state.native_diff.active, 'expected active native diff')
  assert(vim.o.scrollopt == 'ver,jump,hor', 'expected owned horizontal scrolling')

  review_ui:cleanup()

  assert(not vim.api.nvim_tabpage_is_valid(tabpage), 'expected review tab deletion')
  assert(not vim.api.nvim_win_is_valid(main_window), 'expected main window deletion')
  assert(not vim.api.nvim_win_is_valid(companion_window), 'expected companion window deletion')
  for _, buffer in ipairs({ information_buffer, main_buffer, companion_buffer }) do
    assert(not vim.api.nvim_buf_is_valid(buffer), 'expected owned scratch buffer deletion')
  end
  assert(not state.native_diff.active, 'expected released native diff')
  assert(next(state.native_diff.window_options) == nil, 'expected cleared native diff options')
  assert(vim.o.scrollopt == 'ver,jump', 'expected owned horizontal scrolling removal')
  for _, field in ipairs({
    'tabpage',
    'main_window',
    'companion_window',
    'main_snapshot_buffer',
    'companion_snapshot_buffer',
    'information_buffer',
    'decorated_buffer',
    'active_layout',
  }) do
    assert(state[field] == nil, 'expected cleared ' .. field)
  end
  review_ui:cleanup()
  vim.o.scrollopt = initial_scrollopt
end

M.cleanup_should_preserve_borrowed_path_buffer_when_it_is_decorated = function()
  local path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile({ 'borrowed' }, path)
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({ operation = 'added', current = helpers.path(path) }, 'vertical')
  local buffer = helpers.main_buffer(review_ui)
  local namespace = review_ui.side_by_side.namespace
  assert(#vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}) == 1, 'expected decoration')

  review_ui:cleanup()

  assert(vim.api.nvim_buf_is_valid(buffer), 'expected borrowed path buffer preservation')
  assert(#vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}) == 0, 'expected decoration cleanup')
  vim.api.nvim_buf_delete(buffer, { force = true })
  vim.fn.delete(path)
end

local function unrelated_tab_state(tabpage)
  local state = {}
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    state[window] = {
      buffer = vim.api.nvim_win_get_buf(window),
      position = { vim.api.nvim_win_get_position(window) },
      diff = vim.wo[window].diff,
      scrollbind = vim.wo[window].scrollbind,
      cursorbind = vim.wo[window].cursorbind,
      wrap = vim.wo[window].wrap,
      foldmethod = vim.wo[window].foldmethod,
      foldcolumn = vim.wo[window].foldcolumn,
      foldenable = vim.wo[window].foldenable,
      foldlevel = vim.wo[window].foldlevel,
    }
  end
  return state
end

M.display_side_by_side_should_preserve_unrelated_user_tab_across_two_window_transitions = function()
  local initial = vim.o.scrollopt
  local left_path = vim.fn.tempname() .. '-left.txt'
  local right_path = vim.fn.tempname() .. '-right.txt'
  vim.fn.writefile({ 'left one', 'left two' }, left_path)
  vim.fn.writefile({ 'right one', 'right two' }, right_path)
  vim.cmd('tabnew')
  local user_tab = vim.api.nvim_get_current_tabpage()
  local left_window = vim.api.nvim_get_current_win()
  local right_window = vim.api.nvim_open_win(0, false, { split = 'right' })
  vim.api.nvim_win_call(left_window, function()
    vim.cmd('edit ' .. vim.fn.fnameescape(left_path))
  end)
  vim.api.nvim_win_call(right_window, function()
    vim.cmd('edit ' .. vim.fn.fnameescape(right_path))
  end)
  for _, window in ipairs({ left_window, right_window }) do
    vim.api.nvim_win_call(window, function()
      vim.cmd('diffthis')
    end)
  end
  local expected = unrelated_tab_state(user_tab)
  assert(expected[left_window].diff and expected[right_window].diff, 'expected user diff group')

  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(#vim.api.nvim_tabpage_list_wins(review_ui.side_by_side.tabpage) == 2, 'expected review two-window rendering')
  assert(
    vim.deep_equal(unrelated_tab_state(user_tab), expected),
    'expected unchanged user tab after two-window rendering'
  )
  review_ui:display_diff_side_by_side(
    { operation = 'added', current = helpers.snapshot('added.txt', { 'added' }) },
    'vertical'
  )
  assert(
    vim.deep_equal(unrelated_tab_state(user_tab), expected),
    'expected unchanged user tab after leaving two-window mode'
  )
  review_ui:display_diff_side_by_side(modified_diff(), 'horizontal')
  assert(
    vim.deep_equal(unrelated_tab_state(user_tab), expected),
    'expected unchanged user tab after review layout change'
  )
  local review_tab = review_ui.side_by_side.tabpage
  assert(review_tab ~= nil, 'expected review tab')
  ---@cast review_tab integer
  vim.api.nvim_set_current_tabpage(review_tab)
  vim.cmd('tabclose!')
  review_ui:display_diff_side_by_side(modified_diff(), 'vertical')
  assert(
    vim.deep_equal(unrelated_tab_state(user_tab), expected),
    'expected unchanged user tab after review-tab loss recovery'
  )

  helpers.cleanup(review_ui)
  vim.api.nvim_set_current_tabpage(user_tab)
  vim.cmd('tabclose!')
  for _, path in ipairs({ left_path, right_path }) do
    vim.api.nvim_buf_delete(vim.fn.bufnr(path), { force = true })
    vim.fn.delete(path)
  end
  vim.o.scrollopt = initial
end

return M
