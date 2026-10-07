local git_repo = require('helpers.git_repo')
local review = require('diffreview.review')

local M = {}
local config = { layout = 'horizontal', view = 'side_by_side' }

---@return string
local function message_history()
  return vim.api.nvim_exec2('messages', { output = true }).output
end

---@param before string
local function wait_for_notification(before)
  assert(
    vim.wait(1000, function()
      return message_history() ~= before
    end),
    'expected review notification'
  )
end

---@param path string
---@return integer
local function wait_for_review_file(path)
  assert(
    vim.wait(1000, function()
      local quickfix = vim.fn.getqflist({ id = 0, title = 0, items = 1 })
      return quickfix.title == 'Diff Review'
        and #quickfix.items == 1
        and quickfix.items[1].text:find(path, 1, true) ~= nil
    end),
    'expected review quickfix to display ' .. path
  )
  return vim.fn.getqflist({ id = 0 }).id
end

---@param run fun(repo: TestGitRepo, session: ReviewSession)
local function with_review_repo(run)
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local session = review.new(config)
    local ok, err = xpcall(function()
      run(repo, session)
    end, debug.traceback)
    session:stop()
    vim.cmd('silent! cclose')
    assert(ok, err)
  end)
end

M.start_should_display_real_quickfix_and_clear_it_when_stopped = function()
  with_review_repo(function(repo, session)
    repo:write_file('tracked.txt', { 'changed' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    local review_id = wait_for_review_file('tracked.txt')
    session:stop()
    assert(#vim.fn.getqflist({ id = review_id, items = 1 }).items == 0, 'expected review list cleanup')
  end)
end

M.start_should_use_current_directory_when_cwd_is_omitted = function()
  with_review_repo(function(repo, session)
    repo:write_file('tracked.txt', { 'changed' })
    local original_cwd = vim.fn.getcwd()
    local ok, err = xpcall(function()
      vim.api.nvim_set_current_dir(repo.cwd)
      session:start({ from = 'HEAD' })
      wait_for_review_file('tracked.txt')
    end, debug.traceback)
    vim.api.nvim_set_current_dir(original_cwd)
    assert(ok, err)
  end)
end

M.start_should_preserve_active_review_when_another_start_is_requested = function()
  with_review_repo(function(repo, session)
    repo:write_file('tracked.txt', { 'changed' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    local review_id = wait_for_review_file('tracked.txt')

    session:start({ cwd = repo.cwd, from = 'HEAD' })

    local current = vim.fn.getqflist({ id = 0, items = 1 })
    assert(current.id == review_id, 'expected existing review to remain selected')
    assert(#current.items == 1 and current.items[1].text:find('tracked.txt', 1, true), 'expected review contents')
    session:stop()
    assert(#vim.fn.getqflist({ id = review_id, items = 1 }).items == 0, 'expected active review to remain stoppable')
  end)
end

M.start_should_allow_a_new_review_after_an_empty_comparison = function()
  with_review_repo(function(repo, session)
    local messages_before = message_history()
    local tab_count = #vim.api.nvim_list_tabpages()
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    wait_for_notification(messages_before)
    assert(message_history():find('No changes to review', 1, true), 'expected empty comparison notice')
    assert(#vim.api.nvim_list_tabpages() == tab_count, 'expected no tab for empty comparison')

    repo:write_file('tracked.txt', { 'changed' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    wait_for_review_file('tracked.txt')
  end)
end

M.stop_should_cancel_start_and_allow_a_new_review = function()
  with_review_repo(function(repo, session)
    repo:write_file('tracked.txt', { 'changed' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    session:stop()

    session:start({ cwd = repo.cwd, from = 'HEAD' })
    local review_id = wait_for_review_file('tracked.txt')
    session:stop()
    assert(#vim.fn.getqflist({ id = review_id, items = 1 }).items == 0, 'expected new review to remain stoppable')
  end)
end

M.start_should_allow_a_new_review_after_git_failure = function()
  with_review_repo(function(repo, session)
    local messages_before = message_history()
    local tab_count = #vim.api.nvim_list_tabpages()
    session:start({ cwd = vim.fn.tempname(), from = 'HEAD' })
    wait_for_notification(messages_before)
    assert(#vim.api.nvim_list_tabpages() == tab_count, 'expected no tab after Git failure')
    repo:write_file('tracked.txt', { 'changed' })

    session:start({ cwd = repo.cwd, from = 'HEAD' })
    wait_for_review_file('tracked.txt')
  end)
end

M.stop_should_close_review_list_window_in_other_tab_and_notify_once_when_called = function()
  with_review_repo(function(repo, session)
    repo:write_file('tracked.txt', { 'changed' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    local id = wait_for_review_file('tracked.txt')
    local review_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('tabprevious')
    local user_window = vim.api.nvim_get_current_win()
    vim.cmd('copen')
    local foreign_window = vim.api.nvim_get_current_win()
    local before = message_history()
    session:stop()
    assert(not vim.api.nvim_tabpage_is_valid(review_tab), 'expected closed review tab')
    assert(not vim.api.nvim_win_is_valid(foreign_window), 'expected review list window to close')
    assert(vim.api.nvim_get_current_win() == user_window, 'expected user window focus')
    assert(#vim.fn.getqflist({ id = id, items = 1 }).items == 0, 'expected owned list cleared')
    local _, count = message_history():sub(#before + 1):gsub('Review stopped', '')
    assert(count == 1, 'expected one stop event')
  end)
end

return M
