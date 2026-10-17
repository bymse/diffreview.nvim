local h = require('integration.ui.comments.helpers')
local M = {}

M.open_comment_editor_should_validate_and_preserve_drafts_when_requests_change = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old', 'two' }, { 'current', 'two' }), 'vertical', nil, 'file')
    local source, origin = h.pane(ui, 'current')
    local options = {
      target = { file_id = 'file', side = 'current', line_start = 1, line_end = 2 },
      display_path = 'file.txt',
      on_save = function()
        return { comment_id = 'saved' }
      end,
    }
    local buffer = assert(ui:open_comment_editor(options))
    local editor = vim.api.nvim_get_current_win()
    assert(editor ~= origin and vim.api.nvim_win_get_buf(origin) == source)
    assert(vim.api.nvim_win_get_position(editor)[1] > vim.api.nvim_win_get_position(origin)[1])
    assert(not vim.wo[editor].diff and vim.wo[origin].diff)
    assert(vim.bo[buffer].buftype == 'acwrite' and not vim.bo[buffer].buflisted and not vim.bo[buffer].swapfile)
    assert(not vim.bo[buffer].modified and vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { '' }))
    assert(vim.wo[editor].winbar:find('file.txt', 1, true))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft', '' })
    local repeated = { target = vim.deepcopy(options.target) }
    assert(ui:open_comment_editor(repeated) == buffer)
    assert(
      not ui:open_comment_editor({ target = { file_id = 'other' }, display_path = 'other', on_save = options.on_save })
    )
    assert(not ui:close_comment_editor())
    for _, target in ipairs({
      { file_id = '' },
      { file_id = 'file', side = 'invalid' },
      { file_id = 'file', side = 'current', line_start = 1 },
      { file_id = 'file', side = 'current', line_start = 2, line_end = 1 },
    }) do
      local invalid = { target = target }
      local result, err = ui:open_comment_editor(invalid)
      assert(result == nil and type(err) == 'string' and err ~= '')
    end
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'draft', '' }))
    assert(ui:close_comment_editor(true))
    assert(not vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_get_current_win() == origin)
    options.target.line_end = 3
    assert(not ui:open_comment_editor(options))
    options.target.file_id = 'other'
    options.target.line_end = 1
    assert(not ui:open_comment_editor(options))
  end)
end

M.open_comment_editor_should_preserve_stale_body_when_original_target_is_outside_source = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current' }), 'vertical', nil, 'file')
    local comment = h.comment('body\n\n', 'old', 8, 9, 'stale')
    local buffer = assert(ui:open_comment_editor({
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
    assert(ui:write_comment_editor())
    assert(ui:close_comment_editor())
    assert(not ui:open_comment_editor({
      target = { file_id = 'file' },
      display_path = 'file',
      comment = comment,
      on_save = function()
        return {}
      end,
    }))
  end)
end

M.open_comment_editor_should_save_whole_file_when_quickfix_has_no_selected_diff = function()
  h.with_ui(function(ui)
    ui:show_review_files({ { id = 'file', display_path = 'file', added_lines = 1, removed_lines = 0, viewed = false } })
    local origin = vim.api.nvim_get_current_win()
    local entries = vim.fn.getqflist()
    local calls = 0
    local buffer = assert(ui:open_comment_editor({
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
    assert(ui:write_comment_editor() and calls == 1)
    assert(ui:close_comment_editor())
    assert(vim.api.nvim_get_current_win() == origin and ui:files_open())
    assert(vim.deep_equal(entries, vim.fn.getqflist()))
  end)
end

M.open_comment_editor_should_reject_non_source_rows_when_presentation_has_no_target_lines = function()
  h.with_ui(function(ui)
    for _, diff in ipairs({
      { operation = 'added', current = h.models.snapshot('file', {}) },
      { operation = 'added', current = h.models.binary('file') },
    }) do
      ui:display_diff_side_by_side(diff, 'vertical', nil, 'file')
      assert(not ui:open_comment_editor({
        target = { file_id = 'file', side = 'current', line_start = 1, line_end = 1 },
        display_path = 'file',
        on_save = function()
          return { comment_id = 'id' }
        end,
      }))
    end
  end)
end

M.open_comment_editor_should_accept_path_backed_lines_when_source_is_a_real_file = function()
  require('helpers.git_repo').with_repo(function(repo)
    repo:write_file('file', { 'path source', 'second' })
    repo:add('file')
    repo:commit('source')
    local borrowed
    h.with_ui(function(ui)
      ui:display_diff_side_by_side(
        { operation = 'added', current = h.models.path(repo.cwd .. '/file') },
        'vertical',
        nil,
        'file'
      )
      borrowed = h.pane(ui, 'path source')
      local options = {
        target = { file_id = 'file', side = 'current', line_start = 2, line_end = 2 },
        display_path = 'file',
        on_save = function(request)
          assert(request.target.line_start == 2 and request.target.side == 'current')
          return { comment_id = 'id' }
        end,
      }
      local buffer = assert(ui:open_comment_editor(options))
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'body' })
      assert(ui:write_comment_editor())
      assert(ui:close_comment_editor())
      options.target.line_start = 3
      options.target.line_end = 3
      assert(not ui:open_comment_editor(options))
    end)
    assert(vim.api.nvim_buf_is_valid(borrowed) and not vim.bo[borrowed].modified)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(borrowed, 0, -1, false), { 'path source', 'second' }))
  end)
end

return M
