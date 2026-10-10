local git_repo = require('helpers.git_repo')
local review = require('diffreview.review')
local storage = require('diffreview.storage')
local async_operation = require('diffreview.async_operation')

local M = {}

---@param session ReviewSession
---@param repo TestGitRepo
local function start(session, repo)
  session:start({ cwd = repo.cwd, from = 'HEAD' })
  assert(vim.wait(2000, function()
    return session.state.kind ~= 'starting'
  end))
  assert(session.state.kind == 'active', 'expected active review')
end

---@param session ReviewSession
---@param options ReviewStartOptions
local function start_with(session, options)
  session:start(options)
  assert(vim.wait(2000, function()
    return session.state.kind ~= 'starting'
  end))
  assert(session.state.kind == 'active', 'expected active review')
end

---@param id string
---@return boolean
local function viewed(id)
  local quickfix = vim.fn.getqflist({ id = 0, title = 1, items = 1 })
  assert(quickfix.title == 'Diff Review', 'expected review file list')
  for _, item in ipairs(quickfix.items) do
    if item.user_data and item.user_data.file_id == id then
      if item.text:sub(1, 3) == '[x]' then
        return true
      end
      assert(item.text:sub(1, 3) == '[ ]', 'expected viewed indicator')
      return false
    end
  end
  error('missing review row ' .. id)
end

M.mark_files_should_restore_checkpoint_when_content_returns = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    local id = 'stored:file.txt'
    assert(session:mark_files({ id }, true))
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    assert(vim.fn.filereadable(path) == 1 and not path:find(repo.cwd .. '/file.txt', 1, true))
    session:stop()
    repo:write_file('file.txt', { 'other' })
    start(session, repo)
    assert(not viewed(id))
    session:stop()
    repo:write_file('file.txt', { 'first' })
    start(session, repo)
    assert(viewed(id))
    assert(session:mark_files({ id }, false))
    session:stop()
    start(session, repo)
    assert(not viewed(id))
    session:stop()
  end)
end

M.mark_files_should_reject_all_ids_when_one_is_missing = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'new' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    assert(not session:mark_files({ 'stored:file.txt', 'missing' }, true))
    assert(not viewed('stored:file.txt'))
    session:stop()
  end)
end

M.mark_files_should_update_quickfix_after_success_without_opening_closed_drawer = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'new' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    local id = vim.fn.getqflist({ id = 0 }).id
    assert(session:mark_files({ 'stored:file.txt' }, true))
    assert(vim.fn.getqflist({ id = id, items = 1 }).items[1].text:find('[x]', 1, true))
    assert(session:mark_files({ 'stored:file.txt' }, false))
    assert(vim.fn.getqflist({ id = id, items = 1 }).items[1].text:find('[ ]', 1, true))
    session:stop()
  end)
end

M.start_should_isolate_source_baseline_and_target_and_canonicalize_selectors = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    local base = repo:current_sha()
    local branch = repo:run_git({ 'branch', '--show-current' })
    repo:set_default_branch()
    repo:branch('other')
    repo:write_file('file.txt', { 'changed' })
    repo:add('file.txt')
    repo:commit('change')
    local tip = repo:current_sha()
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    local id = 'stored:file.txt'
    local options = { cwd = repo.cwd, from = base, to = tip }
    start_with(session, options)
    assert(session:mark_files({ id }, true))
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    session:stop()
    start_with(session, { cwd = repo.cwd, from = base:sub(1, 12), to = tip:sub(1, 12) })
    assert(viewed(id))
    session:stop()
    start_with(session, { cwd = repo.cwd, from = base, to = 'HEAD' })
    assert(not viewed(id))
    session:stop()
    start_with(session, { cwd = repo.cwd, from = base })
    assert(not viewed(id))
    session:stop()
    start_with(session, { cwd = repo.cwd, from = 'origin/main' })
    assert(not viewed(id))
    session:stop()
    start_with(session, { cwd = repo.cwd })
    assert(not viewed(id))
    session:stop()
    repo:run_git({ 'checkout', '--quiet', 'other' })
    start_with(session, options)
    assert(not viewed(id))
    session:stop()
    repo:run_git({ 'checkout', '--quiet', '--detach', branch })
    start_with(session, options)
    assert(not viewed(id))
    session:stop()
    assert(vim.fn.filereadable(path) == 1)
  end)
end

