local diffs = require('diffreview.diffs')
local async = require('diffreview.async')
local git = require('diffreview.diffs.git')
local git_repo = require('helpers.git_repo')
local M = {}

local messages = {
  invalid_options = 'Invalid diff load options',
  repository = 'Not inside a Git worktree',
  missing_default_branch = 'Default branch is unavailable',
  revision = 'Unable to resolve revision',
  git = 'Git operation failed',
  filesystem = 'Unable to inspect repository files',
}

---@param result DiffLoadResult
---@param kind DiffLoadErrorKind
local function assert_failure(result, kind)
  assert(not result.ok, 'expected load to fail')
  assert(result.error ~= nil, 'expected structured error')
  assert(result.error.kind == kind, 'expected error kind ' .. kind)
  assert(result.error.message == messages[kind], 'expected stable user message')
  if kind == 'invalid_options' then
    assert(result.error.detail == nil, 'expected no validation diagnostic')
  elseif result.error.detail ~= nil then
    assert(result.error.detail ~= '', 'expected nonempty diagnostic detail')
  end
end

---@param repo TestGitRepo
local function set_default_branch(repo)
  local oid = repo:current_sha()
  repo:run_git({ 'update-ref', 'refs/remotes/origin/main', oid })
  repo:run_git({ 'symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main' })
end

local assert_lightweight

---@param loaded LoadedDiffs
---@param id string
---@return ChangedFileViewModel
local function file_by_id(loaded, id)
  assert_lightweight(loaded)
  for _, file in ipairs(loaded.files) do
    if file.id == id then
      return file
    end
  end
  error('missing file ' .. id)
end

---@param loaded LoadedDiffs
assert_lightweight = function(loaded)
  ---@type any
  local raw_loaded = loaded
  for _, field in ipairs({
    'lines',
    'content',
    'old',
    'current',
    'snapshots',
    'file_contents',
    'file_versions',
    'diffs',
    'diff_view_models',
    'diffs_by_id',
  }) do
    assert(raw_loaded[field] == nil, 'expected LoadedDiffs to omit ' .. field)
  end
  for _, summary in ipairs(loaded.files) do
    assert(summary.viewed == false, 'expected every summary to start unviewed')
    ---@type any
    local entry = loaded.entries_by_id[summary.id]
    assert(entry ~= nil, 'expected entry for summary')
    for _, field in ipairs({
      'lines',
      'content',
      'old',
      'current',
      'snapshots',
      'file_contents',
      'file_versions',
      'diffs',
      'diff_view_models',
      'diffs_by_id',
    }) do
      assert(entry[field] == nil, 'expected entry to omit ' .. field)
    end
  end
end

M.load_review_should_reject_invalid_options_when_required_table_fields_are_invalid = function()
  ---@type any
  local missing_options = nil
  local result = diffs.load_review(missing_options)
  assert_failure(result, 'invalid_options')

  ---@type any[]
  local invalid_options = {
    { unexpected = 'value' },
    { cwd = '' },
    { from = '' },
    { to = '' },
    { cwd = 1 },
    { from = 1 },
    { to = 1 },
    { to = 'HEAD' },
  }
  for _, options in ipairs(invalid_options) do
    result = diffs.load_review(options)
    assert_failure(result, 'invalid_options')
  end
end

M.load_review_should_load_default_branch_baseline_through_working_state_when_origin_head_exists = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    set_default_branch(repo)
    repo:write_file('tracked.txt', { 'working' })
    repo:write_file('untracked.txt', { 'one', 'two' })

    local result, loaded = diffs.load_review({ cwd = repo.cwd })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    assert_lightweight(loaded)
    assert(file_by_id(loaded, 'stored:tracked.txt').viewed == false, 'expected unviewed tracked summary')
    local untracked = file_by_id(loaded, 'new:untracked.txt')
    assert(untracked.added_lines == 2, 'expected untracked line count')
    assert(loaded.entries_by_id['new:untracked.txt'].git_diff == nil, 'expected no full diff model')
    ---@type any
    local untracked_entry = loaded.entries_by_id['new:untracked.txt']
    ---@type any
    local tracked_entry = loaded.entries_by_id['stored:tracked.txt']
    assert(untracked_entry.lines == nil, 'expected no retained snapshot lines')
    assert(tracked_entry.content == nil, 'expected no retained full diff content')
  end)
