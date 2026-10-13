local functional_review = require('helpers.functional_review')
local diffs = require('diffreview.diffs')
local storage = require('diffreview.storage')

local M = {}

local function prepare(repo)
  repo:write_file('file.txt', { 'base' })
  repo:add('file.txt')
  repo:commit('base')
  repo:write_file('file.txt', { 'changed' })
  repo:write_file('other.txt', { 'other' })
  return { from = 'HEAD' }
end

local function with_commands(run)
  functional_review.with_review(prepare, function(repo)
    vim.cmd('ReviewStart HEAD')
    local list = functional_review.wait_for_list(2)
    local _, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(loaded)
    run(repo, loaded, list)
  end, false)
end

local function saved_comments(loaded)
  return assert(storage.load(loaded.storage_path, loaded.identity)).comments
end

local function draft(body)
  local buffer = vim.api.nvim_get_current_buf()
  assert(vim.bo[buffer].buftype == 'acwrite')
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { body })
  return buffer
end

local function save(body)
  local buffer = draft(body)
  vim.cmd('write')
  assert(vim.wait(2000, function()
    return not vim.bo[buffer].modified
  end))
  return buffer
end

local function close_editor(buffer)
  vim.cmd('close!')
  assert(vim.wait(1000, function()
    return not vim.api.nvim_buf_is_valid(buffer)
  end))
end

local function focus_row(list, path)
  local entries = vim.fn.getqflist({ id = list, items = 1, qfbufnr = 1 })
  local row
  for index, item in ipairs(entries.items) do
    if item.text:sub(-#path) == path then
      row = index
    end
  end
  assert(row)
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.fn.getwininfo(window)[1].quickfix == 1 and vim.api.nvim_win_get_buf(window) == entries.qfbufnr then
      vim.api.nvim_set_current_win(window)
      vim.api.nvim_win_set_cursor(window, { row, 0 })
      return window
    end
  end
  error('expected review file drawer')
end

local function wait_for_path(repo, path, text)
  assert(
    vim.wait(2000, function()
      local buffer = vim.api.nvim_get_current_buf()
      return vim.api.nvim_buf_get_name(buffer) == repo.cwd .. '/' .. path
        and vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { text })
    end),
    'expected selected file presentation'
  )
end

