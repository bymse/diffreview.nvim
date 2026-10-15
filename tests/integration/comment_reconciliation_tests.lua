local git_repo = require('helpers.git_repo')
local review = require('diffreview.review')
local storage = require('diffreview.storage')
local diffs = require('diffreview.diffs')

local M = {}
local id = 'stored:file.txt'
local base = { 'before', 'anchor', 'range', 'after', 'base' }
local current = { 'before', 'anchor', 'range', 'after', 'changed' }

local function start(session, repo)
  session:start({ cwd = repo.cwd, from = 'HEAD' })
  assert(vim.wait(2000, function()
    return session.state.kind == 'active'
  end))
end

local function select(session, file_id)
  session:select_file(file_id)
  assert(vim.wait(2000, function()
    return session.state.selection_request == nil
  end))
end

local function refresh(session, candidate)
  assert(session:refresh(candidate))
  assert(vim.wait(2000, function()
    return session.state.refresh_request == nil
  end))
end

local function with_review(run)
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', base)
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', current)
    repo:write_file('other.txt', { 'other' })
    local session = review.new({ layout = 'horizontal', view = 'side_by_side' })
    start(session, repo)
    select(session, id)
    local ok, err = xpcall(function()
      run(session, repo)
    end, debug.traceback)
    if session.state.kind ~= 'idle' then
      session:stop()
    end
    assert(ok, err)
  end)
end

local function text_note(session)
  return assert(session:add_comment({ file_id = id, start_line = 2, end_line = 3 }, 'text note'))
end

local function checkpoint(session)
  local loaded = session.state.loaded
  local path = storage.path(loaded.storage_path, loaded.identity)
  return path, vim.fn.readfile(path)[1]
end

