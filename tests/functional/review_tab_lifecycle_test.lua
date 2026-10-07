local diffreview = require('diffreview')
local functional_review = require('helpers.functional_review')
local states = require('helpers.git_states')

local M = {}

local function with_changed_repo(run)
  functional_review.with_review(function(repo)
    return { from = states.modify_file(repo, 'file.txt', 'unstaged') }
  end, run)
end

local function stopped_messages(before)
  local after = vim.api.nvim_exec2('messages', { output = true }).output
  local _, count = after:sub(#before + 1):gsub('Review stopped', '')
  return count
end

M.tab_should_open_focused_drawer_when_review_starts = function()
  with_changed_repo(function()
    functional_review.wait_for_list(1)
    assert(#vim.api.nvim_list_tabpages() == 2, 'expected one dedicated tab')
    assert(vim.api.nvim_get_current_tabpage() ~= vim.api.nvim_list_tabpages()[1], 'expected review tab focus')
    assert(vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].quickfix == 1, 'expected focused drawer')
  end)
end

M.tab_should_close_diff_tab_when_review_stops = function()
  with_changed_repo(function(repo)
    local id = functional_review.wait_for_list(1)
    local review_tab = vim.api.nvim_get_current_tabpage()
    functional_review.select_path(id, 'file.txt')
    functional_review.wait_for_two_sided_current(repo, 'file.txt', 'old file.txt', 'current file.txt')
    assert(vim.api.nvim_get_current_tabpage() == review_tab, 'expected selection in list tab')
    assert(#vim.api.nvim_tabpage_list_wins(review_tab) == 2, 'expected only diff panes')
    assert(#vim.api.nvim_list_tabpages() == 2, 'expected review tab with selection view')
    diffreview.stop()
    assert(#vim.api.nvim_list_tabpages() == 1, 'expected review tab to close after stop')
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      assert(vim.fn.getwininfo(window)[1].quickfix == 0, 'expected quickfix window to close')
    end
  end)
end

M.tab_should_close_other_tab_quickfix_window_when_review_list_is_displayed_on_stop = function()
  with_changed_repo(function()
    local id = functional_review.wait_for_list(1)
    local review_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('tabprevious')
    local user_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('copen')
    local user_window = vim.api.nvim_get_current_win()
    diffreview.stop()
    assert(not vim.api.nvim_tabpage_is_valid(review_tab), 'expected review tab closure')
    assert(vim.api.nvim_get_current_tabpage() == user_tab, 'expected user tab focus')
    assert(not vim.api.nvim_win_is_valid(user_window), 'expected review list window to close')
    assert(#vim.fn.getqflist({ id = id, items = 1 }).items == 0, 'expected cleared review list')
  end)
end

M.tab_should_create_replacement_when_review_stop_closes_last_tab = function()
  with_changed_repo(function()
    local id = functional_review.wait_for_list(1)
    local review_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('tabprevious')
    vim.cmd('tabclose!')
    assert(#vim.api.nvim_list_tabpages() == 1, 'expected sole review tab')
    diffreview.stop()
    assert(#vim.api.nvim_list_tabpages() == 1, 'expected replacement tab')
    assert(not vim.api.nvim_tabpage_is_valid(review_tab), 'expected review tab closed')
    assert(#vim.fn.getqflist({ id = id, items = 1 }).items == 0, 'expected review list cleared')
  end)
end

M.tab_should_close_review_list_windows_and_preserve_tab_focus_when_selected_from_other_tab = function()
  with_changed_repo(function(repo)
    local id = functional_review.wait_for_list(1)
    local review_tab = vim.api.nvim_get_current_tabpage()
    local review_drawer = vim.api.nvim_get_current_win()
    vim.cmd('tabprevious')
    local user_tab = vim.api.nvim_get_current_tabpage()
    local user_window = vim.api.nvim_get_current_win()
    vim.cmd('copen')
    local user_drawer = vim.api.nvim_get_current_win()
    functional_review.select_path(id, 'file.txt')
    functional_review.wait_for_two_sided_current(
      repo,
      'file.txt',
      'old file.txt',
      'current file.txt',
      nil,
      nil,
      review_tab
    )
    assert(vim.api.nvim_get_current_tabpage() == user_tab, 'expected user tab focus after late display')
    assert(vim.api.nvim_get_current_win() == user_window, 'expected user tab window focus')
    assert(not vim.api.nvim_win_is_valid(user_drawer), 'expected review list window to close')
    assert(not vim.api.nvim_win_is_valid(review_drawer), 'expected plugin drawer to close')
    assert(#vim.api.nvim_tabpage_list_wins(review_tab) == 2, 'expected two diff panes in review tab')
    diffreview.stop()
    assert(vim.api.nvim_win_is_valid(user_window), 'expected user tab window to survive stop')
  end)
end

M.tab_should_close_review_list_window_when_plugin_drawer_was_already_closed = function()
  with_changed_repo(function(repo)
    local id = functional_review.wait_for_list(1)
    local review_tab = vim.api.nvim_get_current_tabpage()
    local plugin_drawer = vim.api.nvim_get_current_win()
    vim.cmd('cclose')
    assert(not vim.api.nvim_win_is_valid(plugin_drawer), 'expected closed plugin drawer')
    vim.cmd('tabprevious')
    local user_tab = vim.api.nvim_get_current_tabpage()
    local user_window = vim.api.nvim_get_current_win()
    vim.cmd('copen')
    local user_drawer = vim.api.nvim_get_current_win()
    functional_review.select_path(id, 'file.txt')
    functional_review.wait_for_two_sided_current(
      repo,
      'file.txt',
      'old file.txt',
      'current file.txt',
      nil,
      nil,
      review_tab
    )
    assert(vim.api.nvim_get_current_tabpage() == user_tab, 'expected user tab focus')
    assert(vim.api.nvim_get_current_win() == user_window, 'expected user tab window focus')
    assert(not vim.api.nvim_win_is_valid(user_drawer), 'expected review list window closed')
    assert(#vim.api.nvim_tabpage_list_wins(review_tab) == 2, 'expected two diff panes')
    diffreview.stop()
    assert(vim.api.nvim_win_is_valid(user_window), 'expected user tab window to survive stop')
  end)
end

M.tab_should_stop_and_allow_restart_when_list_tab_is_closed = function()
  with_changed_repo(function(repo)
    local id = functional_review.wait_for_list(1)
    local tab = vim.api.nvim_get_current_tabpage()
    local before = vim.api.nvim_exec2('messages', { output = true }).output
    vim.cmd('tabclose!')
    assert(
      vim.wait(1000, function()
        return stopped_messages(before) == 1
      end),
      'expected one stop notification'
    )
    assert(not vim.api.nvim_tabpage_is_valid(tab), 'expected closed review tab')
    assert(#vim.fn.getqflist({ id = id, items = 1 }).items == 0, 'expected cleared review list')
    diffreview.start({ cwd = repo.cwd, from = 'HEAD' })
    local next_id = functional_review.wait_for_list(1)
    assert(next_id ~= id, 'expected new review list')
  end)
end

M.tab_should_stop_after_diff_and_ignore_unrelated_tab_closure = function()
  with_changed_repo(function(repo)
    local id = functional_review.wait_for_list(1)
    local tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('tabnew')
    vim.cmd('tabclose!')
    assert(vim.api.nvim_tabpage_is_valid(tab), 'expected review tab preserved')
    functional_review.select_path(id, 'file.txt')
    functional_review.wait_for_two_sided_current(repo, 'file.txt', 'old file.txt', 'current file.txt')
    local before = vim.api.nvim_exec2('messages', { output = true }).output
    vim.cmd('tabclose!')
    assert(
      vim.wait(1000, function()
        return stopped_messages(before) == 1
      end),
      'expected one stop notification after diff'
    )
    assert(#vim.fn.getqflist({ id = id, items = 1 }).items == 0, 'expected list cleared')
    diffreview.start({ cwd = repo.cwd, from = 'HEAD' })
    functional_review.wait_for_list(1)
  end)
end

M.tab_should_discard_pending_selection_when_closed_after_enter = function()
  with_changed_repo(function(repo)
    local id = functional_review.wait_for_list(1)
    local tab = vim.api.nvim_get_current_tabpage()
    local drawer = vim.api.nvim_get_current_win()
    local before = vim.api.nvim_exec2('messages', { output = true }).output
    local list = vim.fn.getqflist({ id = id, items = 1, qfbufnr = 1 })
    assert(list.items[1].text:find('file.txt', 1, true), 'expected selectable Git file')
    local mapped = false
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(list.qfbufnr, 'n')) do
      if mapping.lhs == '<CR>' and mapping.desc == 'Open selected Diff Review file' then
        mapped = true
      end
    end
    assert(mapped, 'expected real Enter selection binding in the review drawer')
    functional_review.select_path(id, 'file.txt')
    assert(vim.api.nvim_get_current_win() == drawer, 'expected Enter to return with drawer focused')
    assert(vim.api.nvim_win_is_valid(drawer), 'expected Enter to leave drawer open during asynchronous Git load')
    assert(vim.fn.getqflist({ id = 0 }).id == id, 'expected selection to retain active review list')
    vim.cmd('tabclose!')
    assert(
      vim.wait(1000, function()
        return stopped_messages(before) == 1
      end),
      'expected review to stop after pending selection'
    )
    assert(not vim.wait(2000, function()
      if vim.api.nvim_tabpage_is_valid(tab) or #vim.api.nvim_list_tabpages() > 1 then
        return true
      end
      for _, window in ipairs(vim.api.nvim_list_wins()) do
        if
          vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)) == repo.cwd .. '/file.txt' or vim.wo[window].diff
        then
          return true
        end
      end
      return false
    end), 'expected no late diff view or review tab')
    assert(#vim.fn.getqflist({ id = id, items = 1 }).items == 0, 'expected cleared list')
    diffreview.start({ cwd = repo.cwd, from = 'HEAD' })
    functional_review.wait_for_list(1)
  end)
end

return M
