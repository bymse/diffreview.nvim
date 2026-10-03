local diffreview = require('diffreview')
local git_repo = require('helpers.git_repo')
local M = {}

local function ensure_setup()
  if vim.fn.exists(':ReviewStart') == 0 then
    diffreview.setup({})
  end
end

---@param run fun(base: string, head: string)
local function with_command_repo(run)
  ensure_setup()
  git_repo.with_repo(function(repo)
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

    local original_cwd = vim.fn.getcwd()
    local ok, err = xpcall(function()
      vim.api.nvim_set_current_dir(repo.cwd)
      run(base, head)
    end, debug.traceback)
    pcall(function()
      vim.cmd('ReviewStop')
    end)
    vim.api.nvim_set_current_dir(original_cwd)
    assert(ok, err)
  end)
end

---@return integer
local function wait_for_review_quickfix()
  assert(
    vim.wait(1000, function()
      local quickfix = vim.fn.getqflist({ id = 0, title = 0, items = 1, qfbufnr = 1 })
      if quickfix.title ~= 'Diff Review' or #quickfix.items ~= 1 or quickfix.qfbufnr == 0 then
        return false
      end
      return vim.deep_equal(vim.api.nvim_buf_get_lines(quickfix.qfbufnr, 0, -1, false), {
        '[ ] -1/+1 file.txt',
      })
    end),
    'expected review quickfix to display changed file'
  )
  return vim.fn.getqflist({ id = 0 }).id
end

M.user_commands_should_register_after_setup = function()
  assert(vim.fn.exists(':ReviewStart') == 0, 'expected ReviewStart to require setup')
  assert(vim.fn.exists(':ReviewStop') == 0, 'expected ReviewStop to require setup')
  ensure_setup()
  assert(vim.fn.exists(':ReviewStart') == 2, 'expected ReviewStart command')
  assert(vim.fn.exists(':ReviewStop') == 2, 'expected ReviewStop command')
  assert(not pcall(diffreview.setup, {}), 'expected setup to remain single-use')
end

M.user_commands_should_reject_invalid_start_options = function()
  ensure_setup()
  local before = vim.api.nvim_exec2('messages', { output = true }).output
  diffreview.start({ to = 'HEAD' })
  local after = vim.api.nvim_exec2('messages', { output = true }).output
  assert(after ~= before and after:find('Invalid review start options', 1, true), 'expected start validation message')
end

M.user_commands_should_start_review_when_no_arguments_are_given = function()
  with_command_repo(function()
    vim.cmd('ReviewStart')
    wait_for_review_quickfix()
  end)
end

M.user_commands_should_start_review_when_one_argument_is_given = function()
  with_command_repo(function()
    vim.cmd('ReviewStart HEAD')
    wait_for_review_quickfix()
  end)
end

M.user_commands_should_start_review_when_two_arguments_are_given = function()
  with_command_repo(function(base, head)
    vim.cmd('ReviewStart ' .. base .. ' ' .. head)
    wait_for_review_quickfix()
  end)
end

M.user_commands_should_stop_review_when_active = function()
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

M.user_commands_should_stop_preserve_active_review_when_arity_is_invalid = function()
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