M.refresh_should_keep_fixed_ranges_and_preserve_resolution_when_current_text_moves = function()
  with_review(function(session, repo)
    local new = text_note(session)
    assert(session:resolve_comment(new.comment_id))
    assert(session:mark_files({ id }, true))
    repo:write_file('file.txt', { 'prefix', 'before', 'anchor', 'range', 'after', 'base' })
    repo:add('file.txt')
    repo:commit('move baseline')
    repo:write_file('file.txt', { 'prefix', 'before', 'anchor', 'range', 'after', 'changed' })
    refresh(session)
    local records = session.state.progress.comments
    assert(#records == 1 and records[1].comment_id == new.comment_id)
    for _, record in ipairs(records) do
      assert(record.status == 'resolved' and record.start_line == 2 and record.end_line == 3)
      assert(record.anchor_hash == vim.fn.sha256('anchor\nrange'))
    end
    assert(records[1].status == 'resolved' and not session.state.loaded.files[1].viewed)
    session:stop()
    start(session, repo)
    assert(vim.deep_equal(session.state.progress.comments, records))
  end)
end

M.refresh_should_retain_fixed_location_when_range_changes_or_moves = function()
  with_review(function(session, repo)
    local note = text_note(session)
    for _, lines in ipairs({
      { 'before', 'edited', 'range', 'after', 'changed' },
      { 'prefix', 'before', 'anchor', 'range', 'after', 'changed' },
      { 'before' },
    }) do
      repo:write_file('file.txt', lines)
      refresh(session)
      local stale = vim.deepcopy(note)
      stale.status = 'stale'
      assert(vim.deep_equal(session.state.progress.comments[1], stale))
    end
    repo:write_file('file.txt', current)
    refresh(session)
    local attached = session.state.progress.comments[1]
    assert(attached.comment_id == note.comment_id and attached.status == 'open' and attached.start_line == 2)
  end)
end

M.reopen_comment_should_recheck_anchor_when_resolved_text_changes_or_disappears = function()
  with_review(function(session, repo)
    local note = text_note(session)
    assert(session:resolve_comment(note.comment_id).status == 'resolved')
    repo:write_file('file.txt', { 'before', 'replacement', 'range', 'after', 'changed' })
    refresh(session)
    assert(session.state.progress.comments[1].status == 'resolved')
    session:stop()
    start(session, repo)
    assert(session.state.progress.comments[1].status == 'resolved')
    select(session, 'new:other.txt')
    assert(session:reopen_comment(note.comment_id).status == 'stale')
    assert(session:resolve_comment(note.comment_id).status == 'resolved')
    repo:write_file('file.txt', base)
    refresh(session)
    assert(session.state.progress.comments[1].status == 'resolved')
    assert(session:reopen_comment(note.comment_id).status == 'stale')
    repo:write_file('file.txt', current)
    refresh(session)
    assert(session.state.progress.comments[1].status == 'open')
    assert(session:resolve_comment(note.comment_id).status == 'resolved')
    local reopened = assert(session:reopen_comment(note.comment_id))
    assert(reopened.status == 'open' and reopened.start_line == 2 and reopened.comment_id == note.comment_id)
  end)
end

M.reopen_comment_should_recheck_identity_when_resolved_file_note_disappears = function()
  with_review(function(session, repo)
    local note = assert(session:add_comment({ file_id = 'new:other.txt' }, 'file note'))
    assert(session:resolve_comment(note.comment_id).status == 'resolved')
    assert(vim.fn.delete(repo.cwd .. '/other.txt') == 0)
    refresh(session)
    assert(session.state.progress.comments[1].status == 'resolved')
    assert(session:reopen_comment(note.comment_id).status == 'stale')
    repo:write_file('other.txt', { 'returned' })
    refresh(session)
    assert(session.state.progress.comments[1].status == 'open')
  end)
end

M.reopen_comment_should_preserve_resolved_checkpoint_when_comparison_snapshot_changed = function()
  with_review(function(session, repo)
    local note = text_note(session)
    assert(session:resolve_comment(note.comment_id))
    local path, raw = checkpoint(session)
    repo:write_file('file.txt', { 'changed outside the comparison' })
    local result, err = session:reopen_comment(note.comment_id)
    assert(result == nil and err ~= nil)
    assert(vim.fn.readfile(path)[1] == raw)
    assert(session.state.progress.comments[1].status == 'resolved')
    assert(session:edit_comment(note.comment_id, 'still editable').status == 'resolved')
  end)
end

M.start_should_retain_comment_only_reviews_and_reconcile_notes_when_file_identity_returns = function()
  with_review(function(session, repo)
    local text = text_note(session)
    local file = assert(session:add_comment({ file_id = id }, 'file note'))
    assert(session:resolve_comment(file.comment_id))
    repo:write_file('file.txt', base)
    assert(vim.fn.delete(repo.cwd .. '/other.txt') == 0)
    refresh(session)
    assert(#session.state.loaded.files == 0)
    assert(
      session.state.progress.comments[1].status == 'stale' and session.state.progress.comments[2].status == 'resolved'
    )
    session:stop()
    start(session, repo)
    assert(#session.state.loaded.files == 0 and #session.state.progress.comments == 2)
    repo:write_file('file.txt', current)
    refresh(session)
    local records = session.state.progress.comments
    assert(records[1].comment_id == text.comment_id and records[1].status == 'open')
    assert(records[2].comment_id == file.comment_id and records[2].status == 'resolved')
    repo:run_git({ 'mv', 'file.txt', 'renamed.txt' })
    refresh(session)
    assert(session.state.progress.files[1].display_path == 'renamed.txt')
    assert(session.state.progress.comments[2].status == 'resolved')
  end)
end

local function rejected_candidate(change)
  with_review(function(session, repo)
    text_note(session)
    select(session, 'new:other.txt')
    local progress, loaded = session.state.progress, session.state.loaded
    local buffer = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
    local list = vim.fn.getqflist({ id = 0, items = 1 })
    local path, raw = checkpoint(session)
    local result, candidate = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and candidate)
    change(repo)
    refresh(session, candidate)
    assert(session.state.progress == progress and session.state.loaded == loaded)
    assert(vim.fn.readfile(path)[1] == raw)
    assert(vim.deep_equal(vim.fn.getqflist({ id = list.id, items = 1 }).items, list.items))
    assert(vim.api.nvim_get_current_buf() == buffer)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), lines))
  end)
