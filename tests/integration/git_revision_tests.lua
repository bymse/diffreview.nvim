local git = require('diffreview.diffs.git')
local git_repo = require('helpers.git_repo')
local M = {}

M.symbolic_ref_should_return_target_when_ref_is_symbolic = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('file.txt', { 'content' })
    test_repo:add('file.txt')
    test_repo:commit('initial')
    test_repo:run_git({ 'update-ref', 'refs/remotes/origin/main', 'HEAD' })
    test_repo:run_git({ 'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main' })

    local result, target = git.get_repo(test_repo.cwd):symbolic_ref('refs/remotes/origin/HEAD')

    assert(result.ok, 'expected symbolic-ref to succeed: ' .. (result.error or 'unknown error'))
    assert(target == 'refs/remotes/origin/main', 'expected symbolic ref target')
  end)
end

M.symbolic_ref_should_return_error_when_ref_does_not_exist = function()
  git_repo.with_repo(function(test_repo)
    local result, target = git.get_repo(test_repo.cwd):symbolic_ref('refs/remotes/origin/HEAD')

    assert(not result.ok, 'expected symbolic-ref to fail')
    assert(result.code ~= nil, 'expected symbolic-ref exit code')
    assert(target == nil, 'expected no symbolic ref target')
  end)
end

M.merge_base_should_return_common_ancestor_when_histories_diverge = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('base.txt', { 'base' })
    test_repo:add('base.txt')
    test_repo:commit('base')
    local base = test_repo:current_sha()
    test_repo:branch('side')
    test_repo:write_file('main.txt', { 'main' })
    test_repo:add('main.txt')
    test_repo:commit('main')
    local main = test_repo:current_sha()
    test_repo:run_git({ 'checkout', '--quiet', 'side' })
    test_repo:write_file('side.txt', { 'side' })
    test_repo:add('side.txt')
    test_repo:commit('side')
    local side = test_repo:current_sha()

    local result, ancestor = git.get_repo(test_repo.cwd):merge_base(main, side)

    assert(result.ok, 'expected merge-base to succeed: ' .. (result.error or 'unknown error'))
    assert(ancestor == base, 'expected common ancestor')
  end)
end

M.merge_base_should_return_error_when_revision_does_not_exist = function()
  git_repo.with_repo(function(test_repo)
    local result, ancestor = git.get_repo(test_repo.cwd):merge_base('HEAD', 'missing')

    assert(not result.ok, 'expected merge-base to fail')
    assert(result.error ~= nil and result.error ~= '', 'expected merge-base error details')
    assert(result.code ~= nil, 'expected merge-base exit code')
    assert(ancestor == nil, 'expected no common ancestor')
  end)
end

return M
