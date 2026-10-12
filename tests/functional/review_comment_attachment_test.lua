local helper = require('helpers.functional_comments')
local review = require('helpers.functional_review')
local M = {}

M.review_comment_attach_should_preserve_identity_and_retry_when_stale_source_is_pinned = function()
  helper.with_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    vim.cmd('2ReviewComment')
    helper.write('reattach me', saved)
    helper.close_editor()
    local id = saved().comments[1].id
    repo:write_file('file.txt', { 'one', 'replacement', 'changed' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return saved().comments[1].stale
    end))
    vim.cmd('ReviewComments')
    helper.row(1)
    helper.keys('r')
    helper.keys('a')
    vim.cmd('ReviewCommentAttach!')
    vim.cmd('ReviewFiles')
    review.select_path(files, 'file.txt')
    pcall(function()
      vim.cmd('ReviewCommentAttach')
    end)
    assert(saved().comments[1].stale)
    vim.cmd('ReviewComments')
    helper.row(1)
    helper.keys('a')
    helper.keys('<CR>')
    assert(vim.wait(2000, function()
      return vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].quickfix == 0
    end))
    local buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'unsaved mismatch' })
    pcall(function()
      vim.cmd('ReviewCommentAttach')
    end)
    vim.wait(100)
    assert(saved().comments[1].stale)
    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'one' })
    vim.bo[buffer].modified = false
    vim.cmd('1,2ReviewCommentAttach')
    assert(vim.wait(2000, function()
      return not saved().comments[1].stale
    end))
    local record = saved().comments[1]
    assert(record.id == id and record.body == 'reattach me' and record.resolved)
    assert(record.side == 'current' and record.start_line == 1 and record.end_line == 2)
  end)
end

M.review_comment_attach_should_replace_cancel_and_invalidate_pinned_editor_when_file_note_is_completed = function()
  helper.with_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    for _, body in ipairs({ 'first', 'second' }) do
      vim.cmd('2ReviewComment')
      helper.write(body, saved)
      helper.close_editor()
    end
    repo:write_file('file.txt', { 'one', 'replacement', 'changed' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return saved().comments[1].stale
    end))
    vim.cmd('ReviewComments')
    helper.row(1)
    helper.keys('a')
    helper.row(2)
    helper.keys('a')
    helper.keys('e')
    local editor = vim.api.nvim_get_current_buf()
    vim.cmd('ReviewFiles')
    local list = vim.fn.getqflist({ id = files, qfbufnr = 1 })
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(win) == list.qfbufnr then
        vim.api.nvim_set_current_win(win)
      end
    end
    vim.cmd('ReviewCommentAttach')
    assert(saved().comments[1].stale and not saved().comments[2].stale and saved().comments[2].side == nil)
    assert(not vim.api.nvim_buf_is_valid(editor))
    vim.cmd('ReviewComments')
    helper.row(1)
    helper.keys('a')
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return vim.fn.getqflist({ items = 1 }).items[1].text:find('stale') ~= nil
    end))
    vim.wait(200)
    vim.cmd('ReviewFiles')
    pcall(function()
      vim.cmd('ReviewCommentAttach')
    end)
    assert(saved().comments[1].stale)
    vim.cmd('ReviewComments')
    helper.row(1)
    helper.keys('a')
    helper.keys('d')
    vim.cmd('ReviewFiles')
    pcall(function()
      vim.cmd('ReviewCommentAttach')
    end)
    assert(#saved().comments == 1 and saved().comments[1].body == 'second')
  end)
end

return M