end

M.refresh_should_reject_unselected_snapshot_when_bytes_change_after_aggregate = function()
  rejected_candidate(function(repo)
    repo:write_file('file.txt', { 'changed after aggregate' })
  end)
end

M.refresh_should_reject_entire_candidate_when_unselected_content_read_fails = function()
  rejected_candidate(function(repo)
    assert(vim.fn.delete(repo.cwd .. '/file.txt') == 0)
  end)
end

M.refresh_should_stale_text_but_keep_file_notes_when_side_vanishes_or_becomes_binary = function()
  with_review(function(session, repo)
    local note = text_note(session)
    local file = assert(session:add_comment({ file_id = id }, 'file note'))
    assert(vim.fn.delete(repo.cwd .. '/file.txt') == 0)
    refresh(session)
    assert(session.state.progress.comments[1].status == 'stale')
    assert(session.state.progress.comments[2].status == 'open')
    local descriptor = assert(vim.uv.fs_open(repo.cwd .. '/file.txt', 'w', 420))
    assert(vim.uv.fs_write(descriptor, 'a\0b', 0) == 3)
    assert(vim.uv.fs_close(descriptor))
    refresh(session)
    assert(
      session.state.progress.comments[1].comment_id == note.comment_id
        and session.state.progress.comments[1].status == 'stale'
    )
    assert(
      session.state.progress.comments[2].comment_id == file.comment_id
        and session.state.progress.comments[2].status == 'open'
    )
  end)
end

M.refresh_should_not_save_or_adopt_when_stop_interrupts_preloaded_comment_loading = function()
  with_review(function(session, repo)
    text_note(session)
    local path, raw = checkpoint(session)
    local result, candidate = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and candidate)
    assert(session:refresh(candidate))
    session:stop()
    vim.wait(200)
    assert(session.state.kind == 'idle' and vim.fn.readfile(path)[1] == raw)
  end)
end

M.refresh_should_stale_text_and_keep_file_notes_when_text_becomes_submodule = function()
  with_review(function(session, repo)
    text_note(session)
    assert(session:add_comment({ file_id = id }, 'file note'))
    local oid = repo:current_sha()
    assert(vim.fn.delete(repo.cwd .. '/file.txt') == 0)
    assert(vim.fn.mkdir(repo.cwd .. '/file.txt') == 1)
    repo:run_git({ 'update-index', '--add', '--cacheinfo', '160000,' .. oid .. ',file.txt' })
    refresh(session)
    assert(session.state.loaded.entries_by_id[id].git_diff.new_mode == '160000')
    assert(session.state.progress.comments[1].status == 'stale' and session.state.progress.comments[2].status == 'open')
  end)
end

M.refresh_should_preserve_review_when_supported_blob_read_fails_in_submodule_candidate = function()
  with_review(function(session, repo)
    text_note(session)
    assert(session:add_comment({ file_id = id }, 'file note'))
    local progress, loaded = session.state.progress, session.state.loaded
    local path, raw = checkpoint(session)
    local list = vim.fn.getqflist({ id = 0, items = 1 })
    local buffer = vim.api.nvim_get_current_buf()
    local windows = vim.api.nvim_tabpage_list_wins(0)
    local presented = {}
    for _, window in ipairs(windows) do
      presented[window] = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false)
    end
    local oid = repo:current_sha()
    assert(vim.fn.delete(repo.cwd .. '/file.txt') == 0)
    assert(vim.fn.mkdir(repo.cwd .. '/file.txt') == 1)
    repo:run_git({ 'update-index', '--add', '--cacheinfo', '160000,' .. oid .. ',file.txt' })
    local result, candidate = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and candidate)
    local metadata = assert(candidate.entries_by_id[id].git_diff)
    assert(metadata.old_mode == '100644' and metadata.new_mode == '160000')
    local blob_oid = repo:run_git({ 'rev-parse', metadata.old_oid })
    local blob = repo.cwd .. '/.git/objects/' .. blob_oid:sub(1, 2) .. '/' .. blob_oid:sub(3)
    assert(vim.fn.delete(blob) == 0)
    refresh(session, candidate)
    assert(session.state.loaded == loaded and session.state.progress == progress)
    assert(vim.fn.readfile(path)[1] == raw)
    assert(vim.fn.getqflist({ id = 0 }).id == list.id)
    assert(vim.deep_equal(vim.fn.getqflist({ id = list.id, items = 1 }).items, list.items))
    assert(vim.api.nvim_get_current_buf() == buffer)
    assert(vim.deep_equal(vim.api.nvim_tabpage_list_wins(0), windows))
    for _, window in ipairs(windows) do
      assert(
        vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window), 0, -1, false), presented[window])
      )
    end
  end)
