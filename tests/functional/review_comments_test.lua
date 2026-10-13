local review = require('helpers.functional_review')
local M = {}

M.review_comments_should_navigate_edit_toggle_and_delete_when_native_rows_are_selected = function()
  review.with_comment_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    vim.cmd('ReviewComment')
    review.write_comment('file note', saved)
    review.close_comment_editor()
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    local main = vim.api.nvim_get_current_win()
    vim.cmd('2,3ReviewComment')
    review.write_comment('current range', saved)
    local current_buffer = vim.api.nvim_win_get_buf(main)
    local ranges = 0
    for name, namespace in pairs(vim.api.nvim_get_namespaces()) do
      if name:match('^diffreview%.comments%.') then
        local marks = vim.api.nvim_buf_get_extmarks(current_buffer, namespace, 0, -1, { details = true })
        for _, mark in ipairs(marks) do
          if mark[4].end_row then
            ranges = ranges + 1
            assert(mark[2] == 1 and mark[4].end_row == 3)
          end
        end
      end
    end
    assert(ranges == 1)
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if window ~= main and vim.api.nvim_win_get_buf(window) ~= vim.api.nvim_get_current_buf() then
        for name, namespace in pairs(vim.api.nvim_get_namespaces()) do
          if name:match('^diffreview%.comments%.') then
            assert(#vim.api.nvim_buf_get_extmarks(vim.api.nvim_win_get_buf(window), namespace, 0, -1, {}) == 0)
          end
        end
      end
    end
    review.close_comment_editor()
    vim.cmd('ReviewComments')
    local notes = review.comment_row(2)
    review.keys('<CR>')
    assert(vim.wait(2000, function()
      return vim.api.nvim_get_current_win() == main and vim.api.nvim_win_get_cursor(main)[1] == 2
    end))
    assert(saved().files[1].viewed_fingerprint == nil)
    vim.cmd('ReviewComments')
    review.comment_row(1)
    review.keys('<CR>')
    assert(vim.wait(2000, function()
      return vim.api.nvim_get_current_win() == main
    end))
    vim.cmd('ReviewComments')
    review.comment_row(2)
    review.keys('r')
    assert(saved().comments[2].status == 'resolved')
    review.keys('r')
    assert(vim.wait(2000, function()
      return saved().comments[2].status == 'open'
    end))
    review.keys('e')
    review.write_comment('edited', saved)
    assert(saved().comments[2].body == 'edited')
    review.close_comment_editor()
    review.comment_row(2)
    review.keys('d')
    assert(#saved().comments == 1)
    vim.cmd('ReviewFiles')
    assert(vim.fn.getqflist({ id = 0 }).id == files)
    vim.cmd('ReviewComments')
    assert(vim.fn.getqflist({ id = 0 }).id == notes)
    for _ = 1, 3 do
      vim.cmd('ReviewFiles')
      assert(vim.fn.getqflist({ id = 0 }).id == files)
      vim.cmd('ReviewComments')
      assert(vim.fn.getqflist({ id = 0 }).id == notes)
      local drawers = 0
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.fn.getwininfo(win)[1].quickfix == 1 then
          drawers = drawers + 1
        end
      end
      assert(drawers == 1)
    end
    vim.cmd('ReviewStop')
    vim.cmd('ReviewStart HEAD')
    review.wait_for_list(1)
    vim.cmd('ReviewComments')
    assert(vim.fn.getqflist({ items = 1 }).items[1].text:find('file note'))
  end)
end

return M
