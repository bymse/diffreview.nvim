local git_repo = require('helpers.git_repo')
local review = require('diffreview.review')
local storage = require('diffreview.storage')
local async_operation = require('diffreview.async_operation')

local M = {}
local file_id = 'stored:file.txt'

local function start(session, repo)
  session:start({ cwd = repo.cwd, from = 'HEAD' })
  assert(vim.wait(2000, function()
    return session.state.kind == 'active'
  end))
end

local function select(session, id)
  session:select_file(id)
  assert(vim.wait(2000, function()
    return session.state.selection_request == nil
  end))
end

local function with_review(run)
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'before', 'same', 'old', 'after' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'before', 'same', 'new', 'after' })
    repo:write_file('other.txt', { 'other' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    local ok, err = xpcall(function()
      run(session, repo)
    end, debug.traceback)
    if session.state.kind ~= 'idle' then
      session:stop()
    end
    assert(ok, err)
  end)
end

local function checkpoint(session)
  local active = session.state
  local path = storage.path(active.loaded.storage_path, active.loaded.identity)
  return path, vim.fn.readfile(path)[1]
end

M.add_comment_should_reject_unsaved_display_when_capturing_range = function()
  with_review(function(session)
    select(session, file_id)
    assert(session:add_comment({ file_id = file_id }, 'file note'))
    local path, raw = checkpoint(session)
    local buffer = vim.api.nvim_get_current_buf()
    local original = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    vim.api.nvim_buf_set_lines(buffer, 1, 2, false, { 'unsaved' })
    local location = { file_id = file_id, start_line = 2, end_line = 2 }
    assert(not session:add_comment(location, 'misleading'))
    assert(vim.fn.readfile(path)[1] == raw)
    assert(#session.state.progress.comments == 1 and session.state.progress.comments[1].start_line == nil)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, original)
    vim.bo[buffer].modified = false
    assert(session:add_comment(location, 'valid').anchor_hash == vim.fn.sha256('same'))
  end)
end

M.add_comment_should_persist_management_and_viewed_progress_when_review_restarts = function()
  with_review(function(session, repo)
    assert(session:mark_files({ file_id }, true))
    select(session, file_id)
    local range = assert(session:add_comment({ file_id = file_id, start_line = 2, end_line = 3 }, 'range note'))
    assert(range.status == 'open')
    assert(range.anchor_hash == vim.fn.sha256('same\nnew'))
    local current = assert(session:add_comment({ file_id = file_id, start_line = 1, end_line = 1 }, 'current note'))
    assert(current.anchor_hash == vim.fn.sha256('before'))
    local note = assert(session:add_comment({ file_id = 'new:other.txt' }, 'file note'))
    assert(note.anchor_hash == nil and note.start_line == nil)
    assert(range.comment_id ~= current.comment_id and current.comment_id ~= note.comment_id)
    range.body = 'detached'
    range.anchor_hash = 'detached'
    local edited = assert(session:edit_comment(range.comment_id, 'edited'))
    assert(edited.anchor_hash == vim.fn.sha256('same\nnew'))
    edited.body = 'detached again'
    assert(session:resolve_comment(range.comment_id).status == 'resolved')
    assert(session:reopen_comment(range.comment_id).status == 'open')
    assert(session:resolve_comment(range.comment_id).status == 'resolved')
    local resolved = vim.deepcopy(session.state.progress.comments[1])
    assert(session:delete_comment(current.comment_id))
    local directory, identity = session.state.loaded.storage_path, session.state.loaded.identity
    session:stop()
    start(session, repo)
    local saved = assert(storage.load(directory, identity))
    assert(saved.version == 5 and #saved.comments == 2)
    assert(vim.deep_equal(saved.comments, session.state.progress.comments))
    assert(vim.deep_equal(saved.comments[1], resolved))
    assert(saved.comments[2].comment_id == note.comment_id and saved.comments[2].body == 'file note')
    assert(saved.files[1].viewed_fingerprint == saved.files[1].fingerprint)
    assert(session:refresh())
    assert(vim.wait(2000, function()
      return session.state.refresh_request == nil
    end))
    assert(vim.deep_equal(session.state.progress.comments, saved.comments))
  end)
end

M.comment_mutations_should_preserve_checkpoint_when_request_is_invalid = function()
  with_review(function(session)
    local note = assert(session:add_comment({ file_id = file_id }, 'note'))
    local path, raw = checkpoint(session)
    local original = vim.deepcopy(session.state.progress)
    local locations = {
      { file_id = 'missing' },
      { file_id = file_id, side = 'wrong', start_line = 1, end_line = 1 },
      { file_id = file_id, start_line = 0, end_line = 1 },
      { file_id = file_id, start_line = 3, end_line = 2 },
      { file_id = file_id, start_line = 1.5, end_line = 2 },
      { file_id = file_id, start_line = 1 },
      { file_id = file_id, side = 'old', start_line = 1, end_line = 1 },
      { file_id = file_id, end_line = 1 },
    }
    for _, location in ipairs(locations) do
      local result, err = session:add_comment(location, 'note')
      assert(result == nil and err ~= nil)
    end
    assert(not session:add_comment({ file_id = file_id, start_line = 1, end_line = 1 }, 'unselected'))
    select(session, file_id)
    assert(not session:add_comment({ file_id = file_id, start_line = 5, end_line = 5 }, 'outside'))
    assert(not session:add_comment({ file_id = 'new:other.txt', start_line = 1, end_line = 1 }, 'unselected'))
    for _, body in ipairs({ '', ' \n\t' }) do
      assert(not session:add_comment({ file_id = file_id }, body))
      assert(not session:edit_comment(note.comment_id, body))
    end
    assert(not session:edit_comment('missing', 'body'))
    assert(not session:delete_comment('missing'))
    assert(not session:resolve_comment('missing'))
    assert(not session:reopen_comment('missing'))
    assert(vim.deep_equal(original, session.state.progress) and vim.fn.readfile(path)[1] == raw)
    async_operation.cancel(session.state.operation)
    assert(not session:add_comment({ file_id = file_id }, 'canceled'))
    assert(not session:edit_comment(note.comment_id, 'canceled'))
    assert(not session:delete_comment(note.comment_id))
    assert(not session:resolve_comment(note.comment_id))
    assert(not session:reopen_comment(note.comment_id))
    session:stop()
    assert(not session:add_comment({ file_id = file_id }, 'inactive'))
    assert(not session:edit_comment(note.comment_id, 'inactive'))
    assert(not session:delete_comment(note.comment_id))
    assert(not session:resolve_comment(note.comment_id))
    assert(not session:reopen_comment(note.comment_id))
    assert(vim.fn.readfile(path)[1] == raw)
  end)
end

M.add_comment_should_reject_changed_worktree_and_pending_operations_without_saving = function()
  with_review(function(session, repo)
    select(session, file_id)
    local path, raw = checkpoint(session)
    repo:write_file('file.txt', { 'changed later' })
    assert(not session:add_comment({ file_id = file_id, start_line = 1, end_line = 1 }, 'mismatch'))
    assert(vim.fn.readfile(path)[1] == raw and #session.state.progress.comments == 0)
    session:select_file(file_id)
    assert(not session:add_comment({ file_id = file_id }, 'pending selection'))
    assert(vim.wait(2000, function()
      return session.state.selection_request == nil
    end))
    assert(session:refresh())
    assert(not session:add_comment({ file_id = file_id }, 'pending refresh'))
    session:stop()
    assert(vim.fn.readfile(path)[1] == raw)
  end)
end

M.add_comment_should_preserve_checkpoint_when_stop_interrupts_content_loading = function()
  with_review(function(session)
    select(session, file_id)
    local path, raw = checkpoint(session)
    local done, result, err
    local running = coroutine.create(function()
      result, err = session:add_comment({ file_id = file_id, start_line = 1, end_line = 1 }, 'canceled')
      done = true
    end)
    assert(coroutine.resume(running))
    session:stop()
    assert(vim.wait(2000, function()
      return done
    end))
    assert(result == nil and err ~= nil and vim.fn.readfile(path)[1] == raw)
  end)
end

M.comment_mutations_should_leave_active_state_when_atomic_replace_fails = function()
  with_review(function(session)
    local note = assert(session:add_comment({ file_id = file_id }, 'note'))
    local path, raw = checkpoint(session)
    local original = vim.deepcopy(session.state.progress)
    assert(vim.fn.delete(path) == 0 and vim.fn.mkdir(path) == 1)
    assert(not session:add_comment({ file_id = file_id }, 'failed'))
    assert(not session:edit_comment(note.comment_id, 'failed'))
    assert(not session:delete_comment(note.comment_id))
    assert(not session:resolve_comment(note.comment_id))
    assert(not session:reopen_comment(note.comment_id))
    assert(vim.deep_equal(original, session.state.progress))
    assert(vim.uv.fs_lstat(path).type == 'directory')
    assert(vim.fn.delete(path, 'd') == 0 and vim.fn.writefile({ raw }, path) == 0)
  end)
end

M.add_comment_should_reject_superseded_operation_when_content_loading_yields = function()
  with_review(function(session)
    select(session, file_id)
    local done, result, err
    local running = coroutine.create(function()
      result, err = session:add_comment({ file_id = file_id, start_line = 1, end_line = 1 }, 'superseded')
      done = true
    end)
    assert(coroutine.resume(running))
    local note = assert(session:add_comment({ file_id = file_id }, 'other mutation'))
    assert(session:delete_comment(note.comment_id))
    local path, raw = checkpoint(session)
    assert(vim.wait(2000, function()
      return done
    end))
    assert(result == nil and err ~= nil and vim.fn.readfile(path)[1] == raw)
    assert(#assert(storage.load(session.state.loaded.storage_path, session.state.loaded.identity)).comments == 0)
    done = false
    running = coroutine.create(function()
      result, err = session:add_comment({ file_id = file_id, start_line = 1, end_line = 1 }, 'switched')
      done = true
    end)
    assert(coroutine.resume(running))
    session:select_file('new:other.txt')
    assert(vim.wait(2000, function()
      return done and session.state.selection_request == nil
    end))
    assert(result == nil and err ~= nil and vim.fn.readfile(path)[1] == raw)
  end)
end

M.add_comment_should_allow_only_file_notes_when_selected_side_has_no_text = function()
  with_review(function(session, repo)
    select(session, 'new:other.txt')
    local path, raw = checkpoint(session)
    assert(
      not session:add_comment({ file_id = 'new:other.txt', side = 'old', start_line = 1, end_line = 1 }, 'absent side')
    )
    assert(vim.fn.readfile(path)[1] == raw)
    local descriptor = assert(vim.uv.fs_open(repo.cwd .. '/binary.bin', 'w', 420))
    assert(vim.uv.fs_write(descriptor, 'a\0b', 0) == 3)
    assert(vim.uv.fs_close(descriptor))
    assert(session:refresh())
    assert(vim.wait(2000, function()
      return session.state.refresh_request == nil
    end))
    select(session, 'new:binary.bin')
    local _, refreshed = checkpoint(session)
    assert(not session:add_comment({ file_id = 'new:binary.bin', start_line = 1, end_line = 1 }, 'binary text'))
    assert(vim.fn.readfile(path)[1] == refreshed)
    local note = assert(session:add_comment({ file_id = 'new:binary.bin' }, 'binary note'))
    assert(note.start_line == nil and note.file_id == 'new:binary.bin')
  end)
end

M.edit_comment_should_return_recoverable_error_when_storage_directory_is_not_a_directory = function()
  with_review(function(session)
    local note = assert(session:add_comment({ file_id = file_id }, 'note'))
    local directory = session.state.loaded.storage_path
    local path, raw = checkpoint(session)
    assert(vim.fn.rename(directory, directory .. '-backup') == 0)
    assert(vim.fn.writefile({ 'blocked' }, directory) == 0)
    local result, err = session:edit_comment(note.comment_id, 'failed')
    assert(result == nil and err ~= nil)
    assert(session.state.progress.comments[1].body == 'note')
    assert(vim.fn.readfile(directory)[1] == 'blocked')
    assert(vim.fn.delete(directory) == 0 and vim.fn.rename(directory .. '-backup', directory) == 0)
    assert(vim.fn.readfile(path)[1] == raw)
  end)
end

return M