end

M.start_should_preserve_checkpoint_when_stop_cancels_saved_comment_restart = function()
  with_review(function(session, repo)
    text_note(session)
    local path, raw = checkpoint(session)
    session:stop()
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    session:stop()
    vim.wait(200)
    assert(session.state.kind == 'idle' and vim.fn.readfile(path)[1] == raw)
  end)
end

M.refresh_should_preserve_comments_and_presentation_when_checkpoint_replace_fails = function()
  with_review(function(session, repo)
    text_note(session)
    local progress = session.state.progress
    local buffer = vim.api.nvim_get_current_buf()
    local path, raw = checkpoint(session)
    repo:write_file('file.txt', { 'prefix', 'before', 'anchor', 'range', 'after', 'changed' })
    assert(vim.fn.delete(path) == 0 and vim.fn.mkdir(path) == 1)
    refresh(session)
    assert(session.state.progress == progress and vim.api.nvim_get_current_buf() == buffer)
    assert(vim.uv.fs_lstat(path).type == 'directory')
    assert(vim.fn.delete(path, 'd') == 0 and vim.fn.writefile({ raw }, path) == 0)
  end)
end

M.start_should_stale_fixed_git_snapshot_ranges_when_explicit_target_moves = function()
  with_review(function(session, repo)
    session:stop()
    repo:branch('baseline')
    repo:add('file.txt')
    repo:commit('target')
    repo:branch('target')
    repo:run_git({ 'checkout', '--quiet', 'baseline' })
    local options = { cwd = repo.cwd, from = 'HEAD', to = 'target' }
    session:start(options)
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    select(session, id)
    local new = text_note(session)
    session:stop()
    repo:run_git({ 'checkout', '--quiet', 'target' })
    repo:write_file('file.txt', { 'prefix', 'before', 'anchor', 'range', 'after', 'changed' })
    repo:add('file.txt')
    repo:commit('move target')
    repo:run_git({ 'checkout', '--quiet', 'baseline' })
    session:start(options)
    assert(vim.wait(2000, function()
      return session.state.kind == 'active'
    end))
    local records = session.state.progress.comments
    assert(
      #records == 1
        and records[1].comment_id == new.comment_id
        and records[1].start_line == 2
        and records[1].status == 'stale'
    )
  end)
end

M.refresh_should_ignore_neighbors_and_duplicate_text_when_fixed_range_matches = function()
  with_review(function(session, repo)
    local note = text_note(session)
    repo:write_file('file.txt', { 'different', 'anchor', 'range', 'neighbors', 'anchor', 'range' })
    refresh(session)
    local record = session.state.progress.comments[1]
    assert(
      record.comment_id == note.comment_id
        and record.start_line == 2
        and record.anchor_hash == note.anchor_hash
        and record.status == 'open'
    )
    repo:write_file('file.txt', { 'prefix', 'before', 'anchor', 'range', 'after', 'changed' })
    refresh(session)
    assert(
      session.state.progress.comments[1].status == 'stale'
        and session.state.progress.comments[1].anchor_hash == note.anchor_hash
    )
  end)
end

return M
