local git_repo = require('helpers.git_repo')
local review = require('diffreview.review')
local storage = require('diffreview.storage')
local diffs = require('diffreview.diffs')

local M = {}

local function rows()
  local result = {}
  for _, item in ipairs(vim.fn.getqflist({ id = 0, items = 1 }).items) do
    result[item.user_data.file_id] = item.text:sub(1, 3)
  end
  return result
end

M.refresh_should_reconcile_checkpoints_when_worktree_changes_and_returns = function()
  git_repo.with_repo(function(repo)
    repo:write_file('a.txt', { 'base' })
    repo:write_file('b.txt', { 'base' })
    repo:add('a.txt')
    repo:add('b.txt')
    repo:commit('base')
    repo:write_file('a.txt', { 'first' })
    repo:write_file('b.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    assert(session:mark_files({ 'stored:a.txt', 'stored:b.txt' }, true))
    repo:write_file('a.txt', { 'other' })
    repo:write_file('untracked.txt', { 'new' })
    assert(session:refresh())
    assert(vim.wait(2000, function()
      return rows()['new:untracked.txt'] ~= nil
    end))
    assert(rows()['stored:a.txt'] == '[ ]' and rows()['stored:b.txt'] == '[x]')
    repo:write_file('a.txt', { 'first' })
    assert(session:refresh())
    assert(vim.wait(2000, function()
      return rows()['stored:a.txt'] == '[x]'
    end))
    assert(session:mark_files({ 'stored:a.txt' }, false))
    repo:write_file('a.txt', { 'other' })
    assert(session:refresh())
    assert(vim.wait(2000, function()
      return rows()['stored:a.txt'] == '[ ]'
    end))
    repo:write_file('a.txt', { 'first' })
    assert(session:refresh())
    assert(vim.wait(2000, function()
      return rows()['stored:a.txt'] == '[ ]'
    end))
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    assert(vim.fn.filereadable(path) == 1)
    session:stop()
  end)
end

M.refresh_should_preserve_review_when_identity_or_storage_fails = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    assert(session:mark_files({ 'stored:file.txt' }, true))
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    local original = vim.fn.readfile(path)[1]
    repo:write_file('file.txt', { 'second' })
    assert(vim.fn.delete(path) == 0 and vim.fn.mkdir(path) == 1)
    assert(session:refresh())
    vim.wait(300)
    assert(rows()['stored:file.txt'] == '[x]')
    assert(session:mark_files({ 'stored:file.txt' }, false) == false)
    assert(vim.fn.delete(path, 'd') == 0)
    assert(vim.fn.writefile({ original }, path) == 0)
    repo:run_git({ 'checkout', '--quiet', '-b', 'other' })
    assert(session:refresh())
    vim.wait(300)
    assert(rows()['stored:file.txt'] == '[x]' and vim.fn.readfile(path)[1] == original)
    session:stop()
  end)
end

M.refresh_should_preserve_progress_when_stop_cancels_pending_reload = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    assert(session:mark_files({ 'stored:file.txt' }, true))
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    local saved = vim.fn.readfile(path)[1]
    repo:write_file('file.txt', { 'second' })
    assert(session:refresh())
    session:stop()
    assert(vim.wait(200, function()
      return session.state.kind == 'idle'
    end))
    assert(vim.fn.readfile(path)[1] == saved)
  end)
end

M.refresh_should_reconcile_staged_and_unstaged_changes_after_restart = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    local options = { cwd = repo.cwd, from = 'HEAD' }
    session:start(options)
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    assert(session:mark_files({ 'stored:file.txt' }, true))
    repo:add('file.txt')
    assert(session:refresh())
    vim.wait(300)
    assert(rows()['stored:file.txt'] == '[x]')
    repo:write_file('file.txt', { 'other' })
    assert(session:refresh())
    assert(vim.wait(2000, function()
      return rows()['stored:file.txt'] == '[ ]'
    end))
    session:stop()
    session:start(options)
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    assert(rows()['stored:file.txt'] == '[ ]')
    repo:write_file('file.txt', { 'first' })
    assert(session:refresh())
    assert(vim.wait(2000, function()
      return rows()['stored:file.txt'] == '[x]'
    end))
    session:stop()
  end)
end

M.refresh_should_leave_saved_checkpoint_when_repository_load_fails = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    assert(session:mark_files({ 'stored:file.txt' }, true))
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    local saved = vim.fn.readfile(path)[1]
    assert(vim.fn.rename(repo.cwd .. '/.git', repo.cwd .. '/.git-hidden') == 0)
    assert(session:refresh())
    vim.wait(300)
    assert(rows()['stored:file.txt'] == '[x]')
    assert(vim.fn.rename(repo.cwd .. '/.git-hidden', repo.cwd .. '/.git') == 0)
    assert(vim.fn.readfile(path)[1] == saved)
    assert(session:mark_files({ 'stored:file.txt' }, false))
    session:stop()
  end)
