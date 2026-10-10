local functional_review = require('helpers.functional_review')
local diffreview = require('diffreview')
local diffs = require('diffreview.diffs')
local storage = require('diffreview.storage')

local M = {}

local function wait_for_refreshed_diff(current_content)
  assert(
    vim.wait(2000, function()
      local windows = vim.api.nvim_tabpage_list_wins(0)
      if #windows ~= 2 then
        return false
      end
      local right = vim.api.nvim_get_current_win()
      local left = windows[1] == right and windows[2] or windows[1]
      return vim.api.nvim_win_get_position(left)[2] < vim.api.nvim_win_get_position(right)[2]
        and vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(left), 0, -1, false), { 'base' })
        and vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(right), 0, -1, false), {
          current_content,
        })
        and vim.wo[left].diff
        and vim.wo[right].diff
    end),
    'expected refreshed selected file in a two-pane diff'
  )
end

M.refresh_should_unview_changed_file_and_restore_checkpoint_when_change_returns = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    return { from = 'HEAD' }
  end, function(repo)
    local id = functional_review.wait_for_list(1)
    functional_review.select_path(id, 'file.txt')
    functional_review.wait_for_two_sided_current(repo, 'file.txt', 'base', 'first')
    vim.cmd('ReviewMarkViewed')
    assert(vim.fn.getqflist({ id = id, items = 1 }).items[1].text:sub(1, 3) == '[x]')

    repo:write_file('file.txt', { 'second' })
    vim.cmd('ReviewRefresh')
    assert(
      vim.wait(2000, function()
        return vim.fn.getqflist({ id = id, items = 1 }).items[1].text:sub(1, 3) == '[ ]'
          and vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'second' })
      end),
      'expected changed selected diff to become unviewed on refresh'
    )
    wait_for_refreshed_diff('second')

    repo:write_file('file.txt', { 'first' })
    vim.cmd('ReviewRefresh')
    assert(
      vim.wait(2000, function()
        return vim.fn.getqflist({ id = id, items = 1 }).items[1].text:sub(1, 3) == '[x]'
          and vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'first' })
      end),
      'expected original change to recover its viewed checkpoint'
    )
    wait_for_refreshed_diff('first')
  end)
end

M.refresh_should_show_new_file_and_keep_unchanged_file_viewed = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    return { from = 'HEAD' }
  end, function(repo)
    local id = functional_review.wait_for_list(1)
    functional_review.select_path(id, 'file.txt')
    functional_review.wait_for_two_sided_current(repo, 'file.txt', 'base', 'first')
    vim.cmd('ReviewMarkViewed')
    assert(vim.fn.getqflist({ id = id, items = 1 }).items[1].text:sub(1, 3) == '[x]')

    repo:write_file('new.txt', { 'new content' })
    vim.cmd('ReviewRefresh')
    assert(
      vim.wait(2000, function()
        local items = vim.fn.getqflist({ id = id, items = 1 }).items
        return #items == 2 and items[1].text == '[ ] -0/+1 new.txt' and items[2].text == '[x] -1/+1 file.txt'
      end),
      'expected new unviewed file before unchanged viewed file'
    )
    wait_for_refreshed_diff('first')
    vim.cmd('ReviewFiles')
    functional_review.select_path(id, 'new.txt')
    functional_review.wait_for_one_sided_current(repo, 'new.txt', 'new content')
  end)
end

M.refresh_should_redraw_selected_disk_bytes_without_touching_unsaved_buffer = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    return { from = 'HEAD' }
  end, function(repo)
    local id = functional_review.wait_for_list(1)
    functional_review.select_path(id, 'file.txt')
    assert(vim.wait(2000, function()
      return vim.api.nvim_buf_get_name(0) == repo.cwd .. '/file.txt'
    end))
    local user_buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(user_buffer, 0, -1, false, { 'unsaved' })
    repo:write_file('file.txt', { 'second' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'second' })
    end))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(user_buffer, 0, -1, false), { 'unsaved' }))
    assert(vim.bo[user_buffer].modified)
  end)
end

