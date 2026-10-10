local git_repo = require('helpers.git_repo')
local diffs = require('diffreview.diffs')

local M = {}

---@param path string
---@param bytes string
local function write_bytes(path, bytes)
  local fd = assert(vim.uv.fs_open(path, 'w', 420))
  assert(vim.uv.fs_write(fd, bytes, 0) == #bytes)
  assert(vim.uv.fs_close(fd))
end

---@param repo TestGitRepo
---@param id string
---@param from string|nil
---@return string
local function fingerprint(repo, id, from)
  local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = from or 'HEAD' })
  assert(result.ok and loaded, result.error and result.error.detail)
  return assert(loaded.entries_by_id[id], 'missing entry ' .. id).fingerprint
end

M.load_diffs_should_change_fingerprint_when_equal_numstat_content_changes = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'test' })
    local first_result, first = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(first_result.ok and first)
    repo:write_file('file.txt', { 'else' })
    local second_result, second = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(second_result.ok and second)
    assert(first.files[1].added_lines == second.files[1].added_lines)
    assert(first.entries_by_id['stored:file.txt'].fingerprint ~= second.entries_by_id['stored:file.txt'].fingerprint)
  end)
end

M.load_diffs_should_distinguish_tracked_untracked_symlink_and_mode_changes = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'changed' })
    repo:write_file('untracked.txt', { 'changed' })
    assert(vim.uv.fs_symlink('tracked.txt', repo.cwd .. '/link'))
    local tracked = fingerprint(repo, 'stored:tracked.txt')
    local untracked = fingerprint(repo, 'new:untracked.txt')
    local link = fingerprint(repo, 'new:link')
    assert(tracked ~= untracked and tracked ~= link and untracked ~= link)
    assert(vim.uv.fs_chmod(repo.cwd .. '/tracked.txt', 493))
    assert(fingerprint(repo, 'stored:tracked.txt') ~= tracked)
    assert(vim.uv.fs_unlink(repo.cwd .. '/link'))
    assert(vim.uv.fs_symlink('untracked.txt', repo.cwd .. '/link'))
    assert(fingerprint(repo, 'new:link') ~= link)
  end)
end

M.load_diffs_should_change_unmerged_fingerprint_with_stage_and_worktree_changes = function()
  git_repo.with_repo(function(repo)
    repo:write_file('conflict.txt', { 'base' })
    repo:add('conflict.txt')
    repo:commit('base')
    local base = repo:current_sha()
    local main = repo:run_git({ 'branch', '--show-current' })
    repo:run_git({ 'branch', 'other' })
    repo:write_file('conflict.txt', { 'ours' })
    repo:add('conflict.txt')
    repo:commit('ours')
    repo:run_git({ 'checkout', '--quiet', 'other' })
    repo:write_file('conflict.txt', { 'theirs' })
    repo:add('conflict.txt')
    repo:commit('theirs')
    repo:run_git({ 'checkout', '--quiet', main })
    local merge = vim.system({ 'git', 'merge', '--no-commit', 'other' }, { cwd = repo.cwd, text = true }):wait()
    assert(merge.code ~= 0)
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok and loaded and #loaded.files == 1, vim.inspect({ result, loaded and loaded.files }))
    local id = loaded.files[1].id
    local initial = fingerprint(repo, id, base)
    repo:write_file('conflict.txt', { 'worktree edit' })
    local edited = fingerprint(repo, id, base)
    assert(initial ~= edited)
    local replacement = vim
      .system({ 'git', 'hash-object', '-w', '--stdin' }, { cwd = repo.cwd, stdin = 'replacement\n', text = true })
      :wait()
    assert(replacement.code == 0)
    local stage = vim
      .system(
        { 'git', 'update-index', '--index-info' },
        { cwd = repo.cwd, stdin = '100644 ' .. vim.trim(replacement.stdout) .. ' 2\tconflict.txt\n', text = true }
      )
      :wait()
    assert(stage.code == 0, stage.stderr)
    assert(fingerprint(repo, id, base) ~= edited)
    assert(vim.uv.fs_unlink(repo.cwd .. '/conflict.txt'))
    local failed = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(not failed.ok and failed.error.kind == 'filesystem')
  end)