end

M.load_review_should_use_process_current_directory_when_cwd_is_omitted = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'working' })
    local original_cwd = vim.fn.getcwd()
    local success, result, loaded = xpcall(function()
      vim.api.nvim_set_current_dir(repo.cwd)
      return diffs.load_review({ from = 'HEAD' })
    end, debug.traceback)
    vim.api.nvim_set_current_dir(original_cwd)
    assert(success, result)
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected summaries from process current directory')
    file_by_id(loaded, 'stored:tracked.txt')
  end)
end

M.load_review_should_return_revision_errors_when_caller_revisions_are_unresolved_or_ambiguous = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:branch('ambiguous')
    repo:run_git({ 'tag', 'ambiguous' })
    repo:run_git({ 'update-ref', 'refs/notes/unsupported', 'HEAD' })

    local unresolved = diffs.load_review({ cwd = repo.cwd, from = 'does-not-exist' })
    assert_failure(unresolved, 'revision')
    assert(unresolved.error.detail ~= nil, 'expected Git revision diagnostic')
    local unsupported_ref = diffs.load_review({ cwd = repo.cwd, from = 'refs/notes/unsupported' })
    assert_failure(unsupported_ref, 'revision')
    local ambiguous = diffs.load_review({ cwd = repo.cwd, from = 'ambiguous' })
    assert_failure(ambiguous, 'revision')
    local unresolved_to = diffs.load_review({ cwd = repo.cwd, from = 'HEAD', to = 'does-not-exist' })
    assert_failure(unresolved_to, 'revision')
  end)
end

M.load_review_should_return_requested_errors_when_repository_has_no_commits = function()
  git_repo.with_repo(function(repo)
    local default_result = diffs.load_review({ cwd = repo.cwd })
    assert_failure(default_result, 'missing_default_branch')
    local head_result = diffs.load_review({ cwd = repo.cwd, from = 'HEAD' })
    assert_failure(head_result, 'revision')
  end)
end

M.load_review_should_return_filesystem_errors_when_cwd_is_missing_or_not_a_directory = function()
  local missing_result = diffs.load_review({ cwd = vim.fn.tempname() })
  assert_failure(missing_result, 'filesystem')
  local file = vim.fn.tempname()
  assert(vim.fn.writefile({ 'not a directory' }, file) == 0, 'failed to create cwd file')
  local file_result = diffs.load_review({ cwd = file })
  vim.fn.delete(file)
  assert_failure(file_result, 'filesystem')
end

M.load_review_should_return_filesystem_error_when_cwd_is_inaccessible = function()
  local directory = '/tmp/diffreview-inaccessible-cwd-' .. tostring(vim.uv.hrtime())
  assert(vim.fn.mkdir(directory) == 1, 'failed to create inaccessible cwd fixture')
  assert(vim.uv.fs_chmod(directory, 292), 'failed to make cwd fixture non-traversable')
  local readable = vim.uv.fs_access(directory, 'R')
  local traversable = vim.uv.fs_access(directory, 'X')
  local success, result = xpcall(function()
    return diffs.load_review({ cwd = directory })
  end, debug.traceback)
  assert(vim.uv.fs_chmod(directory, 493), 'failed to restore cwd fixture permissions')
  vim.fn.delete(directory, 'rf')
  assert(success, result)
  assert(readable, 'expected mode-0444 directory to remain readable')
  if traversable then
    assert_failure(result, 'repository')
  else
    assert_failure(result, 'filesystem')
  end
end

M.load_review_should_return_filesystem_error_when_native_cwd_access_fails = function()
  local directory = '/tmp/diffreview-native-access-failure-' .. tostring(vim.uv.hrtime())
  assert(vim.fn.mkdir(directory) == 1, 'failed to create cwd fixture')
  local original_access = vim.uv.fs_access
  vim.uv.fs_access = function(path, mode)
    if path == directory and mode == 'X' then
      return nil, 'injected traversal denial'
    end
    return original_access(path, mode)
  end
  local success, result = xpcall(function()
    return diffs.load_review({ cwd = directory })
  end, debug.traceback)
  vim.uv.fs_access = original_access
  vim.fn.delete(directory, 'rf')
  assert(success, result)
  assert_failure(result, 'filesystem')
  assert(result.error.detail == 'injected traversal denial', 'expected native access diagnostic')
