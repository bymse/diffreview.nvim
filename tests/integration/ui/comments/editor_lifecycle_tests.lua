local h = require('integration.ui.comments.helpers')
local M = {}

M.open_comment_editor_should_retain_captured_draft_when_source_and_origin_are_lost = function()
  local calls = 0
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(
      { file_id = 'file', operation = 'added', current = h.models.snapshot('original-path', { 'original' }) },
      'vertical'
    )
    local source, origin = h.pane(ui, 'original')
    local buffer = assert(ui:open_comment_editor())
    local editor = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    vim.api.nvim_win_close(origin, false)
    ui:display_diff_side_by_side(
      { file_id = 'other', operation = 'added', current = h.models.snapshot('other', { 'replacement' }) },
      'vertical'
    )
    assert(vim.api.nvim_get_current_win() ~= editor)
    assert(vim.api.nvim_win_get_position(editor)[1] > vim.api.nvim_win_get_position(vim.api.nvim_get_current_win())[1])
    assert(vim.api.nvim_win_get_buf(editor) == buffer and vim.bo[buffer].modified)
    assert(not ui:open_comment_editor(source))
    assert(vim.wo[editor].winbar:find('original-path', 1, true))
    assert(ui:write_comment_editor() and calls == 1)
    assert(ui:close_comment_editor())
    assert(not vim.api.nvim_win_is_valid(origin) and vim.api.nvim_get_current_buf() ~= buffer)
  end, {
    get_comment = function()
      return h.comment('saved', 'current', 1, 1)
    end,
    on_comment_save = function(request)
      calls = calls + 1
      assert(vim.deep_equal(request.target, { file_id = 'file', side = 'current', line_start = 1, line_end = 1 }))
      assert(request.comment_id == 'saved' and request.text == 'draft')
      return { comment_id = 'saved' }
    end,
  })
end

M.close_comment_editor_should_discard_without_saving_when_forced_or_cleaned_up = function()
  local calls = 0
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current' }), 'vertical')
    local source, origin = h.pane(ui, 'current')
    local buffer = assert(ui:open_comment_editor())
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    assert(not ui:close_comment_editor())
    assert(ui:close_comment_editor(true) and calls == 0)
    assert(
      vim.api.nvim_get_current_win() == origin and vim.api.nvim_win_get_buf(origin) == source and vim.wo[origin].diff
    )
    buffer = assert(ui:open_comment_editor())
    assert(not vim.bo[buffer].modified)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    ui:clear_selected_diff()
    assert(vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].modified)
    ui:cleanup()
    ui:cleanup()
    assert(not vim.api.nvim_buf_is_valid(buffer) and calls == 0)
  end, {
    on_comment_save = function()
      calls = calls + 1
      return { comment_id = 'id' }
    end,
  })
end

M.open_comment_editor_should_reuse_hidden_draft_when_window_is_closed_without_discard = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(
      { file_id = 'file', operation = 'added', current = h.models.snapshot('file') },
      'vertical'
    )
    local source = h.pane(ui, 'text')
    local buffer = assert(ui:open_comment_editor())
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'hidden' })
    vim.api.nvim_win_hide(vim.api.nvim_get_current_win())
    assert(vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].modified)
    assert(ui:open_comment_editor(source) == buffer)
    assert(vim.api.nvim_get_current_buf() == buffer)
    vim.api.nvim_buf_delete(buffer, { force = true })
    assert(ui:close_comment_editor())
    local fresh = assert(ui:open_comment_editor(source))
    assert(fresh ~= buffer and not vim.bo[fresh].modified)
  end)
end

M.open_comment_editor_should_replace_clean_draft_when_different_range_is_valid = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(
      { file_id = 'file', operation = 'added', current = h.models.snapshot('file', { 'first', 'second' }) },
      'vertical'
    )
    local source, origin = h.pane(ui, 'first')
    local first = assert(ui:open_comment_editor(source, 1, 1))
    assert(not ui:open_comment_editor(source, 3, 3) and vim.api.nvim_buf_is_valid(first))
    local second = assert(ui:open_comment_editor(source, 2, 2))
    assert(second ~= first and not vim.api.nvim_buf_is_valid(first))
    assert(ui:close_comment_editor() and vim.api.nvim_get_current_win() == origin)
  end)
end

return M
