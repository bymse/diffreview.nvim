local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local assert_failure = require('helpers.diff_load_assertions').assert_failure
local M = {}

M.load_diffs_should_return_filesystem_errors_when_cwd_is_missing_or_not_a_directory = function()
  local missing_result = diffs.load_diffs({ cwd = vim.fn.tempname() })
  assert_failure(missing_result, 'filesystem')
  local file = vim.fn.tempname()
  assert(vim.fn.writefile({ 'not a directory' }, file) == 0, 'failed to create cwd file')
  local file_result = diffs.load_diffs({ cwd = file })
  vim.fn.delete(file)
  assert_failure(file_result, 'filesystem')
end

M.load_diffs_should_return_filesystem_error_when_cwd_is_unreadable = function()
  local directory = vim.fn.tempname()
  assert(vim.fn.mkdir(directory) == 1, 'failed to create unreadable cwd fixture')
  assert(vim.uv.fs_chmod(directory, 0), 'failed to make cwd fixture unreadable')
  local unreadable = not vim.uv.fs_access(directory, 'R')
  local result = diffs.load_diffs({ cwd = directory })
  assert(vim.uv.fs_chmod(directory, 493), 'failed to restore cwd fixture permissions')
  vim.fn.delete(directory, 'rf')
  if unreadable then
    assert_failure(result, 'filesystem')
  end
end

M.load_diffs_should_return_repository_error_when_cwd_is_not_a_worktree = function()
  local directory = '/tmp/diffreview-not-worktree-' .. tostring(vim.uv.hrtime())
  assert(vim.fn.mkdir(directory) == 1, 'failed to create non-repository directory')
  local result = diffs.load_diffs({ cwd = directory })
  vim.fn.delete(directory, 'rf')
  assert_failure(result, 'repository')
end

M.load_diffs_should_return_git_error_when_tracked_diff_command_fails = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    assert(vim.fn.writefile({ 'corrupted index' }, repo.cwd .. '/.git/index') == 0, 'failed to corrupt index fixture')

    local result = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert_failure(result, 'git')
    assert(result.error.detail ~= nil and result.error.detail ~= '', 'expected Git command diagnostic')
  end)
end

return M
