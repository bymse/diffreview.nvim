local helper = require('helpers.functional_comments')
local review = require('helpers.functional_review')
local M = {}

local function annotations(windows)
  local result = {}
  for _, window in ipairs(windows) do
    local buffer = vim.api.nvim_win_get_buf(window)
    for name, namespace in pairs(vim.api.nvim_get_namespaces()) do
      if name:match('^diffreview%.comments%.') then
        result[name .. ':' .. buffer] = vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true })
      end
    end
  end
  return result
end

M.review_comment_attach_should_reject_obsolete_completion_when_pending_source_is_canceled_or_reselected_during_git_read = function()
  for _, reselect in ipairs({ false, true }) do
    helper.with_review(function(repo, saved)
      local files = vim.fn.getqflist({ id = 0 }).id
      review.select_path(files, 'file.txt')
      review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
      local main = vim.api.nvim_get_current_win()
      local panes = vim.api.nvim_tabpage_list_wins(0)
      vim.cmd('2ReviewComment')
      helper.write('overlapping attachment', saved)
      helper.close_editor()
      repo:write_file('file.txt', { 'one', 'replacement', 'changed' })
      vim.cmd('ReviewRefresh')
      assert(vim.wait(2000, function()
        return saved().comments[1].stale
      end))
      local original = saved()
      vim.cmd('ReviewComments')
      local notes = helper.row(1)
      helper.keys('a')
      local file_items = vim.fn.getqflist({ id = files, items = 1 }).items
      local comment_items = vim.fn.getqflist({ id = notes, items = 1 }).items
      local marks = annotations(panes)
      vim.api.nvim_set_current_win(main)
      vim.cmd('1ReviewCommentAttach')
      assert(vim.deep_equal(saved(), original), 'text attachment must still be waiting for asynchronous Git content')
      vim.cmd('ReviewCommentAttach!')
      if reselect then
        helper.row(1)
        helper.keys('a')
      end
      assert(
        not vim.wait(500, function()
          return not vim.deep_equal(saved(), original)
        end),
        'obsolete completion must not save the canceled attachment, even after the same comment ID is reselected'
      )
      assert(vim.deep_equal(vim.fn.getqflist({ id = files, items = 1 }).items, file_items))
      assert(vim.deep_equal(vim.fn.getqflist({ id = notes, items = 1 }).items, comment_items))
      assert(vim.deep_equal(annotations(panes), marks))
      if not reselect then
        helper.row(1)
        helper.keys('a')
      end
      vim.api.nvim_set_current_win(main)
      vim.cmd('3ReviewCommentAttach')
      assert(vim.wait(2000, function()
        return not saved().comments[1].stale
      end))
      local record = saved().comments[1]
      assert(record.id == original.comments[1].id and record.body == original.comments[1].body)
      assert(record.resolved == original.comments[1].resolved)
      assert(record.side == 'current' and record.start_line == 3 and record.end_line == 3)
      assert(vim.fn.getqflist({ id = notes, items = 1 }).items[1].text:find('current:3%-3'))
      assert(not vim.deep_equal(annotations(panes), marks))
      assert(vim.fn.getqflist({ id = 0 }).id == notes)
    end)
  end
end

return M
