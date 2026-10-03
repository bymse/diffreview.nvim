local git = require('diffreview.diffs.git')
local git_repo = require('helpers.git_repo')
local M = {}

---@param repo GitRepo
---@param from string|nil
---@param to string|nil
---@return GitDiff[]
local function diff(repo, from, to)
  local result, diffs = repo:diff(from, to)

  assert(result.ok, 'expected diff to succeed: ' .. (result.error or 'unknown error'))
  assert(diffs ~= nil, 'expected parsed diffs')
  return diffs
end

---@param diffs GitDiff[]
---@param path string
---@return GitDiff|nil
local function find_diff(diffs, path)
  for _, parsed_diff in ipairs(diffs) do
    if parsed_diff.current_path == path then
      return parsed_diff
    end
  end
end

M.diff_should_return_empty_array_when_initial_commit_has_no_changes = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('file.txt', { 'content' })
    test_repo:add('file.txt')
    test_repo:commit('Initial commit')

    local diffs = diff(git.get_repo(test_repo.cwd))

    assert(#diffs == 0, 'expected no diffs')
  end)
end

M.diff_should_return_empty_array_when_only_untracked_files_changed = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('tracked.txt', { 'tracked content' })
    test_repo:add('tracked.txt')
    test_repo:commit('Initial commit')
    test_repo:write_file('untracked.txt', { 'untracked content' })

    local diffs = diff(git.get_repo(test_repo.cwd))

    assert(#diffs == 0, 'expected no diffs')
  end)
end

M.diff_should_error_when_oid_has_invalid_form = function()
  local repo = git.get_repo(nil)
  local invalid_oids = { 'HEAD', '', 'not-an-oid', '123xyz' }

  for _, oid in ipairs(invalid_oids) do
    local from_success = pcall(function()
      repo:diff(oid, nil)
    end)
    assert(not from_success, 'expected invalid from OID to raise an error: ' .. oid)

    local to_success = pcall(function()
      repo:diff(nil, oid)
    end)
    assert(not to_success, 'expected invalid to OID to raise an error: ' .. oid)
  end
end

M.diff_should_return_all_changes_since_from_commit_when_to_is_nil = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('tracked.txt', { 'initial content' })
    test_repo:add('tracked.txt')
    test_repo:commit('Initial commit')
    local initial_sha = test_repo:current_sha()

    test_repo:write_file('tracked.txt', { 'modified content' })
    test_repo:add('tracked.txt')
    test_repo:commit('Modify tracked file')
    test_repo:write_file('added.txt', { 'added content' })
    test_repo:add('added.txt')
    test_repo:commit('Add another file')

    local diffs = diff(git.get_repo(test_repo.cwd), initial_sha, nil)

    assert(#diffs == 2, 'expected two diffs')
    local added_diff = find_diff(diffs, 'added.txt')
    assert(added_diff ~= nil, 'expected added file diff')
    assert(added_diff.status == 'A', 'expected added file status')
    local modified_diff = find_diff(diffs, 'tracked.txt')
    assert(modified_diff ~= nil, 'expected modified file diff')
    assert(modified_diff.status == 'M', 'expected modified file status')
  end)
end

M.diff_should_return_text_line_counts_when_file_changes = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('tracked.txt', { 'one', 'two', 'three' })
    test_repo:add('tracked.txt')
    test_repo:commit('Initial commit')
    local initial_sha = test_repo:current_sha()

    test_repo:write_file('tracked.txt', { 'one', 'updated', 'three', 'four' })

    local parsed_diff = find_diff(diff(git.get_repo(test_repo.cwd), initial_sha, nil), 'tracked.txt')
    assert(parsed_diff ~= nil, 'expected changed file diff')
    assert(parsed_diff.added_lines == 2, 'expected two added lines')
    assert(parsed_diff.removed_lines == 1, 'expected one removed line')
    assert(not parsed_diff.binary, 'expected text file')
  end)
end

M.diff_should_return_binary_marker_without_line_counts_when_binary_file_changes = function()
  git_repo.with_repo(function(test_repo)
    local initial_write = vim
      .system({ 'sh', '-c', 'printf "\\000\\001\\002" > image.bin' }, { cwd = test_repo.cwd })
      :wait()
    assert(initial_write.code == 0, 'failed to write binary file: ' .. initial_write.stderr)
    test_repo:add('image.bin')
    test_repo:commit('Initial commit')
    local initial_sha = test_repo:current_sha()

    local modified_write = vim
      .system({ 'sh', '-c', 'printf "\\000\\003\\004" > image.bin' }, { cwd = test_repo.cwd })
      :wait()
    assert(modified_write.code == 0, 'failed to write binary file: ' .. modified_write.stderr)

    local parsed_diff = find_diff(diff(git.get_repo(test_repo.cwd), initial_sha, nil), 'image.bin')
    assert(parsed_diff ~= nil, 'expected changed file diff')
    assert(parsed_diff.added_lines == nil, 'expected binary file to have no added line count')
    assert(parsed_diff.removed_lines == nil, 'expected binary file to have no removed line count')
    assert(parsed_diff.binary, 'expected binary file')
  end)
end

M.diff_should_include_staged_and_unstaged_changes_when_only_from_is_provided = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('unstaged.txt', { 'initial content' })
    test_repo:add('unstaged.txt')
    test_repo:commit('Initial commit')
    local initial_sha = test_repo:current_sha()

    test_repo:write_file('staged.txt', { 'staged content' })
    test_repo:add('staged.txt')
    test_repo:write_file('unstaged.txt', { 'unstaged content' })

    local diffs = diff(git.get_repo(test_repo.cwd), initial_sha, nil)

    assert(#diffs == 2, 'expected staged and unstaged diffs')
    local staged_diff = find_diff(diffs, 'staged.txt')
    assert(staged_diff ~= nil, 'expected staged file diff')
    assert(staged_diff.status == 'A', 'expected staged file to be added')
    local unstaged_diff = find_diff(diffs, 'unstaged.txt')
    assert(unstaged_diff ~= nil, 'expected unstaged file diff')
    assert(unstaged_diff.status == 'M', 'expected unstaged file to be modified')
  end)
end

M.diff_should_return_only_changes_between_from_and_to_commits = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('tracked.txt', { 'initial content' })
    test_repo:add('tracked.txt')
    test_repo:commit('Initial commit')
    local initial_sha = test_repo:current_sha()

    test_repo:write_file('tracked.txt', { 'modified content' })
    test_repo:add('tracked.txt')
    test_repo:commit('Modify tracked file')
    test_repo:write_file('included.txt', { 'included content' })
    test_repo:add('included.txt')
    test_repo:commit('Add included file')
    local pre_last_sha = test_repo:current_sha()

    test_repo:write_file('excluded.txt', { 'excluded content' })
    test_repo:add('excluded.txt')
    test_repo:commit('Add excluded file')

    local diffs = diff(git.get_repo(test_repo.cwd), initial_sha, pre_last_sha)

    assert(#diffs == 2, 'expected two diffs')
    local included_diff = find_diff(diffs, 'included.txt')
    assert(included_diff ~= nil, 'expected included file diff')
    assert(included_diff.status == 'A', 'expected included file status')
    local modified_diff = find_diff(diffs, 'tracked.txt')
    assert(modified_diff ~= nil, 'expected modified file diff')
    assert(modified_diff.status == 'M', 'expected modified file status')
    assert(find_diff(diffs, 'excluded.txt') == nil, 'expected final commit to be excluded')
  end)
end

return M
