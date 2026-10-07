local async_operation = require('diffreview.async_operation')
local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local git_states = require('helpers.git_states')
local validator = require('diffreview.ui.diff_view_model_validator')

local M = {}

---@param path string
---@param bytes string
---@return nil
local function write_raw(path, bytes)
  local descriptor = assert(vim.uv.fs_open(path, 'w', 420))
  local written, write_error = vim.uv.fs_write(descriptor, bytes, 0)
  vim.uv.fs_close(descriptor)
  assert(written == #bytes, write_error or 'failed to write raw fixture bytes')
end

---@param repo TestGitRepo
---@param file_id string
---@param from string
---@param to string|nil
---@return LoadedDiffs, DiffViewModel
local function selected_view(repo, file_id, from, to)
  local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = from, to = to })
  assert(result.ok, result.error and result.error.detail)
  assert(loaded ~= nil, 'expected loaded review summaries')
  assert(loaded.entries_by_id[file_id] ~= nil, 'expected selected entry in loaded review')
  local view = diffs.load_selected_view(loaded, file_id)
  assert(view ~= nil, 'expected selected view')
  validator.validate(view)
  return loaded, view
end

---@param version DiffFileVersion
---@return DiffSnapshotTextContent
local function snapshot(version)
  local content = version.content
  if content.kind ~= 'text' then
    error('expected text snapshot')
  end
  if content.source ~= 'snapshot' then
    error('expected text snapshot')
  end
  ---@cast content DiffSnapshotTextContent
  return content
end

