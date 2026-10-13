local review = require('helpers.functional_review')
local M = {}

M.review_comment_should_show_selected_code_separately_when_new_editor_is_opened = function()
  review.with_comment_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    vim.cmd('2,3ReviewComment')
    assert(vim.deep_equal(review.comment_editor_preview(), {
      'stored:file.txt:2-3',
      '2: anchor',
      '3: changed',
    }))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { '' }))
    review.write_comment('only the body', saved)
    assert(saved().comments[1].body == 'only the body')
    review.close_comment_editor()
  end)
end

M.review_comment_should_reject_unseen_snapshot_when_unsaved_preview_is_restored_before_write = function()
  review.with_comment_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    local source = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(source, 1, 2, false, { 'unsaved preview' })
    vim.cmd('2ReviewComment')
    local buffer = vim.api.nvim_get_current_buf()
    assert(vim.deep_equal(review.comment_editor_preview(), { 'stored:file.txt:2-2', '2: unsaved preview' }))
    vim.api.nvim_buf_set_lines(source, 1, 2, false, { 'anchor' })
    vim.bo[source].modified = false
    local original = saved()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft for previewed code' })
    pcall(function()
      vim.cmd('wq')
    end)
    vim.wait(20)
    assert(vim.deep_equal(saved(), original))
    assert(vim.bo[buffer].modified and #vim.fn.win_findbuf(buffer) == 1)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'draft for previewed code' }))
    vim.cmd('close!')
    assert(vim.wait(2000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end))
  end)
end

M.review_comment_should_require_new_preview_when_existing_clean_editor_outlives_refresh = function()
  review.with_stale_comment_review(function(repo, saved)
    local buffer = vim.api.nvim_get_current_buf()
    assert(not vim.bo[buffer].modified)
    repo:write_file('file.txt', { 'one', 'latest', 'changed' })
    local original = saved()
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return not vim.deep_equal(saved().files, original.files)
    end))
    local refreshed = saved()
    vim.api.nvim_set_current_win(assert(vim.fn.win_findbuf(buffer)[1]))
    pcall(function()
      vim.cmd('wq')
    end)
    vim.wait(20)
    assert(vim.deep_equal(saved(), refreshed))
    assert(vim.bo[buffer].modified and #vim.fn.win_findbuf(buffer) == 1)
    vim.cmd('close!')
    assert(vim.wait(2000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end))
    review.comment_row(1)
    review.keys('e')
    assert(vim.wait(2000, function()
      return vim.bo.buftype == 'acwrite'
    end))
    assert(vim.deep_equal(review.comment_editor_preview(), { 'stored:file.txt:2-3', '2: latest', '3: changed' }))
    vim.cmd('wq')
    assert(saved().comments[1].status == 'open')
    assert(saved().comments[1].anchor_hash == vim.fn.sha256('latest\nchanged'))
  end, function(repo)
    repo:write_file('file.txt', { 'one', 'replacement', 'changed' })
  end)
end

return M
