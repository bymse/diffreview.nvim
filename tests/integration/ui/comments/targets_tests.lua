local h = require('integration.ui.comments.helpers')
local M = {}

M.show_comments_should_clamp_only_stale_anchors_when_source_is_short_or_empty = function()
  for _, lines in ipairs({ { 'source', 'end' }, {} }) do
    h.with_ui(function(review_ui)
      review_ui:display_diff_side_by_side(
        { file_id = 'file', operation = 'added', current = h.models.snapshot('file', lines) },
        'vertical'
      )
      local buffer = h.pane(review_ui, lines[1] or '')
      local comments = {
        h.comment('stale body', 'current', 8, 12, 'stale'),
        h.comment('out of bounds', 'current', 1, 12),
        h.comment('missing side', 'old', 1, 1),
        h.comment('empty is not source', 'current', 1, 1, #lines == 0 and 'open' or 'resolved'),
      }
      local before = vim.deepcopy(comments)
      assert(review_ui:show_comments('file', comments))
      local blocks = h.blocks(buffer)
      assert(#blocks == 1 and blocks[1].row == math.max(#lines - 1, 0))
      assert(vim.deep_equal(blocks[1].text, { 'Stale: current lines 8-12', 'stale body' }))
      assert(vim.deep_equal(comments, before))
    end)
  end
end

M.show_comments_should_reject_missing_or_lost_panes_without_clearing_projection = function()
  h.with_ui(function(review_ui)
    local diff = h.models.modified({ 'old' }, { 'current' })
    local ok, err = review_ui:show_comments('file', {})
    assert(not ok and err and #err > 0)
    review_ui:display_diff_side_by_side(diff, 'vertical')
    local old, old_win = h.pane(review_ui, 'old')
    local current = h.pane(review_ui, 'current')
    assert(review_ui:show_comments('file', { h.comment('keep', 'current', 1, 1) }))
    ok, err = review_ui:show_comments('wrong', {})
    assert(not ok and err and #err > 0 and #h.blocks(current) == 1)
    local replacement = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(old_win, replacement)
    ok, err = review_ui:show_comments('file', {})
    assert(not ok and err and #err > 0 and #h.blocks(current) == 1)
    assert(#h.blocks(replacement) == 0 and #h.blocks(old) == 0)
    vim.api.nvim_buf_delete(replacement, { force = true })
    review_ui:refresh_selected_diff(diff, 'vertical')
    assert(review_ui:show_comments('file', {}))
  end)
end

M.display_diff_side_by_side_should_reject_invalid_identity_when_model_file_id_is_missing_or_invalid = function()
  h.with_ui(function(review_ui)
    for _, file_id in ipairs({ '', false, 42, {} }) do
      local diff = h.models.modified({ 'a' }, { 'b' })
      diff.file_id = file_id
      assert(not pcall(review_ui.display_diff_side_by_side, review_ui, diff, 'vertical'))
    end
    local diff = h.models.modified({ 'a' }, { 'b' })
    diff.file_id = nil
    assert(not pcall(review_ui.display_diff_side_by_side, review_ui, diff, 'vertical'))
  end)
end

return M
