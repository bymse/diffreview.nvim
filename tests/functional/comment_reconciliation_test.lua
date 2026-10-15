local functional_review = require('helpers.functional_review')
local diffs = require('diffreview.diffs')
local review_progress = require('diffreview.review_progress')
local storage = require('diffreview.storage')

local M = {}
local base = { 'before', 'anchor', 'range', 'after', 'base' }
local current = { 'before', 'anchor', 'range', 'after', 'changed' }

local function wait_for_comments(loaded, expected)
  assert(
    vim.wait(2000, function()
      local saved = storage.load(loaded.storage_path, loaded.identity)
      return saved ~= nil and vim.deep_equal(saved.comments, expected)
    end),
    'expected reconciled comments in the saved checkpoint'
  )
end

M.review_commands_should_preserve_fixed_comments_when_text_moves_disappears_and_returns = function()
  functional_review.with_review(function(repo)
    repo:write_file('file.txt', base)
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', current)
    return { from = 'HEAD' }
  end, function(repo)
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded)
    local progress = review_progress.reconcile(nil, loaded)
    progress.comments[1] = {
      comment_id = 'current-saved-note',
      file_id = 'stored:file.txt',
      body = 'current saved body',
      status = 'open',
      start_line = 2,
      end_line = 3,
      anchor_hash = vim.fn.sha256('anchor\nrange'),
    }
    progress.comments[#progress.comments + 1] = {
      comment_id = 'saved-file-note',
      file_id = 'stored:file.txt',
      body = 'saved file body',
      status = 'open',
    }
    assert(storage.save(loaded.storage_path, progress))
    local expected = vim.deepcopy(progress.comments)
    local moved_base = { 'prefix', 'before', 'anchor', 'range', 'after', 'base' }
    local moved_current = { 'prefix', 'before', 'anchor', 'range', 'after', 'changed' }
    repo:write_file('file.txt', moved_base)
    repo:add('file.txt')
    repo:commit('move baseline')
    repo:write_file('file.txt', moved_current)
    expected[1].status = 'stale'
    vim.cmd('ReviewStart HEAD')
    local list = functional_review.wait_for_list(1)
    wait_for_comments(loaded, expected)
    local review_tab = vim.api.nvim_get_current_tabpage()
    functional_review.select_path(list, 'file.txt')
    functional_review.wait_for_two_sided_current(repo, 'file.txt', moved_base, moved_current)
    local main_window = vim.api.nvim_get_current_win()

    local refreshed = { 'extra', 'prefix', 'before', 'anchor', 'range', 'after', 'changed' }
    repo:write_file('file.txt', refreshed)
    vim.cmd('ReviewRefresh')
    wait_for_comments(loaded, expected)
    assert(#vim.fn.getqflist({ id = list, items = 1 }).items == 1)
    assert(
      vim.wait(2000, function()
        return vim.bo[vim.api.nvim_win_get_buf(main_window)].buftype == 'nofile'
          and vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(main_window), 0, -1, false), refreshed)
      end),
      'expected immutable current snapshot after refresh'
    )
    assert(#vim.api.nvim_tabpage_list_wins(review_tab) == 2)
    local snapshots = {}
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(review_tab)) do
      snapshots[#snapshots + 1] = vim.api.nvim_win_get_buf(window)
    end

    repo:write_file('file.txt', { 'extra', 'prefix', 'before', 'edited', 'range', 'after', 'changed' })
    expected[1].status = 'stale'
    vim.cmd('ReviewRefresh')
    wait_for_comments(loaded, expected)
    repo:write_file('file.txt', refreshed)
    expected[1].status = 'stale'
    vim.cmd('ReviewRefresh')
    wait_for_comments(loaded, expected)

    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(review_tab)) do
      assert(vim.fn.getwininfo(window)[1].quickfix == 0, 'expected closed drawer before empty refresh')
    end
    repo:write_file('file.txt', moved_base)
    for _, record in ipairs(expected) do
      record.status = 'stale'
    end
    vim.cmd('ReviewRefresh')
    wait_for_comments(loaded, expected)
    assert(vim.wait(2000, function()
      return #vim.fn.getqflist({ id = list, items = 1 }).items == 0
    end))
    assert(vim.api.nvim_tabpage_is_valid(review_tab))
    assert(vim.api.nvim_win_is_valid(main_window))
    assert(vim.api.nvim_win_get_tabpage(main_window) == review_tab)
    assert(not vim.wo[main_window].diff)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(main_window), 0, -1, false), { '' }))
    for _, buffer in ipairs(snapshots) do
      assert(not vim.api.nvim_buf_is_valid(buffer), 'expected obsolete snapshots to be deleted')
    end
    repo:write_file('file.txt', refreshed)
    for _, record in ipairs(expected) do
      record.status = 'open'
    end
    expected[1].status = 'stale'
    vim.cmd('ReviewRefresh')
    wait_for_comments(loaded, expected)
    assert(vim.fn.getqflist({ title = 1 }).title == 'Diff Review Comments')
    vim.cmd('ReviewFiles')
    assert(functional_review.wait_for_list(1) == list)
    assert(vim.api.nvim_tabpage_is_valid(review_tab) and vim.api.nvim_win_is_valid(main_window))
    vim.cmd('ReviewStop')
    assert(not vim.api.nvim_tabpage_is_valid(review_tab))
    repo:write_file('file.txt', moved_base)
    for _, record in ipairs(expected) do
      record.status = 'stale'
    end
    vim.cmd('ReviewStart HEAD')
    assert(
      vim.wait(2000, function()
        local restarted = vim.fn.getqflist({ id = 0, title = 1, items = 1 })
        return restarted.id ~= list and restarted.title == 'Diff Review Comments' and #restarted.items == #expected
      end),
      'expected a new active review list for the empty comparison'
    )
    list = vim.fn.getqflist({ id = 0 }).id
    wait_for_comments(loaded, expected)
    review_tab = vim.api.nvim_get_current_tabpage()
    assert(#vim.fn.getqflist({ id = list, items = 1 }).items == #expected)

    repo:write_file('file.txt', refreshed)
    for _, record in ipairs(expected) do
      record.status = 'open'
    end
    expected[1].status = 'stale'
    vim.cmd('ReviewRefresh')
    wait_for_comments(loaded, expected)
    assert(vim.fn.getqflist({ id = 0 }).id == list)
    vim.cmd('ReviewFiles')
    functional_review.wait_for_list(1)
    assert(vim.api.nvim_get_current_tabpage() == review_tab)
    local path = storage.path(loaded.storage_path, loaded.identity)
    local raw = vim.fn.readfile(path)[1]
    vim.cmd('ReviewStop')
    assert(not vim.api.nvim_tabpage_is_valid(review_tab))
    assert(#vim.fn.getqflist({ id = list, items = 1 }).items == 0)
    assert(vim.fn.readfile(path)[1] == raw)
  end, false)
end

return M