M.refresh_should_keep_caller_tab_and_open_list_when_selected_file_disappears = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    return { from = 'HEAD' }
  end, function(repo)
    local id = functional_review.wait_for_list(1)
    functional_review.select_path(id, 'file.txt')
    assert(vim.wait(2000, function()
      return vim.api.nvim_buf_get_name(0) == repo.cwd .. '/file.txt'
    end))
    local review_tab = vim.api.nvim_get_current_tabpage()
    vim.cmd('tabnew')
    local caller = vim.api.nvim_get_current_tabpage()
    vim.api.nvim_set_current_dir(vim.fn.fnamemodify(repo.cwd, ':h'))
    repo:write_file('file.txt', { 'base' })
    diffreview.refresh()
    assert(vim.wait(2000, function()
      return #vim.fn.getqflist({ id = id, items = 1 }).items == 0
    end))
    assert(vim.api.nvim_get_current_tabpage() == caller)
    assert(vim.api.nvim_tabpage_is_valid(review_tab))
    local found = false
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(review_tab)) do
      if vim.fn.getwininfo(window)[1].quickfix == 1 then
        found = true
      else
        assert(not vim.wo[window].diff, 'obsolete native diff should be disabled')
        assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)) ~= repo.cwd .. '/file.txt')
      end
    end
    assert(found, 'expected refreshed empty file drawer')
    vim.cmd('tabclose')
  end)
end

M.refresh_should_preserve_open_drawer_when_selected_file_remains = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    return { from = 'HEAD' }
  end, function(repo)
    local id = functional_review.wait_for_list(1)
    functional_review.select_path(id, 'file.txt')
    assert(vim.wait(2000, function()
      return vim.api.nvim_buf_get_name(0) == repo.cwd .. '/file.txt'
    end))
    vim.cmd('ReviewFiles')
    repo:write_file('file.txt', { 'second' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      local list = vim.fn.getqflist({ id = id, qfbufnr = 1, items = 1 })
      if not list.items[1] or list.items[1].text:sub(1, 3) ~= '[ ]' then
        return false
      end
      for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(window) == list.qfbufnr then
          return true
        end
      end
      return false
    end))
  end)
end

M.refresh_should_discard_pending_selection_when_refresh_is_requested = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    return { from = 'HEAD' }
  end, function(repo)
    local id = functional_review.wait_for_list(1)
    functional_review.select_path(id, 'file.txt')
    repo:write_file('file.txt', { 'base' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return #vim.fn.getqflist({ id = id, items = 1 }).items == 0
    end))
    vim.wait(300)
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)) ~= repo.cwd .. '/file.txt')
      assert(not vim.wo[window].diff)
    end
  end)
end

M.refresh_should_discard_pending_candidate_when_file_selection_follows = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    return { from = 'HEAD' }
  end, function(repo)
    local id = functional_review.wait_for_list(1)
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded)
    local path = storage.path(loaded.storage_path, loaded.identity)
    local previous = vim.fn.readfile(path)[1]
    repo:write_file('file.txt', { 'second' })
    vim.cmd('ReviewRefresh')
    functional_review.select_path(id, 'file.txt')
    assert(vim.wait(2000, function()
      return vim.api.nvim_buf_get_name(0) == repo.cwd .. '/file.txt'
    end))
    local buffer = vim.api.nvim_get_current_buf()
    vim.wait(300)
    assert(vim.api.nvim_get_current_buf() == buffer)
    assert(vim.api.nvim_buf_get_name(buffer) == repo.cwd .. '/file.txt')
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'second' }))
    assert(#vim.fn.getqflist({ id = id, items = 1 }).items == 1)
    assert(vim.fn.readfile(path)[1] == previous)
  end)
end

M.refresh_should_leave_state_unchanged_when_review_tab_closes_during_reload = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'first' })
    return { from = 'HEAD' }
  end, function(repo)
    local id = functional_review.wait_for_list(1)
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded)
    local path = storage.path(loaded.storage_path, loaded.identity)
    local previous = vim.fn.readfile(path)[1]
    repo:write_file('file.txt', { 'second' })
    vim.cmd('ReviewRefresh')
    vim.cmd('tabclose')
    assert(vim.wait(2000, function()
      return #vim.fn.getqflist({ id = id, items = 1 }).items == 0
    end))
    assert(vim.fn.readfile(path)[1] == previous)
  end)
end

return M
