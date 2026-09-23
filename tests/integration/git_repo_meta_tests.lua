local git = require('diffreview.diffs.git')
local git_repo = require('helpers.git_repo')
local M = {}

---@param cwd string|nil
---@return GitRepoMeta
local function metadata(cwd)
  local result, meta = git.get_repo(cwd):repo_meta()

  assert(result.ok, 'expected repo_meta to succeed: ' .. (result.error or 'unknown error'))
  assert(meta ~= nil, 'expected repository metadata')
  return meta
end

---@return nil
M.repo_meta_should_return_branch_and_empty_remotes_when_repository_has_no_commits = function()
  git_repo.with_repo(function(test_repo)
    test_repo:run_git({ 'symbolic-ref', 'HEAD', 'refs/heads/main' })

    local meta = metadata(test_repo.cwd)

    assert(meta.root == test_repo.cwd, 'expected repository root')
    assert(meta.branch == 'main', 'expected unborn branch name')
    assert(vim.deep_equal(meta.remotes, {}), 'expected no remotes')
    assert(meta.upstream_branch == nil, 'expected no upstream branch')
    assert(meta.default_branch == nil, 'expected no remote default branch')
  end)
end

---@return nil
M.repo_meta_should_return_root_when_called_from_nested_directory = function()
  git_repo.with_repo(function(test_repo)
    local nested = test_repo.cwd .. '/nested directory/child'
    assert(vim.fn.mkdir(nested, 'p') == 1, 'failed to create nested directory')

    local meta = metadata(nested)

    assert(meta.root == test_repo.cwd, 'expected repository root rather than supplied directory')
  end)
end

---@return nil
M.repo_meta_should_use_current_directory_when_dir_is_omitted = function()
  git_repo.with_repo(function(test_repo)
    local original_cwd = vim.fn.getcwd()
    local success, test_error = xpcall(function()
      vim.api.nvim_set_current_dir(test_repo.cwd)
      local meta = metadata(nil)
      assert(meta.root == test_repo.cwd, 'expected current directory repository')
    end, debug.traceback)

    vim.api.nvim_set_current_dir(original_cwd)
    assert(success, test_error)
  end)
end

---@return nil
M.repo_meta_should_return_all_remotes_when_origin_is_present = function()
  git_repo.with_repo(function(test_repo)
    local expected = {
      origin = 'https://example.com/origin/repo.git',
      fork = 'https://example.com/user/repo.git',
      upstream = 'https://example.com/team/repo.git',
    }
    for name, url in pairs(expected) do
      test_repo:run_git({ 'remote', 'add', name, url })
    end

    local meta = metadata(test_repo.cwd)

    assert(#meta.remotes == 3, 'expected all three remotes, not only origin')
    local actual = {}
    for _, remote in ipairs(meta.remotes) do
      actual[remote.name] = remote.url
    end
    assert(vim.deep_equal(actual, expected), 'expected remote names and URLs regardless of order')
  end)
end

---@return nil
M.repo_meta_should_return_upstream_and_origin_default_branch_when_present = function()
  git_repo.with_repo(function(test_repo)
    test_repo:run_git({ 'symbolic-ref', 'HEAD', 'refs/heads/main' })
    test_repo:write_file('file.txt', { 'content' })
    test_repo:add('file.txt')
    test_repo:commit('Initial commit')
    test_repo:run_git({ 'remote', 'add', 'origin', 'https://example.com/origin/repo.git' })
    test_repo:run_git({ 'update-ref', 'refs/remotes/origin/main', 'HEAD' })
    test_repo:run_git({ 'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main' })
    test_repo:run_git({ 'branch', '--set-upstream-to=origin/main', 'main' })

    local meta = metadata(test_repo.cwd)

    assert(meta.branch == 'main', 'expected active branch')
    assert(meta.upstream_branch == 'origin/main', 'expected configured upstream branch')
    assert(meta.default_branch == 'origin/main', 'expected cached origin default branch')
  end)
end

---@return nil
M.repo_meta_should_not_return_default_branch_when_only_other_remote_has_head = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('file.txt', { 'content' })
    test_repo:add('file.txt')
    test_repo:commit('Initial commit')
    test_repo:run_git({ 'remote', 'add', 'upstream', 'https://example.com/team/repo.git' })
    test_repo:run_git({ 'update-ref', 'refs/remotes/upstream/main', 'HEAD' })
    test_repo:run_git({ 'symbolic-ref', 'refs/remotes/upstream/HEAD', 'refs/remotes/upstream/main' })

    local meta = metadata(test_repo.cwd)

    assert(meta.default_branch == nil, 'expected no default branch without origin')
  end)
end

---@return nil
M.repo_meta_should_return_no_branch_when_head_is_detached = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('file.txt', { 'content' })
    test_repo:add('file.txt')
    test_repo:commit('Initial commit')
    test_repo:run_git({ 'checkout', '--quiet', '--detach', 'HEAD' })

    local meta = metadata(test_repo.cwd)

    assert(meta.root == test_repo.cwd, 'expected repository root')
    assert(meta.branch == nil, 'expected no active branch for detached HEAD')
    assert(meta.upstream_branch == nil, 'expected no upstream for detached HEAD')
  end)
end

---@return nil
M.repo_meta_should_return_error_when_directory_is_not_a_repository = function()
  git_repo.with_repo(function(test_repo)
    assert(vim.fn.delete(test_repo.cwd .. '/.git', 'rf') == 0, 'failed to remove temporary Git metadata')

    local original_ceiling_directories = vim.env.GIT_CEILING_DIRECTORIES
    vim.env.GIT_CEILING_DIRECTORIES = vim.fs.dirname(test_repo.cwd)
    local result, meta = git.get_repo(test_repo.cwd):repo_meta()
    vim.env.GIT_CEILING_DIRECTORIES = original_ceiling_directories

    assert(not result.ok, 'expected repo_meta to fail')
    assert(result.error ~= nil and result.error ~= '', 'expected error details')
    assert(meta == nil, 'expected no repository metadata')
  end)
end

return M