end

M.load_review_should_return_repository_error_when_cwd_is_not_a_worktree = function()
  local directory = '/tmp/diffreview-not-worktree-' .. tostring(vim.uv.hrtime())
  assert(vim.fn.mkdir(directory) == 1, 'failed to create non-repository directory')
  local result = diffs.load_review({ cwd = directory })
  vim.fn.delete(directory, 'rf')
  assert_failure(result, 'repository')
end

M.load_review_should_return_missing_default_branch_when_origin_head_is_absent = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local result = diffs.load_review({ cwd = repo.cwd })
    assert_failure(result, 'missing_default_branch')
  end)
end

M.load_review_should_return_missing_default_branch_when_origin_head_target_is_invalid = function()
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
      local result = diffs.load_review({ cwd = repo.cwd })
      assert_failure(result, 'missing_default_branch')
    end
  end)
end

M.load_review_should_use_exact_endpoints_and_exclude_working_state_when_two_revisions_are_supplied = function()
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

    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = first, to = second })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'new:committed.txt')
    assert(loaded.entries_by_id['new:working.txt'] == nil, 'expected working state exclusion')
  end)
end

M.load_review_should_treat_branch_names_as_exact_endpoints_when_two_revisions_are_supplied = function()
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

    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = 'comparison-source', to = main_branch })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected exact branch endpoint comparison')
    file_by_id(loaded, 'new:main-only.txt')
    file_by_id(loaded, 'stored:source-only.txt')
  end)
end

M.load_review_should_resolve_branch_and_tag_revisions_when_one_revision_is_supplied = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local main_branch = repo:run_git({ 'branch', '--show-current' })
    repo:branch('review-base')
    repo:run_git({ 'tag', 'review-tag' })
    repo:write_file('main-only.txt', { 'head' })
    repo:add('main-only.txt')
    repo:commit('main head')
    repo:run_git({ 'checkout', '--quiet', 'review-base' })
    repo:write_file('branch-only.txt', { 'branch' })
    repo:add('branch-only.txt')
    repo:commit('branch head')
    repo:run_git({ 'checkout', '--quiet', main_branch })

    local branch_result, branch_loaded = diffs.load_review({ cwd = repo.cwd, from = 'review-base' })
    assert(branch_result.ok, branch_result.error and branch_result.error.detail)
    assert(branch_loaded ~= nil, 'expected branch comparison')
    file_by_id(branch_loaded, 'new:main-only.txt')
    assert(branch_loaded.entries_by_id['stored:branch-only.txt'] == nil, 'expected merge-base baseline')
    local tag_result, tag_loaded = diffs.load_review({ cwd = repo.cwd, from = 'review-tag' })
    assert(tag_result.ok, tag_result.error and tag_result.error.detail)
    assert(tag_loaded ~= nil, 'expected tag comparison')
    file_by_id(tag_loaded, 'new:main-only.txt')
  end)
end

M.load_review_should_resolve_remote_branches_and_hashes_when_one_revision_is_supplied = function()
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

    local remote_result, remote_loaded = diffs.load_review({ cwd = repo.cwd, from = 'origin/review' })
    assert(remote_result.ok, remote_result.error and remote_result.error.detail)
    assert(remote_loaded ~= nil, 'expected remote branch comparison')
    file_by_id(remote_loaded, 'new:main-only.txt')
    assert(remote_loaded.entries_by_id['stored:remote-only.txt'] == nil, 'expected remote merge-base baseline')
    local hash_result, hash_loaded = diffs.load_review({ cwd = repo.cwd, from = base })
    assert(hash_result.ok, hash_result.error and hash_result.error.detail)
    assert(hash_loaded ~= nil, 'expected hash comparison')
  end)
end

M.load_review_should_return_empty_files_when_comparison_has_no_changes = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local head = repo:current_sha()
    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = head, to = head })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil and #loaded.files == 0, 'expected successful empty comparison')
  end)
