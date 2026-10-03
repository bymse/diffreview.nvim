local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local assertions = require('helpers.diff_load_assertions')
local assert_failure = assertions.assert_failure
local file_by_id = assertions.file_by_id

---@param loaded LoadedDiffs
---@param id string
local function assert_file_absent(loaded, id)
  for _, file in ipairs(loaded.files) do
    assert(file.id ~= id, 'expected comparison to exclude ' .. id)
  end
end
local M = {}

M.load_diffs_should_load_default_branch_baseline_through_working_state_when_origin_head_exists = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:set_default_branch()
    repo:write_file('tracked.txt', { 'working' })
    repo:write_file('untracked.txt', { 'one', 'two' })

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    assert(file_by_id(loaded, 'stored:tracked.txt').viewed == false, 'expected unviewed tracked summary')
    local untracked = file_by_id(loaded, 'new:untracked.txt')
    assert(untracked.added_lines == 2, 'expected untracked line count')
  end)
end

M.load_diffs_should_return_revision_errors_when_input_is_unsupported = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:run_git({ 'tag', 'tag-only' })
    repo:run_git({ 'update-ref', 'refs/notes/unsupported', 'HEAD' })

    local unresolved = diffs.load_diffs({ cwd = repo.cwd, from = 'does-not-exist' })
    assert_failure(unresolved, 'revision')
    assert(unresolved.error.detail ~= nil, 'expected Git revision diagnostic')
    local unsupported_ref = diffs.load_diffs({ cwd = repo.cwd, from = 'refs/notes/unsupported' })
    assert_failure(unsupported_ref, 'revision')
    local tag = diffs.load_diffs({ cwd = repo.cwd, from = 'tag-only' })
    assert_failure(tag, 'revision')
    local expression = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD~1' })
    assert_failure(expression, 'revision')
    local unresolved_to = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD', to = 'does-not-exist' })
    assert_failure(unresolved_to, 'revision')
  end)
end

M.load_diffs_should_return_revision_error_when_head_has_no_commits = function()
  git_repo.with_repo(function(repo)
    local head_result = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert_failure(head_result, 'revision')
  end)
end

M.load_diffs_should_return_missing_default_branch_when_origin_head_is_absent = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local result = diffs.load_diffs({ cwd = repo.cwd })
    assert_failure(result, 'missing_default_branch')
  end)
end

M.load_diffs_should_return_missing_default_branch_when_origin_head_target_is_invalid = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local blob = repo:run_git({ 'hash-object', '-w', '--stdin' }, { GIT_CONFIG_NOSYSTEM = '1' })
    local targets = {
      'refs/heads/main',
      'refs/remotes/origin/missing',
      'refs/remotes/origin/blob',
    }
    repo:run_git({ 'update-ref', 'refs/remotes/origin/blob', blob })
    for _, target in ipairs(targets) do
      repo:run_git({ 'symbolic-ref', 'refs/remotes/origin/HEAD', target })
      local result = diffs.load_diffs({ cwd = repo.cwd })
      assert_failure(result, 'missing_default_branch')
    end
  end)
end

M.load_diffs_should_use_exact_endpoints_and_exclude_working_state_when_two_revisions_are_supplied = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'first' })
    repo:add('tracked.txt')
    repo:commit('first')
    local first = repo:current_sha()
    repo:write_file('committed.txt', { 'second' })
    repo:add('committed.txt')
    repo:commit('second')
    local second = repo:current_sha()
    repo:write_file('working.txt', { 'excluded' })

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = first, to = second })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'new:committed.txt')
    assert_file_absent(loaded, 'new:working.txt')
  end)
end