M.review_comment_should_pin_id_and_delete_when_repeated_writes_and_blank_edits = function()
  with_commands(function(_, loaded, list)
    focus_row(list, 'file.txt')
    vim.cmd('ReviewComment')
    local buffer = save('')
    assert(#saved_comments(loaded) == 0)
    save('first')
    local record = saved_comments(loaded)[1]
    save('second')
    local records = saved_comments(loaded)
    assert(#records == 1 and records[1].id == record.id and records[1].body == 'second')
    save('  ')
    assert(#saved_comments(loaded) == 0)
    save('replacement')
    records = saved_comments(loaded)
    assert(#records == 1 and records[1].id ~= record.id)
    draft('discarded')
    close_editor(buffer)
    assert(saved_comments(loaded)[1].body == 'replacement')
  end)
end

M.review_comment_should_block_stop_refresh_and_replacement_when_dirty = function()
  with_commands(function(_, loaded, list)
    focus_row(list, 'file.txt')
    vim.cmd('ReviewComment')
    local tab = vim.api.nvim_get_current_tabpage()
    local editor_window = vim.api.nvim_get_current_win()
    local buffer = draft('uncommitted')
    local path = storage.path(loaded.storage_path, loaded.identity)
    local raw = vim.fn.readfile(path)[1]
    focus_row(list, 'other.txt')
    local buffers = vim.api.nvim_list_bufs()
    pcall(function()
      vim.cmd('ReviewComment')
    end)
    assert(vim.deep_equal(vim.api.nvim_list_bufs(), buffers))
    vim.api.nvim_set_current_win(editor_window)
    pcall(function()
      vim.cmd('ReviewRefresh')
    end)
    pcall(function()
      vim.cmd('ReviewStop')
    end)
    assert(vim.api.nvim_tabpage_is_valid(tab) and vim.fn.getqflist({ id = 0 }).id == list)
    assert(vim.fn.readfile(path)[1] == raw and vim.bo[buffer].modified)
    pcall(function()
      vim.cmd('tabclose')
    end)
    assert(vim.api.nvim_buf_is_valid(buffer))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'uncommitted' }))
    if vim.api.nvim_tabpage_is_valid(tab) then
      assert(vim.api.nvim_get_current_tabpage() == tab)
      vim.cmd('tabclose!')
    end
    assert(not vim.api.nvim_tabpage_is_valid(tab) and vim.bo[buffer].buflisted)
    vim.cmd('sbuffer ' .. buffer)
    pcall(function()
      vim.cmd('write')
    end)
    assert(vim.bo[buffer].modified and vim.fn.readfile(path)[1] == raw)
    close_editor(buffer)
  end)
end

M.review_comment_should_keep_failed_draft_when_checkpoint_cannot_be_replaced = function()
  with_commands(function(_, loaded, list)
    focus_row(list, 'file.txt')
    vim.cmd('ReviewComment')
    local tab = vim.api.nvim_get_current_tabpage()
    local path = storage.path(loaded.storage_path, loaded.identity)
    local original = vim.fn.readfile(path)[1]
    assert(vim.fn.delete(path) == 0)
    assert(vim.fn.mkdir(path) == 1)
    local buffer = draft('retry me')
    pcall(function()
      vim.cmd('write')
    end)
    assert(vim.bo[buffer].modified and vim.fn.isdirectory(path) == 1)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'retry me' }))
    assert(vim.fn.delete(path, 'd') == 0)
    assert(vim.fn.writefile({ original }, path) == 0)
    assert(#saved_comments(loaded) == 0)
    save('retry me')
    local records = saved_comments(loaded)
    assert(#records == 1 and records[1].body == 'retry me')
    vim.cmd('ReviewStop')
    assert(not vim.api.nvim_tabpage_is_valid(tab) and not vim.api.nvim_buf_is_valid(buffer))
  end)
end

M.review_comment_should_keep_location_and_guard_pending_save_when_selection_changes = function()
  with_commands(function(repo, loaded, list)
    functional_review.select_path(list, 'file.txt')
    functional_review.wait_for_two_sided_current(repo, 'file.txt', 'base', 'changed')
    local main = vim.api.nvim_get_current_win()
    local displayed = vim.api.nvim_get_current_buf()
    local tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('ReviewComment')
    local buffer = draft('pinned')
    local editor_window = vim.api.nvim_get_current_win()
    vim.cmd('ReviewFiles')
    functional_review.select_path(list, 'other.txt')
    wait_for_path(repo, 'other.txt', 'other')
    vim.api.nvim_set_current_win(editor_window)
    pcall(function()
      vim.cmd('write')
    end)
    assert(vim.bo[buffer].modified and #saved_comments(loaded) == 0)
    vim.cmd('ReviewFiles')
    functional_review.select_path(list, 'file.txt')
    wait_for_path(repo, 'file.txt', 'changed')
    assert(vim.api.nvim_win_get_buf(main) == displayed)
    vim.cmd('ReviewFiles')
    focus_row(list, 'other.txt')
    local original = assert(storage.load(loaded.storage_path, loaded.identity))
    repo:write_file('other.txt', { 'changed during pending save' })
    vim.api.nvim_set_current_win(editor_window)
    vim.cmd('setlocal nomodified')
    local guarded, guard_error
    vim.schedule(function()
      guarded, guard_error = xpcall(function()
        assert(vim.bo[buffer].modified and #saved_comments(loaded) == 0)
        pcall(function()
          vim.cmd('ReviewRefresh')
        end)
        pcall(function()
          vim.cmd('ReviewStop')
        end)
        assert(vim.api.nvim_tabpage_is_valid(tab))
        focus_row(list, 'other.txt')
        local buffers = vim.api.nvim_list_bufs()
        pcall(function()
          vim.cmd('ReviewComment')
        end)
        assert(vim.deep_equal(vim.api.nvim_list_bufs(), buffers))
        pcall(function()
          functional_review.select_path(list, 'other.txt')
        end)
      end, debug.traceback)
    end)
    pcall(function()
      vim.cmd('write')
    end)
    assert(guarded, guard_error)
    assert(vim.wait(2000, function()
      return #saved_comments(loaded) == 1
    end))
    assert(not vim.bo[buffer].modified)
    assert(vim.api.nvim_tabpage_is_valid(tab) and vim.api.nvim_win_get_buf(main) == displayed)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(displayed, 0, -1, false), { 'changed' }))
    local saved = assert(storage.load(loaded.storage_path, loaded.identity))
    assert(
      #saved.comments == 1 and saved.comments[1].file_id == 'stored:file.txt' and saved.comments[1].start_line ~= nil
    )
    assert(saved.comments[1].body == 'pinned')
    assert(vim.deep_equal(saved.files, original.files), 'pending refresh must not adopt changed worktree fingerprints')
    vim.api.nvim_set_current_win(editor_window)
  end)
end

M.review_comment_should_focus_same_target_and_replace_clean_editor_when_requested_location_changes = function()
  with_commands(function(_, loaded, list)
    local drawer = focus_row(list, 'file.txt')
    vim.cmd('ReviewComment')
    local buffer = draft('draft')
    vim.api.nvim_set_current_win(drawer)
    vim.cmd('ReviewComment')
    assert(vim.api.nvim_get_current_buf() == buffer)
    save('created')
    focus_row(list, 'other.txt')
    vim.cmd('ReviewComment')
    assert(not vim.api.nvim_buf_is_valid(buffer))
    buffer = vim.api.nvim_get_current_buf()
    assert(vim.bo[buffer].buftype == 'acwrite' and not vim.bo[buffer].modified)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { '' }))
    save('other note')
    local records = saved_comments(loaded)
    assert(#records == 2 and records[1].file_id == 'stored:file.txt' and records[2].file_id == 'new:other.txt')
  end)