end

M.load_review_should_normalize_operation_identities_when_git_reports_added_deleted_modified_renamed_and_type_changed = function()
  git_repo.with_repo(function(repo)
    repo:write_file('modified.txt', { 'modified before' })
    repo:write_file('deleted.txt', { 'deleted before' })
    repo:write_file('renamed.txt', { 'renamed before' })
    repo:write_file('type.txt', { 'type before' })
    repo:add('modified.txt')
    repo:add('deleted.txt')
    repo:add('renamed.txt')
    repo:add('type.txt')
    repo:commit('base')
    local base = repo:current_sha()
    repo:write_file('modified.txt', { 'after' })
    repo:run_git({ 'rm', '--quiet', 'deleted.txt' })
    repo:run_git({ 'mv', 'renamed.txt', 'destination.txt' })
    assert(vim.fn.delete(repo.cwd .. '/type.txt') == 0, 'failed to remove type fixture file')
    assert(vim.uv.fs_symlink('target.txt', repo.cwd .. '/type.txt'), 'failed to create type fixture symlink')
    repo:add('type.txt')
    repo:write_file('added.txt', { 'added' })
    repo:add('added.txt')

    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'stored:deleted.txt')
    assert(file_by_id(loaded, 'stored:modified.txt').display_path == 'modified.txt', 'expected stored modified ID')
    assert(
      file_by_id(loaded, 'stored:renamed.txt').display_path == 'destination.txt',
      'expected rename source identity'
    )
    local type_changed = file_by_id(loaded, 'stored:type.txt')
    assert(loaded.entries_by_id[type_changed.id].git_diff.status == 'T', 'expected genuine type-changed status')
    file_by_id(loaded, 'new:added.txt')
  end)
end

M.load_review_should_use_new_identity_when_git_reports_a_copy = function()
  git_repo.with_repo(function(repo)
    repo:write_file('source.txt', { 'copy source', 'second line' })
    repo:add('source.txt')
    repo:commit('base')
    local base = repo:current_sha()
    repo:write_file('source.txt', { 'source changed', 'second line' })
    repo:write_file('copied.txt', { 'copy source', 'second line' })
    repo:add('source.txt')
    repo:add('copied.txt')

    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    local copied = file_by_id(loaded, 'new:copied.txt')
    assert(loaded.entries_by_id[copied.id].git_diff.status == 'C', 'expected copied status')
  end)
end

M.load_review_should_use_stored_identity_when_git_reports_an_unmerged_file_with_baseline_content = function()
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

    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'stored:conflict.txt')
  end)
end

M.load_review_should_use_new_identity_when_git_reports_an_unmerged_file_without_baseline_content = function()
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

    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = base })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    file_by_id(loaded, 'new:added-by-both.txt')
  end)
end

M.load_review_should_summarize_binary_untracked_files_without_retaining_contents = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local write_result = vim.system({ 'sh', '-c', 'printf "\\000\\001" > binary.bin' }, { cwd = repo.cwd }):wait()
    assert(write_result.code == 0, 'failed to write binary fixture')

    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    local binary = file_by_id(loaded, 'new:binary.bin')
    assert(binary.added_lines == 0 and binary.removed_lines == 0, 'expected format-safe binary counts')
    assert(loaded.entries_by_id[binary.id].binary, 'expected retained binary metadata')
  end)
end

M.load_review_should_return_filesystem_error_when_an_untracked_file_cannot_be_inspected = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('untracked.txt', { 'untracked' })
    ---@type any
    local git_adapter = git
    local original_get_repo = git_adapter.get_repo
    git_adapter.get_repo = function(cwd)
      local git_repository = original_get_repo(cwd)
      local original_ls_files = git_repository.ls_files
      git_repository.ls_files = function(self)
        local list_result, paths = original_ls_files(self)
        self.untracked_file_stats = function()
          return { ok = false, error = 'injected inspection failure' }, nil, nil, nil
        end
        return list_result, paths
      end
      return git_repository
    end
    local success, result = xpcall(function()
      return diffs.load_review({ cwd = repo.cwd, from = 'HEAD' })
    end, debug.traceback)
    git_adapter.get_repo = original_get_repo
    assert(success, result)
    assert_failure(result, 'filesystem')
    assert(result.error.detail == 'injected inspection failure', 'expected inspection diagnostic')
  end)
