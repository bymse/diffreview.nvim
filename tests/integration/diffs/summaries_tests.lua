local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local file_by_id = require('helpers.diff_load_assertions').file_by_id
local M = {}

---@param path string
---@param run fun(repo: TestGitRepo, base: string)
local function with_committed_file(path, run)
  git_repo.with_repo(function(repo)
    repo:write_file(path, { 'before' })
    repo:add(path)
    repo:commit('base')
    run(repo, repo:current_sha())
  end)
end

M.load_diffs_should_use_stored_identity_when_git_reports_a_deleted_file = function()
  with_committed_file('deleted.txt', function(repo, base)
    repo:run_git({ 'rm', '--quiet', 'deleted.txt' })

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    assert(file_by_id(loaded, 'stored:deleted.txt').display_path == 'deleted.txt', 'expected deleted file path')
  end)
end

M.load_diffs_should_use_stored_identity_when_git_reports_a_modified_file = function()
  with_committed_file('modified.txt', function(repo, base)
    repo:write_file('modified.txt', { 'after' })

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    assert(file_by_id(loaded, 'stored:modified.txt').display_path == 'modified.txt', 'expected modified file path')
  end)
end

M.load_diffs_should_use_stored_source_identity_when_git_reports_a_rename = function()
  with_committed_file('renamed.txt', function(repo, base)
    repo:run_git({ 'mv', 'renamed.txt', 'destination.txt' })

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    assert(
      file_by_id(loaded, 'stored:renamed.txt').display_path == 'destination.txt',
      'expected rename source identity'
    )
  end)
end

M.load_diffs_should_use_stored_identity_when_git_reports_a_type_change = function()
  with_committed_file('type.txt', function(repo, base)
    assert(vim.fn.delete(repo.cwd .. '/type.txt') == 0, 'failed to remove type fixture file')
    assert(vim.uv.fs_symlink('target.txt', repo.cwd .. '/type.txt'), 'failed to create type fixture symlink')
    repo:add('type.txt')

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'stored:type.txt')
    assert(repo:run_git({ 'diff', '--name-status', base, '--' }):match('T\ttype.txt'), 'expected type-change fixture')
  end)
end

M.load_diffs_should_use_new_identity_when_git_reports_an_added_file = function()
  with_committed_file('existing.txt', function(repo, base)
    repo:write_file('added.txt', { 'added' })
    repo:add('added.txt')

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'new:added.txt')
  end)
end

M.load_diffs_should_use_new_identity_when_git_reports_a_copy = function()
  git_repo.with_repo(function(repo)
    repo:write_file('source.txt', { 'copy source', 'second line' })
    repo:add('source.txt')
    repo:commit('base')
    local base = repo:current_sha()
    repo:write_file('source.txt', { 'source changed', 'second line' })
    repo:write_file('copied.txt', { 'copy source', 'second line' })
    repo:add('source.txt')
    repo:add('copied.txt')

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'new:copied.txt')
    assert(
      repo:run_git({ 'diff', '--name-status', '-C', base, '--' }):match('C%d+\tsource.txt\tcopied.txt'),
      'expected copy fixture'
    )
  end)
end

M.load_diffs_should_use_stored_identity_when_git_reports_an_unmerged_file_with_baseline_content = function()
  git_repo.with_repo(function(repo)
    repo:write_file('conflict.txt', { 'base' })
    repo:add('conflict.txt')
    repo:commit('base')
    local base = repo:current_sha()
    local main_branch = repo:run_git({ 'branch', '--show-current' })
    repo:branch('other')
    repo:write_file('conflict.txt', { 'main' })
    repo:add('conflict.txt')
    repo:commit('main')
    repo:run_git({ 'checkout', '--quiet', 'other' })
    repo:write_file('conflict.txt', { 'other' })
    repo:add('conflict.txt')
    repo:commit('other')
    repo:run_git({ 'checkout', '--quiet', main_branch })
    local merge_result = vim.system({ 'git', 'merge', '--no-commit', 'other' }, { cwd = repo.cwd, text = true }):wait()
    assert(merge_result.code ~= 0, 'expected merge conflict')

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'stored:conflict.txt')
  end)
end

M.load_diffs_should_use_new_identity_when_git_reports_an_unmerged_file_without_baseline_content = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local base = repo:current_sha()
    local main_branch = repo:run_git({ 'branch', '--show-current' })
    repo:branch('other')
    repo:write_file('added-by-both.txt', { 'main' })
    repo:add('added-by-both.txt')
    repo:commit('main adds file')
    repo:run_git({ 'checkout', '--quiet', 'other' })
    repo:write_file('added-by-both.txt', { 'other' })
    repo:add('added-by-both.txt')
    repo:commit('other adds file')
    repo:run_git({ 'checkout', '--quiet', main_branch })
    local merge_result = vim.system({ 'git', 'merge', '--no-commit', 'other' }, { cwd = repo.cwd, text = true }):wait()
    assert(merge_result.code ~= 0, 'expected add/add merge conflict')

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'new:added-by-both.txt')
  end)
end

M.load_diffs_should_summarize_binary_untracked_files_with_zero_line_counts = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local write_result = vim.system({ 'sh', '-c', 'printf "\\000\\001" > binary.bin' }, { cwd = repo.cwd }):wait()
    assert(write_result.code == 0, 'failed to write binary fixture')

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    local binary = file_by_id(loaded, 'new:binary.bin')
    assert(binary.added_lines == 0 and binary.removed_lines == 0, 'expected format-safe binary counts')
  end)
end

return M