M.load_diffs_should_treat_branch_names_as_exact_endpoints_when_two_revisions_are_supplied = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local main_branch = repo:run_git({ 'branch', '--show-current' })
    repo:branch('comparison-source')
    repo:write_file('main-only.txt', { 'main' })
    repo:add('main-only.txt')
    repo:commit('main')
    repo:run_git({ 'checkout', '--quiet', 'comparison-source' })
    repo:write_file('source-only.txt', { 'source' })
    repo:add('source-only.txt')
    repo:commit('source')
    repo:run_git({ 'checkout', '--quiet', main_branch })

    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'comparison-source', to = main_branch })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected exact branch endpoint comparison')
    file_by_id(loaded, 'new:main-only.txt')
    file_by_id(loaded, 'stored:source-only.txt')
  end)
end

M.load_diffs_should_resolve_local_branch_when_one_revision_is_supplied = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local main_branch = repo:run_git({ 'branch', '--show-current' })
    repo:branch('review-base')
    repo:write_file('main-only.txt', { 'head' })
    repo:add('main-only.txt')
    repo:commit('main head')
    repo:run_git({ 'checkout', '--quiet', 'review-base' })
    repo:write_file('branch-only.txt', { 'branch' })
    repo:add('branch-only.txt')
    repo:commit('branch head')
    repo:run_git({ 'checkout', '--quiet', main_branch })

    local branch_result, branch_loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'review-base' })
    assert(branch_result.ok, branch_result.error and branch_result.error.detail)
    assert(branch_loaded ~= nil, 'expected branch comparison')
    file_by_id(branch_loaded, 'new:main-only.txt')
    assert_file_absent(branch_loaded, 'stored:branch-only.txt')
  end)
end

M.load_diffs_should_prefer_local_branch_when_short_name_also_matches_remote = function()
  git_repo.with_repo(function(repo)
    repo:write_file('base.txt', { 'base' })
    repo:add('base.txt')
    repo:commit('base')
    repo:branch('shared')
    repo:write_file('main-only.txt', { 'main' })
    repo:add('main-only.txt')
    repo:commit('main change')
    repo:run_git({ 'update-ref', 'refs/remotes/shared', 'HEAD' })

    local local_result, local_loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'shared' })
    assert(local_result.ok, local_result.error and local_result.error.detail)
    assert(local_loaded ~= nil, 'expected local branch comparison')
    file_by_id(local_loaded, 'new:main-only.txt')

    local remote_result, remote_loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'refs/remotes/shared' })
    assert(remote_result.ok, remote_result.error and remote_result.error.detail)
    assert(remote_loaded ~= nil and #remote_loaded.files == 0, 'expected explicit remote ref comparison')
  end)
end

M.load_diffs_should_resolve_remote_branches_and_hashes_when_one_revision_is_supplied = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local base = repo:current_sha()
    local main_branch = repo:run_git({ 'branch', '--show-current' })
    repo:branch('remote-source')
    repo:write_file('main-only.txt', { 'head' })
    repo:add('main-only.txt')
    repo:commit('main head')
    repo:run_git({ 'checkout', '--quiet', 'remote-source' })
    repo:write_file('remote-only.txt', { 'remote' })
    repo:add('remote-only.txt')
    repo:commit('remote head')
    repo:run_git({ 'update-ref', 'refs/remotes/origin/review', 'HEAD' })
    repo:run_git({ 'checkout', '--quiet', main_branch })

    local remote_result, remote_loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'origin/review' })
    assert(remote_result.ok, remote_result.error and remote_result.error.detail)
    assert(remote_loaded ~= nil, 'expected remote branch comparison')
    file_by_id(remote_loaded, 'new:main-only.txt')
    assert_file_absent(remote_loaded, 'stored:remote-only.txt')
    local hash_result, hash_loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(hash_result.ok, hash_result.error and hash_result.error.detail)
    assert(hash_loaded ~= nil, 'expected hash comparison')
  end)
end

M.load_diffs_should_return_empty_files_when_comparison_has_no_changes = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local head = repo:current_sha()
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = head, to = head })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil and #loaded.files == 0, 'expected successful empty comparison')
  end)
end

return M
