local helper = require('helpers.functional_comments')
local review = require('helpers.functional_review')
local M = {}

M.review_comments_should_preserve_checkpoint_when_rows_or_ownership_are_replaced = function()
  helper.with_review(function(_, saved)
    vim.cmd('ReviewComment')
    helper.write('protected', saved)
    helper.close_editor()
    vim.cmd('ReviewComments')
    local id = helper.row(1)
    local original = saved()
    local list = vim.fn.getqflist({ id = id, items = 1 })
    list.items[1].user_data.comment_id = 'unknown'
    vim.fn.setqflist({}, 'r', { id = id, items = list.items })
    for _, key in ipairs({ '<CR>', 'e', 'd', 'r', 'a' }) do
      helper.keys(key)
    end
    assert(vim.deep_equal(saved(), original))
    assert(vim.bo.buftype == 'quickfix')
    vim.cmd('ReviewComments')
    vim.cmd('ReviewComments')
    helper.row(1)
    vim.fn.setqflist({}, ' ', { title = 'foreign', context = { plugin = 'foreign' }, items = { { text = 'other' } } })
    for _, key in ipairs({ '<CR>', 'e', 'd', 'r', 'a' }) do
      helper.keys(key)
    end
    assert(vim.deep_equal(saved(), original))
    assert(vim.fn.getqflist({ items = 1 }).items[1].text == 'other')
  end)
end

M.review_comments_should_keep_draft_and_invalidate_clean_editor_only_after_successful_delete = function()
  helper.with_review(function(repo, saved)
    vim.cmd('ReviewComment')
    helper.write('protected', saved)
    helper.close_editor()
    vim.cmd('ReviewComments')
    helper.row(1)
    helper.keys('e')
    local editor = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(editor, 0, -1, false, { 'dirty draft' })
    helper.row(1)
    local original = saved()
    for _, key in ipairs({ 'e', 'd', 'r', 'a' }) do
      helper.keys(key)
    end
    pcall(function()
      vim.cmd('ReviewCommentAttach!')
    end)
    assert(vim.deep_equal(saved(), original) and vim.bo[editor].modified)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(editor, 0, -1, false), { 'dirty draft' }))
    local window = vim.fn.win_findbuf(editor)[1]
    vim.api.nvim_set_current_win(window)
    helper.write('saved draft', saved)
    helper.row(1)
    local directory = repo.cwd .. '/.git/diffreview-nvim'
    local checkpoints = vim.fn.readdir(directory, function(name)
      return name:match('%.json$') and 1 or 0
    end)
    assert(#checkpoints == 1)
    local path = directory .. '/' .. checkpoints[1]
    local raw = vim.fn.readfile(path)
    assert(vim.fn.delete(path) == 0 and vim.fn.mkdir(path) == 1)
    local projection = vim.fn.getqflist({ id = 0, items = 1 }).items
    helper.keys('d')
    assert(vim.api.nvim_buf_is_valid(editor))
    assert(vim.deep_equal(vim.fn.getqflist({ id = 0, items = 1 }).items, projection))
    assert(vim.fn.delete(path, 'd') == 0 and vim.fn.writefile(raw, path) == 0)
    helper.keys('d')
    assert(#saved().comments == 0 and not vim.api.nvim_buf_is_valid(editor))
  end)
end

M.review_comments_should_reject_native_keys_and_attachment_when_text_write_is_pending = function()
  helper.with_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    vim.cmd('ReviewComment')
    helper.write('existing', saved)
    helper.close_editor()
    local original = saved().comments[1]
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    vim.cmd('2ReviewComment')
    local editor = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(editor, 0, -1, false, { 'pending text' })
    vim.bo[editor].modified = false
    vim.cmd('write')
    assert(#saved().comments == 1)
    pcall(function()
      vim.cmd('ReviewCommentAttach!')
    end)
    vim.cmd('ReviewComments')
    helper.row(1)
    for _, key in ipairs({ 'd', 'r', 'e', 'a', '<CR>' }) do
      helper.keys(key)
    end
    assert(vim.api.nvim_buf_is_valid(editor))
    assert(vim.wait(2000, function()
      return #saved().comments == 2
    end))
    assert(vim.deep_equal(saved().comments[1], original))
    assert(saved().comments[2].body == 'pending text')
  end)
end

return M
