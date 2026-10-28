local h = require('integration.ui.comments.helpers')
local editor = require('diffreview.ui.comments.editor')
local M = {}

M.open_should_preserve_stale_target_when_existing_record_is_outside_displayed_source = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current' }), 'vertical')
    local comment = h.comment('body\n\n', 'old', 8, 9, 'stale')
    local buffer = assert(editor.open(ui, {
      target = comment.target,
      display_path = 'file',
      comment = comment,
      on_save = function(request)
        assert(request.target.line_start == 8 and request.target.line_end == 9 and request.comment_id == 'body\n\n')
        return { comment_id = 'saved' }
      end,
    }))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'body', '', '' }))
    comment.target.line_start = 1
    assert(editor.write(ui))
    assert(editor.close(ui))
    assert(
      not editor.open(ui, { target = { file_id = 'file' }, display_path = 'file', comment = comment, on_save = h.save })
    )
  end)
end

M.open_should_support_whole_file_record_when_quickfix_has_no_selected_diff = function()
  h.with_ui(function(ui)
    ui:show_review_files({ { id = 'file', display_path = 'file', added_lines = 1, removed_lines = 0, viewed = false } })
    local origin = vim.api.nvim_get_current_win()
    local entries = vim.fn.getqflist()
    local calls = 0
    local buffer = assert(editor.open(ui, {
      target = { file_id = 'file' },
      display_path = 'file',
      origin_window = origin,
      on_save = function(request)
        calls = calls + 1
        assert(request.target.side == nil and request.target.line_start == nil)
        return { comment_id = 'whole' }
      end,
    }))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'whole file' })
    assert(editor.write(ui) and calls == 1)
    assert(editor.close(ui))
    assert(vim.api.nvim_get_current_win() == origin and ui:files_open())
    assert(vim.deep_equal(entries, vim.fn.getqflist()))
  end)
end

M.open_should_reuse_captured_draft_when_original_source_and_origin_no_longer_exist = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(
      { file_id = 'file', operation = 'added', current = h.models.snapshot('original-path', { 'original' }) },
      'vertical'
    )
    local _, origin = h.pane(ui, 'original')
    local target = { file_id = 'file', side = 'current', line_start = 1, line_end = 1 }
    local calls = 0
    local buffer = assert(editor.open(ui, {
      target = target,
      display_path = 'original-path',
      comment = h.comment('saved', 'current', 1, 1),
      on_save = function(request)
        calls = calls + 1
        assert(vim.deep_equal(request.target, target) and request.comment_id == 'saved' and request.text == 'draft')
        return { comment_id = 'saved' }
      end,
    }))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    vim.api.nvim_win_close(origin, false)
    ui:display_diff_side_by_side(
      { file_id = 'other', operation = 'added', current = h.models.snapshot('other') },
      'vertical'
    )
    local repeated =
      { target = vim.deepcopy(target), display_path = false, comment = false, on_save = false, origin_window = -1 }
    assert(editor.open(ui, repeated) == buffer)
    assert(vim.wo[vim.api.nvim_get_current_win()].winbar:find('original-path', 1, true))
    assert(editor.write(ui) and calls == 1)
  end)
end

M.open_should_preserve_draft_and_source_recovery_when_first_diff_is_displayed_from_editor = function()
  h.with_ui(function(ui)
    ui:show_review_files({ { id = 'file', display_path = 'file', added_lines = 1, removed_lines = 0, viewed = false } })
    local buffer = assert(editor.open(ui, { target = { file_id = 'file' }, display_path = 'file', on_save = h.save }))
    local window = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft before display' })
    ui:display_diff_side_by_side(
      { file_id = 'file', operation = 'added', current = h.models.snapshot('file', { 'source' }) },
      'vertical',
      true
    )
    assert(vim.api.nvim_get_current_win() ~= window and vim.api.nvim_win_get_buf(window) == buffer)
    assert(vim.bo[buffer].modified and editor.write(ui))
  end)
end

return M
