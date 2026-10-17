local comments = require('diffreview.comments')
local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local M = {}

---@param repo TestGitRepo
---@param from string
---@param to string|nil
---@return ReviewCommentCollection, LoadedDiffs
local function collection(repo, from, to)
  local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = from, to = to })
  assert(result.ok and loaded)
  return comments.new(), loaded
end

---@param review ReviewCommentCollection
---@param loaded LoadedDiffs
---@param id string
---@param side ReviewCommentSide
---@param last integer|nil
---@return nil
local function accept(review, loaded, id, side, last)
  local diff = assert(diffs.load_selected_view(loaded, id, nil, true))
  local record =
    assert(review:add({ file_id = id, side = side, text = 'feedback', line_start = last and 1, line_end = last }, diff))
  assert(vim.deep_equal(record.target, { file_id = id, side = side, line_start = last and 1, line_end = last }))
  assert(record.state == 'open')
end

---@param review ReviewCommentCollection
---@param loaded LoadedDiffs
---@param id string
---@param side ReviewCommentSide
---@param last integer|nil
---@return nil
local function reject(review, loaded, id, side, last)
  local diff = assert(diffs.load_selected_view(loaded, id, nil, true))
  local before = assert(review:list())
  local record, err =
    review:add({ file_id = id, side = side, text = 'feedback', line_start = last and 1, line_end = last }, diff)
  assert(record == nil and type(err) == 'string' and err ~= '')
  assert(vim.deep_equal(assert(review:list()), before))
end