M.load_selected_view_should_return_worktree_bytes_when_a_tracked_file_changes = function()
  git_repo.with_repo(function(repo)
    local base = git_states.modify_file(repo, 'same-lines.txt', 'unstaged')

    local loaded, view = selected_view(repo, 'stored:same-lines.txt', base)

    assert(#loaded.files == 1, 'expected summaries before selecting file content')
    assert(view.operation == 'modified' and view.content_changed, 'expected changed bytes on the current side')
    assert(vim.deep_equal(snapshot(view.old).lines, { 'old same-lines.txt' }), 'expected committed baseline content')
    assert(view.current.content.source == 'path', 'expected a path-backed current regular file')
    assert(view.current.content.absolute_path == repo.cwd .. '/same-lines.txt', 'expected current worktree path')
  end)
end

M.load_selected_view_should_use_explicit_revision_blobs_instead_of_worktree_files = function()
  git_repo.with_repo(function(repo)
    repo:write_file('revision.txt', { 'first' })
    repo:add('revision.txt')
    repo:commit('first')
    local first = repo:current_sha()
    repo:write_file('revision.txt', { 'second' })
    repo:add('revision.txt')
    repo:commit('second')
    local second = repo:current_sha()
    repo:write_file('revision.txt', { 'worktree' })

    local _, view = selected_view(repo, 'stored:revision.txt', first, second)

    assert(view.operation == 'modified' and view.content_changed, 'expected committed change')
    assert(vim.deep_equal(snapshot(view.old).lines, { 'first' }), 'expected from-revision bytes')
    assert(vim.deep_equal(snapshot(view.current).lines, { 'second' }), 'expected to-revision bytes')
    assert(snapshot(view.current).filetype_path == 'revision.txt', 'expected revision path metadata')
  end)
end

M.load_selected_view_should_preserve_text_snapshot_line_endings_and_empty_content = function()
  git_repo.with_repo(function(repo)
    write_raw(repo.cwd .. '/dos.txt', 'first\r\nsecond\r\n')
    write_raw(repo.cwd .. '/mac.txt', 'one\rtwo\r')
    write_raw(repo.cwd .. '/empty.txt', '')
    repo:add('dos.txt')
    repo:add('mac.txt')
    repo:add('empty.txt')
    repo:commit('line endings')
    local base = repo:current_sha()
    repo:write_file('dos.txt', { 'changed' })
    repo:write_file('mac.txt', { 'changed' })
    repo:write_file('empty.txt', { 'changed' })

    local _, dos_view = selected_view(repo, 'stored:dos.txt', base)
    local _, mac_view = selected_view(repo, 'stored:mac.txt', base)
    local _, empty_view = selected_view(repo, 'stored:empty.txt', base)
    local dos = snapshot(dos_view.old)
    local mac = snapshot(mac_view.old)
    local empty = snapshot(empty_view.old)

    assert(vim.deep_equal(dos.lines, { 'first', 'second' }), 'expected DOS lines')
    assert(dos.fileformat == 'dos' and dos.endofline, 'expected DOS line ending metadata')
    assert(vim.deep_equal(mac.lines, { 'one', 'two' }), 'expected classic Mac lines')
    assert(mac.fileformat == 'mac' and mac.endofline, 'expected classic Mac line ending metadata')
    assert(#empty.lines == 0 and not empty.endofline, 'expected empty blob metadata')
  end)
end

M.load_selected_view_should_report_mode_only_changes_without_text_changes = function()
  git_repo.with_repo(function(repo)
    repo:write_file('script.sh', { 'run' })
    repo:add('script.sh')
    repo:commit('base')
    local base = repo:current_sha()
    assert(vim.uv.fs_chmod(repo.cwd .. '/script.sh', 493), 'failed to make fixture executable')

    local _, view = selected_view(repo, 'stored:script.sh', base)

    assert(view.operation == 'modified' and not view.content_changed, 'expected mode-only change')
    assert(view.old.mode == '100644' and view.current.mode == '100755', 'expected old and current modes')
  end)
end

M.load_selected_view_should_return_binary_metadata_for_binary_content = function()
  git_repo.with_repo(function(repo)
    write_raw(repo.cwd .. '/binary.bin', '\0old')
    repo:add('binary.bin')
    repo:commit('base')
    local base = repo:current_sha()
    write_raw(repo.cwd .. '/binary.bin', '\0new')

    local _, view = selected_view(repo, 'stored:binary.bin', base)

    assert(view.operation == 'modified' and view.content_changed, 'expected changed binary bytes')
    assert(view.old.content.kind == 'binary' and view.old.content.size == 4, 'expected baseline binary metadata')
    assert(view.current.content.kind == 'binary' and view.current.content.size == 4, 'expected current binary metadata')
  end)
end

M.load_selected_view_should_show_type_change_information_with_symlink_target_snapshot = function()
  git_repo.with_repo(function(repo)
    repo:write_file('type.txt', { 'regular file' })
    repo:add('type.txt')
    repo:commit('base')
    local base = repo:current_sha()
    assert(vim.fn.delete(repo.cwd .. '/type.txt') == 0, 'failed to replace regular file')
    assert(vim.uv.fs_symlink('link-target', repo.cwd .. '/type.txt'), 'failed to create symlink fixture')

    local _, view = selected_view(repo, 'stored:type.txt', base)

    assert(view.operation == 'type_changed', 'expected type-changed view')
    assert(view.old.mode == '100644' and view.current.mode == '120000', 'expected regular-to-symlink modes')
    assert(vim.deep_equal(snapshot(view.current).lines, { 'link-target' }), 'expected link target bytes')
    assert(not snapshot(view.current).endofline, 'expected symlink target without a trailing newline')
  end)
end

M.load_selected_view_should_preserve_committed_and_untracked_symlink_target_bytes = function()
  git_repo.with_repo(function(repo)
    assert(vim.uv.fs_symlink('first-target', repo.cwd .. '/tracked-link'), 'failed to create committed symlink')
    repo:add('tracked-link')
    repo:commit('first link')
    local first = repo:current_sha()
    assert(vim.fn.delete(repo.cwd .. '/tracked-link') == 0, 'failed to replace committed symlink')
    assert(vim.uv.fs_symlink('second-target', repo.cwd .. '/tracked-link'), 'failed to update committed symlink')
    repo:add('tracked-link')
    repo:commit('second link')
    local second = repo:current_sha()
    assert(vim.uv.fs_symlink('missing-target', repo.cwd .. '/untracked-link'), 'failed to create untracked symlink')

    local _, committed_view = selected_view(repo, 'stored:tracked-link', first, second)
    local _, untracked_view = selected_view(repo, 'new:untracked-link', first)

    assert(committed_view.operation == 'modified', 'expected committed symlink change')
    assert(vim.deep_equal(snapshot(committed_view.old).lines, { 'first-target' }), 'expected old committed link target')
    assert(
      vim.deep_equal(snapshot(committed_view.current).lines, { 'second-target' }),
      'expected current committed link target'
    )
    assert(
      untracked_view.operation == 'untracked' and untracked_view.current.mode == '120000',
      'expected untracked link'
    )
    assert(
      vim.deep_equal(snapshot(untracked_view.current).lines, { 'missing-target' }),
      'expected untracked link target without following it'
    )
  end)
end

M.load_selected_view_should_map_added_deleted_modified_and_renamed_entries = function()
  git_repo.with_repo(function(repo)
    repo:write_file('deleted.txt', { 'deleted baseline' })
    repo:write_file('renamed.txt', { 'renamed baseline' })
    repo:write_file('modified.txt', { 'modified baseline' })
    repo:add('deleted.txt')
    repo:add('renamed.txt')
    repo:add('modified.txt')
    repo:commit('base')
    local base = repo:current_sha()
    assert(vim.fn.delete(repo.cwd .. '/deleted.txt') == 0, 'failed to remove deleted fixture')
    repo:run_git({ 'mv', 'renamed.txt', 'moved.txt' })
    repo:write_file('modified.txt', { 'modified current' })
    repo:write_file('added.txt', { 'added current' })
    repo:add('added.txt')

    local _, deleted = selected_view(repo, 'stored:deleted.txt', base)
    local _, renamed = selected_view(repo, 'stored:renamed.txt', base)
    local _, modified = selected_view(repo, 'stored:modified.txt', base)
    local _, added = selected_view(repo, 'new:added.txt', base)

    assert(deleted.operation == 'deleted' and vim.deep_equal(snapshot(deleted.old).lines, { 'deleted baseline' }))
    assert(renamed.operation == 'renamed', 'expected renamed view')
    assert(renamed.old.display_path == 'renamed.txt' and renamed.current.display_path == 'moved.txt')
    assert(modified.operation == 'modified' and modified.content_changed, 'expected modified view')
    assert(added.operation == 'added' and added.current.display_path == 'added.txt', 'expected added view')
  end)
end

M.load_selected_view_should_map_copied_entries_with_both_source_and_destination = function()
  git_repo.with_repo(function(repo)
    repo:write_file('source.txt', { 'copy source', 'second line' })
    repo:add('source.txt')
    repo:commit('base')
    local base = repo:current_sha()
    repo:write_file('source.txt', { 'source changed', 'second line' })
    repo:write_file('copied.txt', { 'copy source', 'second line' })
    repo:add('source.txt')
    repo:add('copied.txt')

    local _, view = selected_view(repo, 'new:copied.txt', base)

    assert(view.operation == 'copied', 'expected copied view')
    assert(view.old.display_path == 'source.txt' and view.current.display_path == 'copied.txt')
    assert(vim.deep_equal(snapshot(view.old).lines, { 'copy source', 'second line' }), 'expected copy source content')
  end)
end

M.load_selected_view_should_use_current_conflict_content_for_worktree_comparison = function()
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
    local merge = vim.system({ 'git', 'merge', '--no-commit', 'other' }, { cwd = repo.cwd, text = true }):wait()
    assert(merge.code ~= 0, 'expected merge conflict')

    local _, view = selected_view(repo, 'stored:conflict.txt', base)

    assert(view.operation == 'modified', 'expected baseline-to-worktree change for unresolved path')
    assert(view.current.content.kind == 'text' and view.current.content.source == 'path')
  end)
end

M.load_selected_view_should_return_error_view_when_known_worktree_content_disappears = function()
  git_repo.with_repo(function(repo)
    local base = git_states.add_file(repo, 'untracked.txt', 'untracked')
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok and loaded ~= nil, 'expected summary load before content selection')
    assert(vim.fn.delete(repo.cwd .. '/untracked.txt') == 0, 'failed to remove selected fixture')

    local view = diffs.load_selected_view(loaded, 'new:untracked.txt')

    assert(view ~= nil and view.operation == 'error', 'expected per-file content error view')
    assert(view.attempted_operation == 'untracked' and view.path == 'untracked.txt')
    validator.validate(view)
  end)
end

M.load_selected_view_should_return_nil_for_unknown_ids_and_canceled_operations = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'changed' })
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded ~= nil, 'expected loaded review')
    local operation = async_operation.new()
    async_operation.cancel(operation)

    assert(diffs.load_selected_view(loaded, 'unknown:file.txt') == nil, 'expected unknown ID to return nil')
    assert(
      diffs.load_selected_view(loaded, 'stored:tracked.txt', operation) == nil,
      'expected cancellation to return nil'
    )

    local selection_operation = async_operation.new()
    local selected
    local worker = coroutine.create(function()
      selected = diffs.load_selected_view(loaded, 'stored:tracked.txt', selection_operation)
    end)
    local started, start_error = coroutine.resume(worker)
    assert(started, start_error)
    assert(coroutine.status(worker) == 'suspended', 'expected selected Git content load to be pending')
    async_operation.cancel(selection_operation)
    assert(
      vim.wait(1000, function()
        return coroutine.status(worker) == 'dead'
      end),
      'expected selected content load to finish after cancellation'
    )
    assert(selected == nil, 'expected in-flight cancellation to return nil')
  end)
end

return M
