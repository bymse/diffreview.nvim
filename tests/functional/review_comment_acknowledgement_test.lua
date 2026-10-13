local review = require('helpers.functional_review')
local M = {}

local function stale_review(run, replacement)
  review.with_stale_comment_review(run, function(repo)
    repo:write_file('file.txt', replacement or { 'one', 'replacement', 'changed' })
  end)
end

M.review_comment_should_acknowledge_fixed_range_when_unchanged_editor_is_written_and_closed = function()
  stale_review(function(_, saved, original)
    local buffer = vim.api.nvim_get_current_buf()
    assert(not vim.bo[buffer].modified)
    assert(vim.deep_equal(review.comment_editor_preview(), {
      'stored:file.txt:2-3',
      '2: replacement',
      '3: changed',
    }))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { original.body }))
    vim.cmd('wq')
    assert(vim.wait(2000, function()
      return saved().comments[1].status == 'open'
    end))
    local record = saved().comments[1]
    assert(record.id == original.id and record.body == original.body)
    assert(record.start_line == 2 and record.end_line == 3)
    assert(record.anchor_hash == vim.fn.sha256('replacement\nchanged'))
    assert(#vim.fn.win_findbuf(buffer) == 0)
    vim.cmd('ReviewRefresh')
    vim.wait(200)
    assert(vim.deep_equal(saved().comments[1], record))
    vim.cmd('ReviewStop')
    vim.cmd('ReviewStart HEAD')
    review.wait_for_list(1)
    assert(vim.deep_equal(saved().comments[1], record))
  end)
end

M.review_comment_should_keep_stale_metadata_when_range_is_unavailable = function()
  stale_review(function(_, saved, original)
    assert(vim.deep_equal(review.comment_editor_preview(), {
      'stored:file.txt:2-3',
      'Location unavailable; saving will not reopen a stale comment.',
    }))
    review.write_comment('still relevant', saved)
    local record = saved().comments[1]
    assert(record.status == 'stale' and record.anchor_hash == original.anchor_hash)
    assert(record.start_line == 2 and record.end_line == 3)
    review.close_comment_editor()
    review.comment_row(1)
    review.keys('d')
    assert(#saved().comments == 0)
  end, { 'shortened' })
end

M.review_comment_should_leave_stale_record_unchanged_when_editor_is_closed_without_write = function()
  stale_review(function(_, saved)
    local original = saved()
    review.close_comment_editor()
    assert(vim.deep_equal(saved(), original))
  end)
end

M.review_comment_should_preserve_draft_and_metadata_when_unchanged_wq_cannot_persist = function()
  stale_review(function(repo, saved)
    local original = saved()
    local buffer = vim.api.nvim_get_current_buf()
    local directory = repo.cwd .. '/.git/diffreview-nvim'
    local checkpoints = vim.fn.readdir(directory, function(name)
      return name:match('%.json$') and 1 or 0
    end)
    assert(#checkpoints == 1)
    local path = directory .. '/' .. checkpoints[1]
    local raw = vim.fn.readfile(path)
    assert(vim.fn.delete(path) == 0 and vim.fn.mkdir(path) == 1)
    pcall(function()
      vim.cmd('wq')
    end)
    vim.wait(20)
    assert(vim.api.nvim_buf_is_valid(buffer) and #vim.fn.win_findbuf(buffer) == 1)
    assert(vim.bo[buffer].modified)
    assert(vim.fn.delete(path, 'd') == 0 and vim.fn.writefile(raw, path) == 0)
    assert(vim.deep_equal(saved(), original))
    vim.cmd('wq')
    assert(saved().comments[1].status == 'open')
  end)
end

M.review_comment_should_preserve_resolution_when_resolved_editor_is_written = function()
  stale_review(function(_, saved)
    review.close_comment_editor()
    review.comment_row(1)
    review.keys('r')
    local original = saved().comments[1]
    assert(original.status == 'resolved')
    review.keys('e')
    assert(vim.wait(2000, function()
      return vim.bo.buftype == 'acwrite'
    end))
    vim.cmd('wq')
    assert(vim.deep_equal(saved().comments[1], original))
  end)
end

M.review_comment_should_preserve_stale_record_when_code_changes_after_editor_opens = function()
  stale_review(function(repo, saved)
    local original = saved()
    local buffer = vim.api.nvim_get_current_buf()
    repo:write_file('file.txt', { 'different comparison' })
    pcall(function()
      vim.cmd('write')
    end)
    vim.wait(200)
    assert(vim.deep_equal(saved(), original))
    assert(vim.api.nvim_buf_is_valid(buffer))
    vim.cmd('close!')
    assert(vim.wait(2000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end))
  end)
end

M.review_comment_should_remove_attachment_command_and_mapping_when_setup_is_complete = function()
  review.with_comment_review(function(_, saved)
    assert(vim.fn.exists(':ReviewCommentAttach') == 0)
    vim.cmd('ReviewComment')
    review.write_comment('note', saved)
    review.close_comment_editor()
    vim.cmd('ReviewComments')
    review.comment_row(1)
    assert(vim.fn.maparg('a', 'n', false, true).buffer ~= 1)
  end)
end

return M