end

M.review_comment_should_detach_draft_and_reject_old_owner_when_tab_is_force_closed_and_review_restarts = function()
  with_commands(function(_, loaded, list)
    focus_row(list, 'file.txt')
    vim.cmd('ReviewComment')
    local tab = vim.api.nvim_get_current_tabpage()
    local buffer = draft('detached draft')
    local path = storage.path(loaded.storage_path, loaded.identity)
    local raw = vim.fn.readfile(path)[1]
    vim.cmd('tabclose!')
    assert(not vim.api.nvim_tabpage_is_valid(tab) and vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].buflisted)
    assert(#vim.fn.getqflist({ id = list, items = 1 }).items == 0)
    -- Noncanonical JSON makes a redundant restart rewrite observable.
    raw = ' ' .. raw
    assert(vim.fn.writefile({ raw }, path) == 0)
    vim.cmd('ReviewStart HEAD')
    assert(vim.wait(2000, function()
      return vim.fn.getqflist({ id = 0 }).id ~= list
    end))
    functional_review.wait_for_list(2)
    local restarted_tab = vim.api.nvim_get_current_tabpage()
    assert(restarted_tab ~= tab and vim.fn.readfile(path)[1] == raw)
    vim.cmd('sbuffer ' .. buffer)
    pcall(function()
      vim.cmd('write')
    end)
    assert(
      vim.bo[buffer].modified and vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'detached draft' })
    )
    assert(vim.fn.readfile(path)[1] == raw)
    close_editor(buffer)
  end)
end

