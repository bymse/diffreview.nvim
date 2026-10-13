local review = require('helpers.functional_review')
local M = {}

local function unavailable_write(change)
  review.with_stale_comment_review(function(_, saved, original)
    assert(vim.deep_equal(review.comment_editor_preview(), {
      'stored:file.txt:2-3',
      'Location unavailable; saving will not reopen a stale comment.',
    }))
    review.write_comment('edited without a location', saved)
    local record = saved().comments[1]
    assert(record.id == original.id and record.file_id == original.file_id)
    assert(record.status == 'stale' and record.anchor_hash == original.anchor_hash)
    assert(record.start_line == original.start_line and record.end_line == original.end_line)
    review.close_comment_editor()
    review.comment_row(1)
    review.keys('d')
    assert(#saved().comments == 0)
  end, change)
end

M.review_comment_should_save_stale_body_when_file_identity_is_missing = function()
  unavailable_write(function(repo)
    repo:write_file('file.txt', { 'one', 'anchor', 'three' })
  end)
end

M.review_comment_should_save_stale_body_when_current_side_is_absent = function()
  unavailable_write(function(repo)
    assert(vim.fn.delete(repo.cwd .. '/file.txt') == 0)
  end)
end

M.review_comment_should_save_stale_body_when_current_content_is_binary = function()
  unavailable_write(function(repo)
    local descriptor = assert(vim.uv.fs_open(repo.cwd .. '/file.txt', 'w', 420))
    assert(vim.uv.fs_write(descriptor, 'a\0b', 0) == 3)
    assert(vim.uv.fs_close(descriptor))
  end)
end

M.review_comment_should_preserve_stale_checkpoint_and_draft_when_content_read_fails = function()
  review.with_stale_comment_review(function(repo, saved)
    local original = saved()
    local buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'unsaved body' })
    assert(vim.fn.delete(repo.cwd .. '/file.txt') == 0)
    pcall(function()
      vim.cmd('wq')
    end)
    vim.wait(20)
    assert(vim.deep_equal(saved(), original))
    assert(vim.bo[buffer].modified and #vim.fn.win_findbuf(buffer) == 1)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'unsaved body' }))
    vim.cmd('close!')
    assert(vim.wait(2000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end))
  end, function(repo)
    repo:write_file('file.txt', { 'one', 'replacement', 'changed' })
  end)
end

return M