end

M.load_diffs_should_read_only_literal_conflict_path_with_metacharacters = function()
  git_repo.with_repo(function(repo)
    local path = 'conflict[1].txt'
    local neighbor = 'conflict1.txt'
    repo:write_file(path, { 'base' })
    repo:write_file(neighbor, { 'neighbor' })
    repo:add(path)
    repo:add(neighbor)
    repo:commit('base')
    local base = repo:current_sha()
    local main = repo:run_git({ 'branch', '--show-current' })
    repo:branch('other')
    repo:write_file(path, { 'ours' })
    repo:write_file(neighbor, { 'ours neighbor' })
    repo:add(path)
    repo:add(neighbor)
    repo:commit('ours')
    repo:run_git({ 'checkout', '--quiet', 'other' })
    repo:write_file(path, { 'theirs' })
    repo:write_file(neighbor, { 'theirs neighbor' })
    repo:add(path)
    repo:add(neighbor)
    repo:commit('theirs')
    repo:run_git({ 'checkout', '--quiet', main })
    local merge = vim.system({ 'git', 'merge', '--no-commit', 'other' }, { cwd = repo.cwd, text = true }):wait()
    assert(merge.code ~= 0)
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base })
    assert(result.ok and loaded, result.error and result.error.detail)
    local entry = assert(loaded.entries_by_id['stored:' .. path])
    assert(#entry.fingerprint == 64)
    assert(#assert(loaded.entries_by_id['stored:' .. neighbor]).fingerprint == 64)
  end)
end

M.load_diffs_should_fingerprint_added_deleted_renamed_and_binary_content = function()
  git_repo.with_repo(function(repo)
    repo:write_file('removed.txt', { 'old' })
    repo:write_file('moved.txt', { 'move' })
    repo:add('removed.txt')
    repo:add('moved.txt')
    repo:commit('base')
    local base = repo:current_sha()
    assert(vim.fn.delete(repo.cwd .. '/removed.txt') == 0)
    repo:run_git({ 'mv', 'moved.txt', 'renamed.txt' })
    repo:write_file('added.txt', { 'added' })
    write_bytes(repo.cwd .. '/binary.dat', 'one\0two')
    repo:add('added.txt')
    repo:add('binary.dat')
    repo:add('removed.txt')
    repo:commit('changes')
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base, to = 'HEAD' })
    assert(result.ok and loaded)
    local added = assert(loaded.entries_by_id['new:added.txt'])
    local deleted = assert(loaded.entries_by_id['stored:removed.txt'])
    local renamed = assert(loaded.entries_by_id['stored:moved.txt'])
    local binary = assert(loaded.entries_by_id['new:binary.dat'])
    assert(added.fingerprint ~= deleted.fingerprint and renamed.fingerprint ~= added.fingerprint)
    assert(binary.fingerprint ~= added.fingerprint and binary.git_diff.binary)
    repo:write_file('added.txt', { 'different' })
    write_bytes(repo.cwd .. '/binary.dat', 'two\0one')
    assert(fingerprint(repo, 'stored:added.txt') ~= added.fingerprint)
    assert(fingerprint(repo, 'stored:binary.dat') ~= binary.fingerprint)
  end)
end

M.load_diffs_should_fingerprint_copied_content_and_source_path = function()
  git_repo.with_repo(function(repo)
    repo:write_file('source.txt', { 'copy me' })
    repo:add('source.txt')
    repo:commit('base')
    local base = repo:current_sha()
    repo:write_file('copy.txt', { 'copy me' })
    repo:write_file('source.txt', { 'changed source' })
    repo:add('copy.txt')
    repo:add('source.txt')
    repo:commit('copy and change source')
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base, to = 'HEAD' })
    assert(result.ok and loaded)
    local copied = assert(loaded.entries_by_id['new:copy.txt'])
    assert(copied.git_diff.status == 'C', 'expected Git to detect a copy')
    assert(copied.fingerprint ~= loaded.entries_by_id['stored:source.txt'].fingerprint)
    assert(#copied.fingerprint == 64)
  end)
