local h = require('integration.ui.comments.helpers')
local M = {}

M.show_comments_should_render_both_sides_and_preserve_source_when_layout_changes = function()
  for _, layout in ipairs({ 'vertical', 'horizontal' }) do
    h.with_ui(function(review_ui)
      review_ui:display_diff_side_by_side(
        h.models.modified({ 'old', 'same', 'end' }, { 'current', 'same', 'end' }),
        layout,
        nil,
        'file'
      )
      local old, old_win = h.pane(review_ui, 'old')
      local current, current_win = h.pane(review_ui, 'current')
      local axis = layout == 'vertical' and 2 or 1
      assert(vim.api.nvim_win_get_position(old_win)[axis] < vim.api.nvim_win_get_position(current_win)[axis])
      local comments = {
        h.comment('first\n\nlast\n', 'old', 2, 2),
        h.comment('range', 'current', 1, 3),
        h.comment('second', 'old', 2, 2),
        h.comment('hidden', 'current', 1, 1, 'resolved'),
      }
      local copy = vim.deepcopy(comments)
      assert(review_ui:show_comments('file', comments))
      local blocks = h.blocks(old)
      assert(#blocks == 1 and blocks[1].row == 1 and not blocks[1].above)
      assert(vim.deep_equal(blocks[1].text, { 'old line 2', 'first', '', 'last', '', 'old line 2', 'second' }))
      assert(vim.deep_equal(h.blocks(current)[1].text, { 'current lines 1-3', 'range' }))
      assert(h.blocks(current)[1].row == 2)
      assert(vim.deep_equal(vim.api.nvim_buf_get_lines(current, 0, -1, false), { 'current', 'same', 'end' }))
      assert(vim.deep_equal(comments, copy))
      assert(vim.wo[old_win].diff and vim.wo[current_win].diff)
      assert(review_ui:show_comments('file', comments))
      assert(#h.blocks(old) == 1)
      comments[1].text = 'changed by caller'
      assert(h.blocks(old)[1].text[2] == 'first')
      assert(review_ui:show_comments('file', {}))
      assert(#h.blocks(old) == 0 and #h.blocks(current) == 0)
      assert(review_ui:show_comments('file', comments))
      assert(review_ui:show_comments('file', { h.comment('resolved', nil, nil, nil, 'resolved') }))
      assert(#h.blocks(old) == 0 and #h.blocks(current) == 0)
      assert(review_ui:show_comments('file', {
        h.comment('main only', nil),
        h.comment('old file body', 'old'),
        h.comment('current file body', 'current'),
      }))
      assert(vim.deep_equal(h.blocks(old)[1].text, { 'old file', 'old file body' }))
      assert(vim.deep_equal(h.blocks(current)[1].text, { 'file', 'main only', 'current file', 'current file body' }))
      assert(h.blocks(old)[1].above and h.blocks(current)[1].above)
    end)
  end
end

M.show_comments_should_render_file_targets_once_when_main_is_source_or_information = function()
  local diffs = {
    { operation = 'deleted', old = h.models.snapshot('file', { 'deleted' }) },
    { operation = 'added', current = h.models.binary('file') },
    {
      operation = 'renamed',
      old = h.models.snapshot('before'),
      current = h.models.snapshot('after'),
      content_changed = false,
    },
  }
  for index, diff in ipairs(diffs) do
    h.with_ui(function(review_ui)
      review_ui:display_diff_side_by_side(diff, 'vertical', nil, 'file')
      local windows = vim.api.nvim_tabpage_list_wins(assert(review_ui.tabpage))
      assert(#windows == 1)
      local buffer = vim.api.nvim_win_get_buf(windows[1])
      assert(review_ui:show_comments('file', {
        h.comment('file feedback', nil),
        h.comment('old feedback', 'old'),
        h.comment('current feedback', 'current'),
        h.comment('information is not source', 'current', 1, 1, index == 2 and 'stale' or 'resolved'),
      }))
      local blocks = h.blocks(buffer)
      assert(#blocks == 1 and blocks[1].above and blocks[1].row == 0)
      local side_text = index == 1 and { 'old file', 'old feedback' }
        or index == 3 and { 'current file', 'current feedback' }
        or {}
      local expected = { 'file', 'file feedback' }
      vim.list_extend(expected, side_text)
      assert(vim.deep_equal(blocks[1].text, expected))
    end)
  end
end

return M
