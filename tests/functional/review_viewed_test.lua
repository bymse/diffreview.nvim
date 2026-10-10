local review = require('helpers.functional_review')

local M = {}

local function prepare(repo)
  repo:write_file('a.txt', { 'base a' })
  repo:write_file('b.txt', { 'base b' })
  repo:write_file('c.txt', { 'base c' })
  repo:add('.')
  repo:commit('base')
  repo:write_file('a.txt', { 'changed a' })
  repo:write_file('b.txt', { 'changed b' })
  repo:write_file('c.txt', { 'changed c' })
  return { from = 'HEAD' }
end

local function rows(id)
  local result = {}
  for _, item in ipairs(vim.fn.getqflist({ id = id, items = 1 }).items) do
    result[#result + 1] = item.text
  end
  return result
end

local function line(path, viewed)
  return (viewed and '[x]' or '[ ]') .. ' -1/+1 ' .. path
end

local function drawer(id)
  local buffer = vim.fn.getqflist({ id = id, qfbufnr = 1 }).qfbufnr
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(window) == buffer and vim.fn.getwininfo(window)[1].quickfix == 1 then
      return window
    end
  end
end

local function rejected(command)
  local before = vim.api.nvim_exec2('messages', { output = true }).output
  local ok = pcall(function()
    vim.cmd(command)
  end)
  assert(
    not ok or vim.api.nvim_exec2('messages', { output = true }).output ~= before,
    'expected rejected command: ' .. command
  )
end

M.viewed_mark_should_advance_and_persist_when_selected_diff_is_viewed = function()
  review.with_review(prepare, function(repo, options)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    assert(rows(id)[1] == line('a.txt', false), 'opening must not mark viewed')
    vim.cmd('ReviewMarkViewed')
    review.wait_for_two_sided_current(repo, 'b.txt', 'base b', 'changed b')
    assert(vim.deep_equal(rows(id), { line('b.txt', false), line('c.txt', false), line('a.txt', true) }))
    vim.cmd('ReviewStop')
    require('diffreview').start({ cwd = repo.cwd, from = options.from })
    local reopened = review.wait_for_list(3)
    assert(vim.deep_equal(rows(reopened), { line('b.txt', false), line('c.txt', false), line('a.txt', true) }))
  end)
end

M.viewed_mark_should_clear_checkpoint_when_selected_diff_is_unviewed_and_restarted = function()
  review.with_review(prepare, function(repo, options)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    vim.cmd('ReviewMarkViewed')
    review.wait_for_two_sided_current(repo, 'b.txt', 'base b', 'changed b')
    vim.cmd('ReviewFiles')
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    vim.cmd('ReviewMarkUnviewed')
    local unviewed = { line('a.txt', false), line('b.txt', false), line('c.txt', false) }
    assert(vim.deep_equal(rows(id), unviewed))
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')

    vim.cmd('ReviewStop')
    require('diffreview').start({ cwd = repo.cwd, from = options.from })
    local reopened = review.wait_for_list(3)
    assert(vim.deep_equal(rows(reopened), unviewed), 'expected explicitly unviewed file to remain unviewed')
  end)
end

M.viewed_mark_should_mark_owned_quickfix_row_without_advancing_selection = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    vim.cmd('ReviewFiles')
    vim.api.nvim_set_current_win(assert(drawer(id)))
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.cmd('ReviewMarkViewed')
    assert(vim.deep_equal(rows(id), { line('a.txt', false), line('c.txt', false), line('b.txt', true) }))
    vim.api.nvim_win_set_cursor(0, { 3, 0 })
    vim.cmd('ReviewMarkUnviewed')
    assert(vim.deep_equal(rows(id), { line('a.txt', false), line('b.txt', false), line('c.txt', false) }))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd('ReviewMarkViewed')
    assert(vim.deep_equal(rows(id), { line('b.txt', false), line('c.txt', false), line('a.txt', true) }))
    vim.cmd('ReviewFiles')
    assert(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())) == repo.cwd .. '/a.txt')
  end)
end

M.viewed_mark_should_reject_stale_quickfix_row_mapping_when_ids_are_remapped = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    vim.cmd('ReviewFiles')
    vim.api.nvim_set_current_win(assert(drawer(id)))
    local items = vim.fn.getqflist({ id = id, items = 1 }).items
    items[2].user_data.file_id = items[1].user_data.file_id
    assert(vim.fn.setqflist({}, 'u', { id = id, items = items }) == 0)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    rejected('ReviewMarkViewed')
    assert(vim.deep_equal(rows(id), { line('a.txt', false), line('b.txt', false), line('c.txt', false) }))
  end)
end

M.viewed_mark_should_use_selected_diff_when_another_review_window_is_focused = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    vim.cmd('enew')
    vim.cmd('ReviewMarkViewed')
    assert(vim.deep_equal(rows(id), { line('b.txt', false), line('c.txt', false), line('a.txt', true) }))
    review.wait_for_two_sided_current(repo, 'b.txt', 'base b', 'changed b')
  end)
end