end

M.load_diffs_should_change_deleted_fingerprint_when_baseline_bytes_change = function()
  local fingerprints = {}
  for _, bytes in ipairs({ 'first', 'other' }) do
    git_repo.with_repo(function(repo)
      repo:write_file('removed.txt', { bytes })
      repo:add('removed.txt')
      repo:commit('base')
      local base = repo:current_sha()
      assert(vim.fn.delete(repo.cwd .. '/removed.txt') == 0)
      repo:add('removed.txt')
      repo:commit('delete')
      local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base, to = 'HEAD' })
      assert(result.ok and loaded)
      local entry = assert(loaded.entries_by_id['stored:removed.txt'])
      assert(entry.git_diff.status == 'D')
      fingerprints[#fingerprints + 1] = entry.fingerprint
    end)
  end
  assert(fingerprints[1] ~= fingerprints[2])
end

M.load_diffs_should_change_rename_fingerprint_when_source_path_changes = function()
  local fingerprints = {}
  for _, source in ipairs({ 'source-a.txt', 'source-b.txt' }) do
    git_repo.with_repo(function(repo)
      repo:write_file(source, { 'same bytes' })
      repo:add(source)
      repo:commit('base')
      local base = repo:current_sha()
      repo:run_git({ 'mv', source, 'target.txt' })
      repo:commit('rename')
      local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base, to = 'HEAD' })
      assert(result.ok and loaded)
      local entry = assert(loaded.entries_by_id['stored:' .. source])
      assert(entry.git_diff.status == 'R' and entry.git_diff.current_path == 'target.txt')
      fingerprints[#fingerprints + 1] = entry.fingerprint
    end)
  end
  assert(fingerprints[1] ~= fingerprints[2])
end

M.load_diffs_should_change_copy_fingerprint_when_source_path_changes = function()
  local fingerprints = {}
  for _, source in ipairs({ 'source-a.txt', 'source-b.txt' }) do
    git_repo.with_repo(function(repo)
      repo:write_file(source, { 'same bytes' })
      repo:add(source)
      repo:commit('base')
      local base = repo:current_sha()
      repo:write_file('target.txt', { 'same bytes' })
      repo:write_file(source, { 'changed source' })
      repo:add(source)
      repo:add('target.txt')
      repo:commit('copy')
      local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = base, to = 'HEAD' })
      assert(result.ok and loaded)
      local entry = assert(loaded.entries_by_id['new:target.txt'])
      assert(entry.git_diff.status == 'C' and entry.git_diff.old_path == source)
      fingerprints[#fingerprints + 1] = entry.fingerprint
    end)
  end
  assert(fingerprints[1] ~= fingerprints[2])
end

M.load_diffs_should_change_binary_fingerprint_when_bytes_change_without_changing_operation = function()
  git_repo.with_repo(function(repo)
    write_bytes(repo.cwd .. '/binary.dat', 'base\0bytes')
    repo:add('binary.dat')
    repo:commit('base')
    write_bytes(repo.cwd .. '/binary.dat', 'one\0bytes')
    local first_result, first = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(first_result.ok and first)
    local entry = assert(first.entries_by_id['stored:binary.dat'])
    assert(entry.git_diff.status == 'M' and entry.git_diff.binary)
    write_bytes(repo.cwd .. '/binary.dat', 'two\0bytes')
    local second_result, second = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(second_result.ok and second)
    local changed = assert(second.entries_by_id['stored:binary.dat'])
    assert(changed.git_diff.status == 'M' and changed.git_diff.binary)
    assert(entry.fingerprint ~= changed.fingerprint)
  end)
end

return M
