local review = require('helpers.functional_review')
local M = {}

M.review_comment_attach_should_preserve_identity_and_retry_when_stale_source_is_pinned = function()
  review.with_comment_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    vim.cmd('2ReviewComment')
    review.write_comment('reattach me', saved)
    review.close_comment_editor()
    local id = saved().comments[1].id
    repo:write_file('file.txt', { 'one', 'replacement', 'changed' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return saved().comments[1].status == 'stale'
    end))
    vim.cmd('ReviewComments')
    review.comment_row(1)
    review.keys('a')
    vim.cmd('ReviewCommentAttach!')
    vim.cmd('ReviewFiles')
    review.select_path(files, 'file.txt')
    pcall(function()
      vim.cmd('ReviewCommentAttach')
    end)
    assert(saved().comments[1].status == 'stale')
    vim.cmd('ReviewComments')
    review.comment_row(1)
    review.keys('a')
    review.keys('<CR>')
    assert(vim.wait(2000, function()
      return vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].quickfix == 0
    end))
    local main = vim.api.nvim_get_current_win()
    local original = saved()
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if window ~= main then
        vim.api.nvim_set_current_win(window)
        pcall(function()
          vim.cmd('1,2ReviewCommentAttach')
        end)
        assert(vim.deep_equal(saved(), original))
      end
    end
    vim.api.nvim_set_current_win(main)
    local buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'unsaved mismatch' })
    pcall(function()
      vim.cmd('ReviewCommentAttach')
    end)
    vim.wait(100)
    assert(saved().comments[1].status == 'stale')
    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'one' })
    vim.bo[buffer].modified = false
    vim.cmd('1,2ReviewCommentAttach')
    assert(vim.wait(2000, function()
      return saved().comments[1].status ~= 'stale'
    end))
    local record = saved().comments[1]
    assert(record.id == id and record.body == 'reattach me' and record.status == 'open')
    assert(record.start_line == 1 and record.end_line == 2)
  end)
end

M.review_comment_attach_should_replace_cancel_and_invalidate_pinned_editor_when_file_note_is_completed = function()
  review.with_comment_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    for _, body in ipairs({ 'first', 'second' }) do
      vim.cmd('2ReviewComment')
      review.write_comment(body, saved)
      review.close_comment_editor()
    end
    repo:write_file('file.txt', { 'one', 'replacement', 'changed' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return saved().comments[1].status == 'stale'
    end))
    vim.cmd('ReviewComments')
    review.comment_row(1)
    review.keys('a')
    review.comment_row(2)
    review.keys('a')
    review.keys('e')
    local editor = vim.api.nvim_get_current_buf()
    vim.cmd('ReviewFiles')
    local list = vim.fn.getqflist({ id = files, qfbufnr = 1 })
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(win) == list.qfbufnr then
        vim.api.nvim_set_current_win(win)
      end
    end
    vim.cmd('ReviewCommentAttach')
    assert(
      saved().comments[1].status == 'stale'
        and saved().comments[2].status == 'open'
        and saved().comments[2].start_line == nil
    )
    assert(not vim.api.nvim_buf_is_valid(editor))
    vim.cmd('ReviewComments')
    review.comment_row(1)
    review.keys('a')
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return vim.fn.getqflist({ items = 1 }).items[1].text:find('stale') ~= nil
    end))
    vim.wait(200)
    vim.cmd('ReviewFiles')
    pcall(function()
      vim.cmd('ReviewCommentAttach')
    end)
    assert(saved().comments[1].status == 'stale')
    vim.cmd('ReviewComments')
    review.comment_row(1)
    review.keys('a')
    review.keys('d')
    vim.cmd('ReviewFiles')
    pcall(function()
      vim.cmd('ReviewCommentAttach')
    end)
    assert(#saved().comments == 1 and saved().comments[1].body == 'second')
  end)
end

return M
