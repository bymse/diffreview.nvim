local helper = require('helpers.functional_comments')
local review = require('helpers.functional_review')
local M = {}

M.review_comments_should_navigate_edit_toggle_and_delete_when_native_rows_are_selected = function()
  helper.with_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    vim.cmd('ReviewComment')
    helper.write('file note', saved)
    helper.close_editor()
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    local main = vim.api.nvim_get_current_win()
    local old = vim.api.nvim_tabpage_list_wins(0)[1]
    vim.api.nvim_set_current_win(old)
    vim.cmd('2,3ReviewComment')
    helper.write('old range', saved)
    local old_buffer = vim.api.nvim_win_get_buf(old)
    local ranges = 0
    for name, namespace in pairs(vim.api.nvim_get_namespaces()) do
      if name:match('^diffreview%.comments%.') then
        local marks = vim.api.nvim_buf_get_extmarks(old_buffer, namespace, 0, -1, { details = true })
        ranges = ranges + #marks
        if #marks > 0 then
          assert(marks[1][2] == 1 and marks[1][4].end_row == 3)
        end
      end
    end
    assert(ranges == 1)
    helper.close_editor()
    vim.cmd('ReviewComments')
    local notes = helper.row(2)
    helper.keys('<CR>')
    assert(vim.wait(2000, function()
      return vim.api.nvim_get_current_win() == old and vim.api.nvim_win_get_cursor(old)[1] == 2
    end))
    assert(saved().files[1].viewed_fingerprint == nil)
    vim.cmd('ReviewComments')
    helper.row(1)
    helper.keys('<CR>')
    assert(vim.wait(2000, function()
      return vim.api.nvim_get_current_win() == main
    end))
    vim.cmd('ReviewComments')
    helper.row(2)
    helper.keys('r')
    assert(saved().comments[2].resolved)
    helper.keys('r')
    assert(not saved().comments[2].resolved)
    helper.keys('e')
    helper.write('edited', saved)
    assert(saved().comments[2].body == 'edited')
    helper.close_editor()
    helper.row(2)
    helper.keys('d')
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
