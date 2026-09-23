local git = require('diffreview.diffs.git')
local git_repo = require('helpers.git_repo')
local M = {}

M.untracked_file_stats_should_return_added_lines_when_file_is_text = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('untracked.txt', { 'first', 'second' })

    local result, added, removed, binary = git.get_repo(test_repo.cwd):untracked_file_stats('untracked.txt')

    assert(result.ok, 'expected untracked stats to succeed: ' .. (result.error or 'unknown error'))
    assert(added == 2, 'expected two added lines')
    assert(removed == 0, 'expected no removed lines')
    assert(binary == false, 'expected text file')
  end)
end

M.untracked_file_stats_should_identify_binary_file = function()
  git_repo.with_repo(function(test_repo)
    local write_result = vim.system({ 'sh', '-c', 'printf "\\000\\001" > binary.bin' }, { cwd = test_repo.cwd }):wait()
    assert(write_result.code == 0, 'failed to write binary fixture')

    local result, added, removed, binary = git.get_repo(test_repo.cwd):untracked_file_stats('binary.bin')

    assert(result.ok, 'expected untracked stats to succeed: ' .. (result.error or 'unknown error'))
    assert(added == 0 and removed == 0, 'expected binary-safe line counts')
    assert(binary == true, 'expected binary file')
  end)
end

M.untracked_file_stats_should_return_error_when_file_does_not_exist = function()
  git_repo.with_repo(function(test_repo)
    local result, added, removed, binary = git.get_repo(test_repo.cwd):untracked_file_stats('missing.txt')

    assert(not result.ok, 'expected untracked stats to fail')
    assert(result.error ~= nil and result.error ~= '', 'expected untracked stats error details')
    assert(added == nil and removed == nil and binary == nil, 'expected no file stats')
  end)
end

return M