M.start_should_retain_checkpoint_through_empty_comparison_and_moving_branch_tip = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:branch('baseline')
    repo:write_file('file.txt', { 'change' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    local options = { cwd = repo.cwd, from = 'baseline' }
    start_with(session, options)
    assert(session:mark_files({ 'stored:file.txt' }, true))
    local original_path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    session:stop()
    repo:write_file('file.txt', { 'base' })
    session:start(options)
    assert(vim.wait(2000, function()
      return session.state.kind == 'idle'
    end))
    assert(vim.fn.filereadable(original_path) == 1)
    repo:write_file('file.txt', { 'change' })
    start_with(session, { cwd = repo.cwd, from = 'refs/heads/baseline' })
    assert(viewed('stored:file.txt'))
    session:stop()
    repo:write_file('another.txt', { 'new' })
    repo:add('another.txt')
    repo:commit('tip moves')
    start_with(session, options)
    assert(storage.path(session.state.loaded.storage_path, session.state.loaded.identity) == original_path)
    assert(viewed('stored:file.txt'))
    session:stop()
  end)
end

M.start_should_restore_checkpoint_when_overlapping_remote_ref_appears = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:run_git({ 'checkout', '--quiet', '-b', 'origin/topic' })
    repo:write_file('file.txt', { 'changed' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    assert(session:mark_files({ 'stored:file.txt' }, true))
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    assert(
      vim.json.decode(table.concat(vim.fn.readfile(path), '\n')).identity.source == 'branch:refs/heads/origin/topic'
    )
    session:stop()
    repo:run_git({ 'update-ref', 'refs/remotes/origin/topic', 'HEAD' })
    assert(repo:run_git({ 'symbolic-ref', 'HEAD' }) == 'refs/heads/origin/topic')
    start(session, repo)
    assert(viewed('stored:file.txt'))
    assert(storage.path(session.state.loaded.storage_path, session.state.loaded.identity) == path)
    session:stop()
  end)
end

M.mark_files_should_leave_display_unchanged_when_save_fails = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'change' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    assert(vim.fn.delete(path) == 0)
    assert(vim.fn.mkdir(path) == 1)
    assert(not session:mark_files({ 'stored:file.txt' }, true))
    assert(not viewed('stored:file.txt'))
    assert(vim.fn.getqflist({ id = 0, items = 1 }).items[1].text:find('[ ]', 1, true))
    session:stop()
  end)
end

M.start_should_leave_malformed_state_unchanged_when_oid_or_fingerprint_is_invalid = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'change' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    session:stop()
    local original = table.concat(vim.fn.readfile(path), '\n')
    for _, corrupt in ipairs({
      function(value)
        value.from_oid = 'a'
      end,
      function(value)
        value.to_oid = 'invalid'
      end,
      function(value)
        value.head_oid = 'short'
      end,
      function(value)
        value.files[1].fingerprint = 'a'
      end,
    }) do
      local value = vim.json.decode(original)
      corrupt(value)
      local raw = vim.json.encode(value)
      assert(vim.fn.writefile({ raw }, path) == 0)
      local tabs = #vim.api.nvim_list_tabpages()
      session:start({ cwd = repo.cwd, from = 'HEAD' })
      assert(vim.wait(2000, function()
        return session.state.kind == 'idle'
      end))
      assert(#vim.api.nvim_list_tabpages() == tabs)
      assert(vim.fn.readfile(path)[1] == raw)
    end
  end)
end

M.start_should_reject_dangling_state_symlink_without_replacing_it = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'change' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    session:stop()
    assert(vim.uv.fs_unlink(path))
    local target = repo.cwd .. '/.git/missing-review-state'
    assert(vim.uv.fs_symlink(target, path))
    local tabs = #vim.api.nvim_list_tabpages()
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    assert(vim.wait(2000, function()
      return session.state.kind == 'idle'
    end))
    assert(#vim.api.nvim_list_tabpages() == tabs)
    assert(vim.uv.fs_lstat(path).type == 'link')
    assert(vim.uv.fs_readlink(path) == target)
    assert(vim.uv.fs_lstat(target) == nil)
  end)
end

M.start_should_leave_state_unchanged_when_file_cannot_be_opened = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'change' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    session:stop()
    local original = table.concat(vim.fn.readfile(path), '\n')
    assert(vim.uv.fs_chmod(path, 0))
    local unreadable = not vim.uv.fs_access(path, 'R')
    if unreadable then
      local tabs = #vim.api.nvim_list_tabpages()
      session:start({ cwd = repo.cwd, from = 'HEAD' })
      assert(vim.wait(2000, function()
        return session.state.kind == 'idle'
      end))
      assert(#vim.api.nvim_list_tabpages() == tabs)
    end
    assert(vim.uv.fs_chmod(path, 384))
    assert(table.concat(vim.fn.readfile(path), '\n') == original)
    if unreadable then
      start(session, repo)
      session:stop()
    end
  end)
end

M.mark_files_should_clear_older_checkpoint_when_current_version_is_unviewed = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    local id = 'stored:file.txt'
    repo:write_file('file.txt', { 'first' })
    start(session, repo)
    assert(session:mark_files({ id }, true))
    session:stop()
    repo:write_file('file.txt', { 'second' })
    start(session, repo)
    assert(not viewed(id))
    assert(session:mark_files({ id }, false))
    session:stop()
    repo:write_file('file.txt', { 'first' })
    start(session, repo)
    assert(not viewed(id))
    session:stop()
  end)
end

M.mark_files_should_replace_older_checkpoint_when_newer_version_is_marked_viewed = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    local id = 'stored:file.txt'
    repo:write_file('file.txt', { 'first' })
    start(session, repo)
    assert(session:mark_files({ id }, true))
    session:stop()
    repo:write_file('file.txt', { 'second' })
    start(session, repo)
    assert(not viewed(id))
    assert(session:mark_files({ id }, true))
    session:stop()
    start(session, repo)
    assert(viewed(id))
    session:stop()
    repo:write_file('file.txt', { 'first' })
    start(session, repo)
    assert(not viewed(id))
    session:stop()
  end)
end

M.mark_files_should_reject_inactive_or_canceled_review_without_saving = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'change' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    local id = 'stored:file.txt'
    assert(not session:mark_files({ id }, true))
    start(session, repo)
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    local original = table.concat(vim.fn.readfile(path), '\n')
    async_operation.cancel(session.state.operation)
    assert(not session:mark_files({ id }, true))
    assert(not viewed(id))
    assert(table.concat(vim.fn.readfile(path), '\n') == original)
    session:stop()
    assert(not session:mark_files({ id }, true))
    assert(table.concat(vim.fn.readfile(path), '\n') == original)
  end)
end

return M