---@param repo TestGitRepo
---@param path string
---@param bytes string
---@return nil
local function write_raw(repo, path, bytes)
  local descriptor = assert(vim.uv.fs_open(repo.cwd .. '/' .. path, 'w', 420))
  local written, err = vim.uv.fs_write(descriptor, bytes, 0)
  vim.uv.fs_close(descriptor)
  assert(written == #bytes, err)
end

M.add_should_preserve_file_ids_and_sides_when_files_are_added_deleted_renamed_or_copied = function()
  git_repo.with_repo(function(repo)
    for _, path in ipairs({ 'deleted.txt', 'renamed.txt', 'source.txt', 'modified.txt' }) do
      repo:write_file(path, { path, 'unchanged' })
      repo:add(path)
    end
    repo:commit('base')
    assert(vim.fn.delete(repo.cwd .. '/deleted.txt') == 0)
    repo:run_git({ 'mv', 'renamed.txt', 'moved.txt' })
    repo:write_file('source.txt', { 'changed source', 'unchanged' })
    repo:write_file('copied.txt', { 'source.txt', 'unchanged' })
    repo:add('source.txt')
    repo:add('copied.txt')
    repo:write_file('modified.txt', { 'changed', 'unchanged' })
    repo:write_file('added.txt', { 'added' })
    repo:add('added.txt')
    repo:write_file('untracked.txt', { 'untracked' })
    local review, loaded = collection(repo, 'HEAD')
    for _, side in ipairs({ 'old', 'current' }) do
      accept(review, loaded, 'stored:modified.txt', side, 2)
      reject(review, loaded, 'stored:modified.txt', side, 3)
    end
    for _, path in ipairs({ 'added.txt', 'untracked.txt' }) do
      accept(review, loaded, 'new:' .. path, 'current', 1)
      reject(review, loaded, 'new:' .. path, 'old')
      reject(review, loaded, 'new:' .. path, 'current', 2)
    end
    accept(review, loaded, 'stored:deleted.txt', 'old', 2)
    reject(review, loaded, 'stored:deleted.txt', 'current')
    accept(review, loaded, 'stored:renamed.txt', 'old', 2)
    accept(review, loaded, 'stored:renamed.txt', 'current', 2)
    accept(review, loaded, 'new:copied.txt', 'old', 2)
    accept(review, loaded, 'new:copied.txt', 'current', 2)
  end)
end

M.add_should_enforce_snapshot_bounds_when_binary_empty_and_normalized_text_are_loaded = function()
  git_repo.with_repo(function(repo)
    local bytes = {
      ['binary'] = '\0old',
      ['empty'] = '',
      ['blank'] = '\n',
      ['dos'] = 'one\r\ntwo\r\n',
      ['mac'] = 'one\rtwo\r',
      ['unix'] = 'one\ntwo\n',
      ['unterminated'] = 'one\ntwo',
    }
    for path, content in pairs(bytes) do
      write_raw(repo, path, content)
      repo:add(path)
    end
    repo:commit('base')
    for path in pairs(bytes) do
      write_raw(repo, path, path == 'binary' and '\0new' or 'changed\n')
    end
    local review, loaded = collection(repo, 'HEAD')
    for _, side in ipairs({ 'old', 'current' }) do
      accept(review, loaded, 'stored:binary', side)
      reject(review, loaded, 'stored:binary', side, 1)
    end
    accept(review, loaded, 'stored:empty', 'old')
    reject(review, loaded, 'stored:empty', 'old', 1)
    accept(review, loaded, 'stored:blank', 'old', 1)
    reject(review, loaded, 'stored:blank', 'old', 2)
    for _, path in ipairs({ 'dos', 'mac', 'unix', 'unterminated' }) do
      accept(review, loaded, 'stored:' .. path, 'old', 2)
      reject(review, loaded, 'stored:' .. path, 'old', 3)
      accept(review, loaded, 'stored:' .. path, 'current', 1)
      reject(review, loaded, 'stored:' .. path, 'current', 2)
    end
  end)
end

M.add_should_accept_text_sides_when_modes_types_and_symlinks_change = function()
  git_repo.with_repo(function(repo)
    repo:write_file('script.sh', { 'run' })
    repo:write_file('type.txt', { 'regular', 'second' })
    assert(vim.uv.fs_symlink('old-target', repo.cwd .. '/tracked-link'))
    for _, path in ipairs({ 'script.sh', 'type.txt', 'tracked-link' }) do
      repo:add(path)
    end
    repo:commit('base')
    local base = repo:current_sha()
    assert(vim.uv.fs_chmod(repo.cwd .. '/script.sh', 493))
    assert(vim.fn.delete(repo.cwd .. '/type.txt') == 0)
    assert(vim.uv.fs_symlink('missing-target', repo.cwd .. '/type.txt'))
    assert(vim.fn.delete(repo.cwd .. '/tracked-link') == 0)
    assert(vim.uv.fs_symlink('new-target', repo.cwd .. '/tracked-link'))
    assert(vim.uv.fs_symlink('missing-target', repo.cwd .. '/untracked-link'))
    local review, loaded = collection(repo, base)
    for _, side in ipairs({ 'old', 'current' }) do
      accept(review, loaded, 'stored:script.sh', side, 1)
      reject(review, loaded, 'stored:script.sh', side, 2)
      accept(review, loaded, 'stored:tracked-link', side, 1)
      reject(review, loaded, 'stored:tracked-link', side, 2)
    end
    accept(review, loaded, 'stored:type.txt', 'old', 2)
    accept(review, loaded, 'stored:type.txt', 'current', 1)
    reject(review, loaded, 'stored:type.txt', 'current', 2)
    accept(review, loaded, 'new:untracked-link', 'current', 1)
    reject(review, loaded, 'new:untracked-link', 'old')
    repo:add('tracked-link')
    repo:commit('new link')
    local revision, revision_loaded = collection(repo, base, repo:current_sha())
    accept(revision, revision_loaded, 'stored:tracked-link', 'old', 1)
    accept(revision, revision_loaded, 'stored:tracked-link', 'current', 1)
    reject(revision, revision_loaded, 'stored:tracked-link', 'current', 2)
  end)
end

M.add_should_use_revision_bounds_when_worktree_content_differs = function()
  git_repo.with_repo(function(repo)
    repo:write_file('revision.txt', { 'before' })
    repo:add('revision.txt')
    repo:commit('base')
    local base = repo:current_sha()
    repo:write_file('revision.txt', { 'after', 'second' })
    repo:add('revision.txt')
    repo:commit('target')
    local target = repo:current_sha()
    repo:write_file('revision.txt', { 'worktree', 'second', 'third' })
    local review, loaded = collection(repo, base, target)
    accept(review, loaded, 'stored:revision.txt', 'old', 1)
    reject(review, loaded, 'stored:revision.txt', 'old', 2)
    accept(review, loaded, 'stored:revision.txt', 'current', 2)
    reject(review, loaded, 'stored:revision.txt', 'current', 3)
  end)
end

M.add_should_require_snapshot_text_when_worktree_view_is_path_backed = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'before' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'after', 'second' })
    local review, loaded = collection(repo, 'HEAD')
    local path_view = assert(diffs.load_selected_view(loaded, 'stored:tracked.txt'))
    local whole = assert(review:add({ file_id = 'stored:tracked.txt', side = 'current', text = 'whole' }, path_view))
    local input = { file_id = 'stored:tracked.txt', side = 'current', text = 'line', line_start = 2, line_end = 2 }
    local rejected, err = review:add(input, path_view)
    assert(rejected == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), { whole }))
    local snapshot = assert(diffs.load_selected_view(loaded, 'stored:tracked.txt', nil, true))
    local line = assert(review:add(input, snapshot))
    assert(
      vim.deep_equal(line.target, { file_id = 'stored:tracked.txt', side = 'current', line_start = 2, line_end = 2 })
    )
    assert(vim.deep_equal(assert(review:list()), { whole, line }))
  end)
end

M.add_should_reject_unavailable_sides_when_content_disappears_after_summary_loading = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'changed' })
    repo:write_file('untracked.txt', { 'new' })
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded)
    assert(vim.fn.delete(repo.cwd .. '/tracked.txt') == 0)
    assert(vim.fn.delete(repo.cwd .. '/untracked.txt') == 0)
    local review = comments.new()
    for _, id in ipairs({ 'stored:tracked.txt', 'new:untracked.txt' }) do
      for _, side in ipairs({ 'old', 'current' }) do
        reject(review, loaded, id, side)
        reject(review, loaded, id, side, 1)
      end
    end
  end)
end

return M
