local diffreview = require('diffreview')
local functional_review = require('helpers.functional_review')

local M = {}

---@param run fun(repo: TestGitRepo, base: string, head: string)
local function with_command_repo(run)
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    local base = repo:current_sha()
    repo:set_default_branch()
    repo:write_file('file.txt', { 'committed' })
    repo:add('file.txt')
    repo:commit('changed')
    local head = repo:current_sha()
    repo:write_file('file.txt', { 'working' })
    return { from = base, to = head }
  end, function(repo, options)
    run(repo, assert(options.from), assert(options.to))
  end, false)
end

---@return integer
local function wait_for_review_quickfix()
  local id = functional_review.wait_for_list(1)
  assert(
    vim.wait(1000, function()
      local quickfix = vim.fn.getqflist({ id = id, qfbufnr = 1 })
      if quickfix.qfbufnr == 0 then
        return false
      end
      return vim.deep_equal(vim.api.nvim_buf_get_lines(quickfix.qfbufnr, 0, -1, false), {
        '[ ] -1/+1 file.txt',
      })
    end),
    'expected review quickfix to display changed file'
  )
  return id
end

M.plugin_should_register_commands_when_setup_is_called = function()
  assert(vim.fn.exists(':ReviewStart') == 0, 'expected ReviewStart to require setup')
  assert(vim.fn.exists(':ReviewStop') == 0, 'expected ReviewStop to require setup')
  assert(vim.fn.exists(':ReviewRefresh') == 0, 'expected ReviewRefresh to require setup')
  functional_review.ensure_setup()
  assert(vim.fn.exists(':ReviewStart') == 2, 'expected ReviewStart command')
  assert(vim.fn.exists(':ReviewStop') == 2, 'expected ReviewStop command')
  for _, name in ipairs({ 'ReviewFiles', 'ReviewRefresh', 'ReviewMarkViewed', 'ReviewMarkUnviewed' }) do
    assert(vim.fn.exists(':' .. name) == 2, 'expected ' .. name .. ' command')
  end
  assert(not pcall(diffreview.setup, {}), 'expected setup to remain single-use')
end

M.review_refresh_should_report_unavailable_when_review_is_inactive = function()
  functional_review.ensure_setup()
  local before = vim.api.nvim_exec2('messages', { output = true }).output
  pcall(function()
    vim.cmd('ReviewRefresh')
  end)
  local after = vim.api.nvim_exec2('messages', { output = true }).output
  assert(after ~= before and after:find('Review refresh unavailable', 1, true))
end

M.review_refresh_should_preserve_review_when_arity_is_invalid = function()
  with_command_repo(function()
    vim.cmd('ReviewStart HEAD')
    local id = wait_for_review_quickfix()
    assert(not pcall(function()
      vim.cmd('ReviewRefresh unexpected')
    end))
    assert(vim.fn.getqflist({ id = 0 }).id == id)
  end)
end

M.should_reject_invalid_start_options = function()
  functional_review.ensure_setup()
  local before = vim.api.nvim_exec2('messages', { output = true }).output
  diffreview.start({ to = 'HEAD' })
  local after = vim.api.nvim_exec2('messages', { output = true }).output
  assert(after ~= before and after:find('Invalid review start options', 1, true), 'expected start validation message')
end

M.should_start_review_when_no_arguments_are_given = function()
  with_command_repo(function()
    vim.cmd('ReviewStart')
    wait_for_review_quickfix()
  end)
end

M.should_start_review_when_one_argument_is_given = function()
  with_command_repo(function()
    vim.cmd('ReviewStart HEAD')
    wait_for_review_quickfix()
  end)
end

M.should_start_review_when_two_arguments_are_given = function()
  with_command_repo(function(repo, base, head)
    vim.cmd('ReviewStart ' .. base .. ' ' .. head)
    wait_for_review_quickfix()
  end)
end

M.should_stop_review_when_active = function()
  with_command_repo(function()
    vim.cmd('ReviewStart HEAD')
    local id = wait_for_review_quickfix()
    vim.cmd('ReviewStop')
    assert(#vim.fn.getqflist({ id = id, items = 1 }).items == 0, 'expected review quickfix to be cleared')
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      assert(vim.fn.getwininfo(window)[1].quickfix == 0, 'expected quickfix window to close')
    end
  end)
end

M.should_stop_preserve_active_review_when_arity_is_invalid = function()
  with_command_repo(function()
    vim.cmd('ReviewStart HEAD')
    local id = wait_for_review_quickfix()
    local stopped = pcall(function()
      vim.cmd('ReviewStop unexpected')
    end)
    assert(not stopped, 'expected native command arity error')
    assert(vim.fn.getqflist({ id = 0 }).id == id, 'expected invalid stop to preserve active review')
  end)
end

return M