M.viewed_mark_should_reject_foreign_context_and_inactive_review = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    local original = rows(id)
    vim.cmd('tabnew')
    rejected('ReviewFiles')
    rejected('ReviewMarkViewed')
    vim.cmd('tabclose')
    vim.fn.setqflist({}, ' ', { nr = '$', items = { { text = 'foreign' } } })
    vim.cmd('copen')
    rejected('ReviewMarkViewed')
    assert(vim.deep_equal(rows(id), original))
    vim.cmd('ReviewStop')
    rejected('ReviewFiles')
    rejected('ReviewMarkUnviewed')
  end)
end

M.viewed_mark_should_wrap_and_stay_when_no_unviewed_files_remain = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    vim.cmd('ReviewMarkViewed')
    review.wait_for_two_sided_current(repo, 'b.txt', 'base b', 'changed b')
    vim.cmd('ReviewMarkViewed')
    review.wait_for_two_sided_current(repo, 'c.txt', 'base c', 'changed c')
    vim.cmd('ReviewMarkViewed')
    review.wait_for_two_sided_current(repo, 'c.txt', 'base c', 'changed c')
    assert(vim.deep_equal(rows(id), { line('a.txt', true), line('b.txt', true), line('c.txt', true) }))

    vim.cmd('ReviewFiles')
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    vim.cmd('ReviewMarkUnviewed')
    assert(vim.deep_equal(rows(id), { line('a.txt', false), line('b.txt', true), line('c.txt', true) }))
    vim.cmd('ReviewFiles')
    review.select_path(id, 'c.txt')
    review.wait_for_two_sided_current(repo, 'c.txt', 'base c', 'changed c')
    vim.cmd('ReviewMarkViewed')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
  end)
end

M.viewed_mark_should_preserve_selected_diff_and_order_when_save_fails = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    local directory = repo.cwd .. '/.git/diffreview-nvim'
    assert(vim.uv.fs_chmod(directory, 0))
    local ok, err = xpcall(function()
      rejected('ReviewMarkViewed')
      assert(vim.deep_equal(rows(id), { line('a.txt', false), line('b.txt', false), line('c.txt', false) }))
      review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    end, debug.traceback)
    assert(vim.uv.fs_chmod(directory, 448))
    assert(ok, err)
    vim.cmd('ReviewMarkViewed')
    review.wait_for_two_sided_current(repo, 'b.txt', 'base b', 'changed b')
  end)
end

M.viewed_mark_should_reject_mark_when_error_view_replaces_selected_diff = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    assert(vim.fn.delete(repo.cwd .. '/b.txt') == 0)
    vim.cmd('ReviewFiles')
    review.select_path(id, 'b.txt')
    review.wait_for_information({ 'Content load error', 'Path: b.txt' })
    rejected('ReviewMarkViewed')
    assert(vim.deep_equal(rows(id), { line('a.txt', false), line('b.txt', false), line('c.txt', false) }))
  end)
end

M.viewed_mark_should_reject_location_list_window_without_marking_selected_diff = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    vim.fn.setloclist(0, { { text = 'foreign location' } }, 'r')
    vim.cmd('lopen')
    rejected('ReviewMarkViewed')
    assert(vim.deep_equal(rows(id), { line('a.txt', false), line('b.txt', false), line('c.txt', false) }))
    vim.cmd('lclose')
    vim.cmd('ReviewMarkViewed')
    review.wait_for_two_sided_current(repo, 'b.txt', 'base b', 'changed b')
  end)
end

M.viewed_mark_should_reject_selected_diff_mark_while_git_selection_is_pending = function()
  review.with_review(prepare, function(repo)
    local id = review.wait_for_list(3)
    review.select_path(id, 'a.txt')
    review.wait_for_two_sided_current(repo, 'a.txt', 'base a', 'changed a')
    local prior_window = vim.api.nvim_get_current_win()
    vim.cmd('ReviewFiles')
    local window = assert(drawer(id))
    vim.api.nvim_set_current_win(window)
    vim.api.nvim_win_set_cursor(window, { 2, 0 })
    local checked = false
    local rejected_pending = false
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'xt', false)
    vim.api.nvim_set_current_win(prior_window)
    vim.schedule(function()
      if not checked then
        local before = rows(id)
        local message = vim.api.nvim_exec2('messages', { output = true }).output
        local prior_visible = vim.api.nvim_get_current_win() == prior_window
          and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(prior_window)) == repo.cwd .. '/a.txt'
        local ok = pcall(function()
          vim.cmd('ReviewMarkViewed')
        end)
        rejected_pending = (not ok or vim.api.nvim_exec2('messages', { output = true }).output ~= message)
          and prior_visible
          and vim.deep_equal(rows(id), before)
        checked = true
      end
    end)
    assert(
      vim.wait(2000, function()
        return checked
      end),
      'expected pending selection callback'
    )
    assert(rejected_pending, 'pending selection must reject selected diff mark')
    assert(vim.deep_equal(rows(id), { line('a.txt', false), line('b.txt', false), line('c.txt', false) }))
    review.wait_for_two_sided_current(repo, 'b.txt', 'base b', 'changed b')
  end)
end

return M
