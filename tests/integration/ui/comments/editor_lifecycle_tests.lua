local h = require('integration.ui.comments.helpers')
local M = {}

M.open_comment_editor_should_retain_captured_draft_when_source_and_origin_are_lost = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(
      { operation = 'added', current = h.models.snapshot('file', { 'original' }) },
      'vertical',
      nil,
      'file'
    )
    local _, origin = h.pane(ui, 'original')
    local calls = 0
    local target = { file_id = 'file', side = 'current', line_start = 1, line_end = 1 }
    local buffer = assert(ui:open_comment_editor({
      target = target,
      display_path = 'original-path',
      comment = h.comment('saved', 'current', 1, 1),
      on_save = function(request)
        calls = calls + 1
        assert(vim.deep_equal(request.target, target) and request.comment_id == 'saved' and request.text == 'draft')
        return { comment_id = 'saved' }
      end,
    }))
    local editor = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    vim.api.nvim_win_close(origin, false)
    ui:display_diff_side_by_side(
      { operation = 'added', current = h.models.snapshot('other', { 'replacement' }) },
      'vertical',
      nil,
      'other'
    )
    assert(vim.api.nvim_get_current_win() ~= editor)
    assert(vim.api.nvim_win_get_position(editor)[1] > vim.api.nvim_win_get_position(vim.api.nvim_get_current_win())[1])
    assert(vim.api.nvim_win_get_buf(editor) == buffer and vim.bo[buffer].modified)
    local repeated =
      { target = vim.deepcopy(target), display_path = false, comment = false, on_save = false, origin_window = -1 }
    assert(ui:open_comment_editor(repeated) == buffer)
    assert(vim.wo[editor].winbar:find('original-path', 1, true))
    assert(ui:write_comment_editor() and calls == 1)
    assert(ui:close_comment_editor())
    assert(not vim.api.nvim_win_is_valid(origin) and vim.api.nvim_get_current_buf() ~= buffer)
  end)
end

M.close_comment_editor_should_discard_without_saving_when_forced_or_cleaned_up = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current' }), 'vertical', nil, 'file')
    local source, origin = h.pane(ui, 'current')
    local calls = 0
    local options = {
      target = { file_id = 'file' },
      display_path = 'file',
      on_save = function()
        calls = calls + 1
        return { comment_id = 'id' }
      end,
    }
    local buffer = assert(ui:open_comment_editor(options))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    assert(not ui:close_comment_editor())
    assert(ui:close_comment_editor(true) and calls == 0)
    assert(
      vim.api.nvim_get_current_win() == origin and vim.api.nvim_win_get_buf(origin) == source and vim.wo[origin].diff
    )
    buffer = assert(ui:open_comment_editor(options))
    assert(not vim.bo[buffer].modified)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    ui:clear_selected_diff()
    assert(vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].modified)
    ui:cleanup()
    ui:cleanup()
    assert(not vim.api.nvim_buf_is_valid(buffer) and calls == 0)
  end)
end

M.open_comment_editor_should_reuse_hidden_draft_when_window_is_closed_without_discard = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side({ operation = 'added', current = h.models.snapshot('file') }, 'vertical', nil, 'file')
    local options = {
      target = { file_id = 'file' },
      display_path = 'file',
      on_save = function()
        return { comment_id = 'id' }
      end,
    }
    local buffer = assert(ui:open_comment_editor(options))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'hidden' })
    vim.api.nvim_win_hide(vim.api.nvim_get_current_win())
    assert(vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].modified)
    local repeated = { target = options.target }
    assert(ui:open_comment_editor(repeated) == buffer)
    assert(vim.api.nvim_get_current_buf() == buffer)
    vim.api.nvim_buf_delete(buffer, { force = true })
    assert(ui:close_comment_editor())
    local fresh = assert(ui:open_comment_editor(options))
    assert(fresh ~= buffer and not vim.bo[fresh].modified)
  end)
end

M.open_comment_editor_should_keep_editor_separate_when_first_diff_is_displayed_from_editor = function()
  h.with_ui(function(ui)
    ui:show_review_files({ { id = 'file', display_path = 'file', added_lines = 1, removed_lines = 0, viewed = false } })
    local buffer = assert(ui:open_comment_editor({
      target = { file_id = 'file' },
      display_path = 'file',
      on_save = function()
        return { comment_id = 'id' }
      end,
    }))
    local editor = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft before display' })
    ui:display_diff_side_by_side(
      { operation = 'added', current = h.models.snapshot('file', { 'source' }) },
      'vertical',
      true,
      'file'
    )
    assert(vim.api.nvim_get_current_win() ~= editor and vim.api.nvim_win_get_buf(editor) == buffer)
    assert(vim.bo[buffer].modified and ui:write_comment_editor())
  end)
end

M.open_comment_editor_should_replace_clean_draft_when_different_target_is_valid = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side({ operation = 'added', current = h.models.snapshot('file') }, 'vertical', nil, 'file')
    local _, origin = h.pane(ui, 'text')
    local calls = 0
    local options = {
      target = { file_id = 'file' },
      display_path = 'file',
      origin_window = origin,
      on_save = function()
        calls = calls + 1
        return { comment_id = 'id' }
      end,
    }
    local first = assert(ui:open_comment_editor(options))
    options.target = { file_id = 'another' }
    options.display_path = ''
    assert(not ui:open_comment_editor(options) and vim.api.nvim_buf_is_valid(first))
    options.display_path = 'another'
    local second = assert(ui:open_comment_editor(options))
    assert(second ~= first and not vim.api.nvim_buf_is_valid(first) and calls == 0)
    assert(ui:close_comment_editor() and vim.api.nvim_get_current_win() == origin)
  end)
end

return M