end

M.refresh_should_discard_pending_candidate_when_mark_or_new_refresh_supersedes_it = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    repo:write_file('file.txt', { 'second' })
    assert(session:refresh())
    assert(session:mark_files({ 'stored:file.txt' }, true))
    local marked = vim.fn.readfile(path)[1]
    vim.wait(300)
    assert(rows()['stored:file.txt'] == '[x]' and vim.fn.readfile(path)[1] == marked)
    assert(session:refresh())
    repo:write_file('file.txt', { 'third' })
    assert(session:refresh())
    assert(vim.wait(2000, function()
      local state = vim.json.decode(vim.fn.readfile(path)[1])
      return rows()['stored:file.txt'] == '[ ]'
        and state.files[1].fingerprint ~= state.files[1].viewed_fingerprint
        and state.files[1].fingerprint ~= vim.json.decode(marked).files[1].fingerprint
    end))
    local latest = vim.json.decode(vim.fn.readfile(path)[1])
    local diff = require('diffreview.diffs')
    local result, loaded = diff.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded)
    assert(latest.files[1].fingerprint == loaded.entries_by_id['stored:file.txt'].fingerprint)
    session:stop()
  end)
end

M.refresh_should_update_added_deleted_and_untracked_files = function()
  git_repo.with_repo(function(repo)
    repo:write_file('deleted.txt', { 'base' })
    repo:add('deleted.txt')
    repo:commit('base')
    repo:write_file('untracked.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    assert(session:mark_files({ 'new:untracked.txt' }, true))
    repo:write_file('untracked.txt', { 'other' })
    repo:write_file('added.txt', { 'new' })
    repo:add('added.txt')
    assert(vim.fn.delete(repo.cwd .. '/deleted.txt') == 0)
    assert(session:refresh())
    assert(vim.wait(2000, function()
      local current = rows()
      return current['new:untracked.txt'] == '[ ]'
        and current['new:added.txt'] == '[ ]'
        and current['stored:deleted.txt'] == '[ ]'
    end))
    assert(session:mark_files({ 'new:added.txt', 'stored:deleted.txt' }, true))
    assert(vim.fn.delete(repo.cwd .. '/untracked.txt') == 0)
    assert(vim.fn.delete(repo.cwd .. '/added.txt') == 0)
    repo:write_file('deleted.txt', { 'base' })
    assert(session:refresh())
    assert(vim.wait(2000, function()
      local current = rows()
      return current['new:untracked.txt'] == nil
        and current['new:added.txt'] == nil
        and current['stored:deleted.txt'] == nil
    end))
    session:stop()
  end)
end

local function selected_failure_case(change_selected)
  git_repo.with_repo(function(repo)
    repo:write_file('selected.txt', { 'base' })
    repo:write_file('another.txt', { 'base' })
    repo:add('selected.txt')
    repo:add('another.txt')
    repo:commit('base')
    repo:write_file('selected.txt', { 'first' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    assert(session:mark_files({ 'stored:selected.txt' }, true))
    session:select_file('stored:selected.txt')
    assert(vim.wait(2000, function()
      return vim.api.nvim_buf_get_name(0) == repo.cwd .. '/selected.txt'
    end))
    local displayed_buffer = vim.api.nvim_get_current_buf()
    local displayed_bytes = vim.api.nvim_buf_get_lines(displayed_buffer, 0, -1, false)
    local list_id = vim.fn.getqflist({ id = 0 }).id
    local path = storage.path(session.state.loaded.storage_path, session.state.loaded.identity)
    local checkpoint = vim.fn.readfile(path)[1]
    repo:write_file('another.txt', { 'new' })
    local result, candidate = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and candidate and #candidate.files == 2)
    change_selected(repo)
    assert(session:refresh(candidate))
    assert(vim.fn.getqflist({ id = list_id, items = 1 }).items[1].text:sub(1, 3) == '[x]')
    assert(#vim.fn.getqflist({ id = list_id, items = 1 }).items == 1)
    assert(vim.api.nvim_get_current_buf() == displayed_buffer)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(displayed_buffer, 0, -1, false), displayed_bytes))
    assert(vim.fn.readfile(path)[1] == checkpoint)
    assert(session:mark_selected(false))
    assert(rows()['stored:selected.txt'] == '[ ]')
    session:stop()
  end)
end

M.refresh_should_preserve_selection_and_checkpoint_when_selected_content_disappears = function()
  selected_failure_case(function(repo)
    assert(vim.fn.delete(repo.cwd .. '/selected.txt') == 0)
  end)
end

M.refresh_should_preserve_selection_and_checkpoint_when_selected_bytes_change_after_aggregate = function()
  selected_failure_case(function(repo)
    repo:write_file('selected.txt', { 'other' })
  end)
end

return M
