local async_operation = require('diffreview.async_operation')
local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local assert_failure = require('helpers.diff_load_assertions').assert_failure
local M = {}

M.load_diffs_should_return_canceled_when_operation_is_already_canceled = function()
  local operation = async_operation.new()
  async_operation.cancel(operation)
  local result = diffs.load_diffs({ cwd = vim.fn.tempname() }, operation)
  assert(not result.ok and result.error.kind == 'canceled', 'expected canceled load result')
  assert(result.error.detail == nil, 'expected canceled load without diagnostic detail')
end

M.load_diffs_should_return_canceled_when_operation_is_canceled_after_start = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local operation = async_operation.new()
    local result
    local worker = coroutine.create(function()
      result = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' }, operation)
    end)

    local started, err = coroutine.resume(worker)
    assert(started, err)
    assert(coroutine.status(worker) == 'suspended', 'expected load to be in progress')
    async_operation.cancel(operation)
    assert(
      vim.wait(1000, function()
        return coroutine.status(worker) == 'dead'
      end),
      'expected load to finish after cancellation'
    )
    assert_failure(result, 'canceled')
  end)
end

return M