M.review_comment_should_persist_addition_before_closing_when_written_with_wq = function()
  with_commands(function(repo, loaded, list)
    functional_review.select_path(list, 'file.txt')
    functional_review.wait_for_two_sided_current(repo, 'file.txt', 'base', 'changed')
    vim.cmd('ReviewComment')
    local buffer = draft('written before closing')
    vim.cmd('wq')
    assert(#saved_comments(loaded) == 1 and saved_comments(loaded)[1].body == 'written before closing')
    assert(#vim.fn.win_findbuf(buffer) == 0)
  end)
end

M.review_comment_should_preserve_draft_when_clean_creation_outlives_its_comparison = function()
  with_commands(function(repo, loaded, list)
    focus_row(list, 'file.txt')
    vim.cmd('ReviewComment')
    local buffer = vim.api.nvim_get_current_buf()
    local editor_window = vim.api.nvim_get_current_win()
    assert(not vim.bo[buffer].modified)
    local path = storage.path(loaded.storage_path, loaded.identity)
    local original = vim.fn.readfile(path)[1]
    repo:write_file('other.txt', { 'new comparison' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return vim.fn.readfile(path)[1] ~= original
    end))
    local refreshed = vim.fn.readfile(path)[1]
    vim.api.nvim_set_current_win(editor_window)
    draft('old target')
    pcall(function()
      vim.cmd('write')
    end)
    assert(vim.bo[buffer].modified and vim.fn.readfile(path)[1] == refreshed and #saved_comments(loaded) == 0)
    close_editor(buffer)
  end)
end

M.review_comment_should_reject_creation_when_active_review_is_in_another_tab = function()
  with_commands(function(_, loaded, list)
    local review_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('tabnew')
    local foreign_tab = vim.api.nvim_get_current_tabpage()
    local path = storage.path(loaded.storage_path, loaded.identity)
    local raw = vim.fn.readfile(path)[1]
    local buffers = vim.api.nvim_list_bufs()
    pcall(function()
      vim.cmd('ReviewComment')
    end)
    assert(vim.api.nvim_get_current_tabpage() == foreign_tab and vim.deep_equal(vim.api.nvim_list_bufs(), buffers))
    assert(vim.fn.readfile(path)[1] == raw)
    vim.cmd('copen')
    assert(vim.fn.getqflist({ id = 0 }).id == list)
    buffers = vim.api.nvim_list_bufs()
    pcall(function()
      vim.cmd('ReviewComment')
    end)
    assert(vim.deep_equal(vim.api.nvim_list_bufs(), buffers) and vim.fn.readfile(path)[1] == raw)
    vim.cmd('tabclose')
    vim.api.nvim_set_current_tabpage(review_tab)
  end)
end

M.review_comment_should_reject_creation_when_owned_quickfix_rows_are_stale_or_remapped = function()
  with_commands(function(_, loaded, list)
    focus_row(list, 'file.txt')
    local original = vim.fn.getqflist({ id = list, items = 1, context = 1 })
    local path = storage.path(loaded.storage_path, loaded.identity)
    local raw = vim.fn.readfile(path)[1]
    for _, items in ipairs({ { original.items[1] }, { original.items[2], original.items[1] } }) do
      assert(vim.fn.setqflist({}, 'r', { id = list, items = items }) == 0)
      assert(vim.fn.getqflist({ id = 0, context = 1 }).context == original.context)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local buffers = vim.api.nvim_list_bufs()
      pcall(function()
        vim.cmd('ReviewComment')
      end)
      assert(vim.deep_equal(vim.api.nvim_list_bufs(), buffers) and vim.fn.readfile(path)[1] == raw)
    end
    assert(vim.fn.setqflist({}, 'r', { id = list, items = original.items }) == 0)
    focus_row(list, 'file.txt')
    vim.cmd('ReviewComment')
    save('restored row')
    local records = saved_comments(loaded)
    assert(#records == 1 and records[1].file_id == 'stored:file.txt' and records[1].start_line == nil)
  end)
end

return M