end

M.load_review_should_return_git_error_when_tracked_diff_command_fails = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    assert(vim.fn.writefile({ 'corrupted index' }, repo.cwd .. '/.git/index') == 0, 'failed to corrupt index fixture')

    local result = diffs.load_review({ cwd = repo.cwd, from = 'HEAD' })
    assert_failure(result, 'git')
    assert(result.error.detail ~= nil and result.error.detail ~= '', 'expected Git command diagnostic')
  end)
end

M.load_review_should_stop_revision_resolution_when_operation_is_canceled = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local operation = async.new_operation()
    ---@type any
    local git_adapter = git
    local original_get_repo = git_adapter.get_repo
    local named_ref_calls = 0
    git_adapter.get_repo = function(cwd)
      local git_repository = original_get_repo(cwd)
      local original_named_ref = git_repository.named_ref
      git_repository.named_ref = function(self, ref)
        named_ref_calls = named_ref_calls + 1
        local result, oid = original_named_ref(self, ref)
        async.cancel(operation)
        return result, oid
      end
      return git_repository
    end
    local success, result = xpcall(function()
      return diffs.load_review({ cwd = repo.cwd, from = 'HEAD' }, operation)
    end, debug.traceback)
    git_adapter.get_repo = original_get_repo
    assert(success, result)
    assert(not result.ok and result.error.kind == 'canceled', 'expected canceled load result')
    assert(result.error.detail == nil, 'expected canceled load without detail')
    assert(named_ref_calls == 1, 'expected cancellation between revision candidates')
  end)
end

M.load_review_should_stop_untracked_file_inspection_when_operation_is_canceled = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('first.txt', { 'first' })
    repo:write_file('second.txt', { 'second' })
    local operation = async.new_operation()
    ---@type any
    local git_adapter = git
    local original_get_repo = git_adapter.get_repo
    local inspection_calls = 0
    git_adapter.get_repo = function(cwd)
      local git_repository = original_get_repo(cwd)
      local original_untracked_file_stats = git_repository.untracked_file_stats
      git_repository.untracked_file_stats = function(self, path)
        inspection_calls = inspection_calls + 1
        local result, added, removed, binary = original_untracked_file_stats(self, path)
        async.cancel(operation)
        return result, added, removed, binary
      end
      return git_repository
    end
    local success, result = xpcall(function()
      return diffs.load_review({ cwd = repo.cwd, from = 'HEAD' }, operation)
    end, debug.traceback)
    git_adapter.get_repo = original_get_repo
    assert(success, result)
    assert(not result.ok and result.error.kind == 'canceled', 'expected canceled load result')
    assert(result.error.detail == nil, 'expected canceled load without detail')
    assert(inspection_calls == 1, 'expected cancellation between untracked-file inspections')
  end)
end

M.load_review_should_match_git_numstat_for_untracked_text_line_endings = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    local write_result = vim
      .system({
        'sh',
        '-c',
        'printf "" > empty.txt; printf "unterminated" > unterminated.txt; printf "one\\ntwo\\n" > lf.txt; printf "one\\r\\ntwo\\r\\n" > crlf.txt; printf "one\\rtwo\\r" > cr.txt',
      }, { cwd = repo.cwd })
      :wait()
    assert(write_result.code == 0, 'failed to write line-ending fixtures')

    local result, loaded = diffs.load_review({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok, result.error and result.error.detail)
    assert(loaded ~= nil, 'expected loaded summaries')
    assert(file_by_id(loaded, 'new:empty.txt').added_lines == 0, 'expected empty file count')
    assert(file_by_id(loaded, 'new:unterminated.txt').added_lines == 1, 'expected unterminated line count')
    assert(file_by_id(loaded, 'new:lf.txt').added_lines == 2, 'expected LF line count')
    assert(file_by_id(loaded, 'new:crlf.txt').added_lines == 2, 'expected CRLF line count')
    assert(file_by_id(loaded, 'new:cr.txt').added_lines == 1, 'expected Git CR-only line count')
  end)
end

return M
