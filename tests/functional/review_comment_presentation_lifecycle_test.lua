local review = require('helpers.functional_review')
local M = {}

local function annotations(buffer)
  local result = {}
  if not vim.api.nvim_buf_is_valid(buffer) then
    return result
  end
  for name, namespace in pairs(vim.api.nvim_get_namespaces()) do
    if name:match('^diffreview%.comments%.') then
      vim.list_extend(result, vim.api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, { details = true }))
    end
  end
  return result
end

M.review_comments_should_follow_writes_refresh_and_tab_cleanup_without_editing_content = function()
  review.with_comment_review(function(repo, saved)
    local files = vim.fn.getqflist({ id = 0 }).id
    review.select_path(files, 'file.txt')
    review.wait_for_two_sided_current(repo, 'file.txt', { 'one', 'anchor', 'three' }, { 'one', 'anchor', 'changed' })
    local buffer = vim.api.nvim_get_current_buf()
    local main = vim.api.nvim_get_current_win()
    vim.cmd('2ReviewComment')
    review.write_comment('visible body', saved)
    assert(#annotations(buffer) == 1 and annotations(buffer)[1][2] == 1)
    review.write_comment('updated body', saved)
    assert(annotations(buffer)[1][4].virt_text[1][1]:find('updated body'))
    review.close_comment_editor()
    vim.cmd('ReviewComments')
    review.comment_row(1)
    review.keys('r')
    assert(annotations(buffer)[1][4].virt_text[1][1]:find('resolved'))
    repo:write_file('file.txt', { 'one', 'replacement', 'changed' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return saved().comments[1].stale
    end))
    assert(vim.fn.getqflist({ title = 1 }).title == 'Diff Review Comments')
    local previous = buffer
    buffer = vim.api.nvim_win_get_buf(main)
    if previous ~= buffer then
      assert(#annotations(previous) == 0)
    end
    local marks = annotations(buffer)
    assert(#marks == 1 and marks[1][2] == 0 and marks[1][4].virt_text[1][1]:find('stale file note'))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'one', 'replacement', 'changed' }))
    vim.cmd('tabclose!')
    assert(#annotations(buffer) == 0)
  end)
end

M.review_comments_should_open_from_closed_drawer_when_refresh_and_restart_have_only_saved_comments = function()
  review.with_comment_review(function(repo, saved)
    vim.cmd('ReviewComment')
    review.write_comment('retained note', saved)
    review.close_comment_editor()
    local original = saved().comments[1].id
    vim.cmd('ReviewFiles')
    repo:write_file('file.txt', { 'one', 'anchor', 'three' })
    vim.cmd('ReviewRefresh')
    assert(vim.wait(2000, function()
      return vim.fn.getqflist({ title = 1 }).title == 'Diff Review Comments' and saved().comments[1].stale
    end))
    local notes = review.comment_row(1)
    review.keys('<CR>')
    assert(vim.bo.buftype == 'quickfix')
    review.keys('e')
    review.write_comment('still editable', saved)
    review.close_comment_editor()
    vim.cmd('ReviewStop')
    vim.cmd('ReviewStart HEAD')
    assert(vim.wait(2000, function()
      local list = vim.fn.getqflist({ title = 1, id = 0, items = 1 })
      return list.id ~= notes and list.title == 'Diff Review Comments' and #list.items == 1
    end))
    review.comment_row(1)
    assert(saved().comments[1].id == original and saved().comments[1].body == 'still editable')
  end)
end

return M
