local h = require('integration.ui.comments.helpers')
local M = {}

M.open_comment_editor_should_use_current_source_cursor_when_called_without_arguments = function()
  for _, layout in ipairs({ 'vertical', 'horizontal' }) do
    for _, side in ipairs({ 'old', 'current' }) do
      local requests = {}
      h.with_ui(function(ui)
        ui:display_diff_side_by_side(h.models.modified({ 'old', 'second' }, { 'current', 'second' }), layout)
        local source, origin = h.pane(ui, side)
        vim.api.nvim_set_current_win(origin)
        vim.api.nvim_win_set_cursor(origin, { 2, 0 })
        local buffer = assert(ui:open_comment_editor())
        local editor = vim.api.nvim_get_current_win()
        assert(editor ~= origin and vim.api.nvim_win_get_buf(origin) == source)
        assert(vim.api.nvim_win_get_position(editor)[1] > vim.api.nvim_win_get_position(origin)[1])
        assert(not vim.wo[editor].diff and vim.wo[origin].diff)
        assert(vim.bo[buffer].buftype == 'acwrite' and not vim.bo[buffer].buflisted and not vim.bo[buffer].swapfile)
        assert(not vim.bo[buffer].modified)
        assert(vim.wo[editor].winbar:find('file.txt', 1, true))
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'body' })
        assert(ui:write_comment_editor())
        assert(vim.deep_equal(requests[1].target, { file_id = 'file', side = side, line_start = 2, line_end = 2 }))
        assert(ui:close_comment_editor() and vim.api.nvim_get_current_win() == origin)
      end, {
        on_comment_save = function(request)
          table.insert(requests, request)
          return { comment_id = 'saved' }
        end,
      })
    end
  end
end

M.open_comment_editor_should_use_source_window_cursor_when_explicit_buffer_is_not_current = function()
  local requests = {}
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old', 'second' }, { 'current' }), 'vertical')
    local old, old_window = h.pane(ui, 'old')
    local _, current_window = h.pane(ui, 'current')
    vim.api.nvim_win_set_cursor(old_window, { 2, 0 })
    vim.api.nvim_set_current_win(current_window)
    local buffer = assert(ui:open_comment_editor(old))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'old source' })
    assert(ui:write_comment_editor())
    assert(requests[1].target.side == 'old' and requests[1].target.line_start == 2)
    assert(ui:close_comment_editor() and vim.api.nvim_get_current_win() == old_window)
  end, {
    on_comment_save = function(request)
      table.insert(requests, request)
      return { comment_id = 'saved' }
    end,
  })
end

M.open_comment_editor_should_preserve_draft_when_another_range_or_invalid_request_is_supplied = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old', 'second' }, { 'current', 'second' }), 'vertical')
    local source = h.pane(ui, 'current')
    local buffer = assert(ui:open_comment_editor(source, 1, 2))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft', '' })
    assert(ui:open_comment_editor(source, 1, 2) == buffer)
    assert(not ui:open_comment_editor(source, 1, 1))
    assert(not ui:close_comment_editor())
    for _, range in ipairs({ { 1 }, { 2, 1 }, { 0, 1 }, { 1.5, 2 }, { 1, 3 } }) do
      local result, err = ui:open_comment_editor(source, range[1], range[2])
      assert(result == nil and type(err) == 'string' and err ~= '')
    end
    ---@type any
    local invalid_buffer = { target = { file_id = 'file' } }
    assert(not ui:open_comment_editor(invalid_buffer))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'draft', '' }))
  end)
end

M.open_comment_editor_should_reject_non_source_origins_when_buffer_has_no_displayed_source = function()
  h.with_ui(function(ui)
    assert(not ui:open_comment_editor())
    ui:show_review_files({ { id = 'file', display_path = 'file', added_lines = 1, removed_lines = 0, viewed = false } })
    assert(not ui:open_comment_editor())
    for _, current in ipairs({ h.models.snapshot('file', {}), h.models.binary('file') }) do
      ui:display_diff_side_by_side({ file_id = 'file', operation = 'added', current = current }, 'vertical')
      assert(not ui:open_comment_editor())
    end
    ui:display_diff_side_by_side(
      { file_id = 'file', operation = 'added', current = h.models.snapshot('file') },
      'vertical'
    )
    local hidden = vim.api.nvim_create_buf(false, true)
    assert(not ui:open_comment_editor(hidden))
    vim.api.nvim_buf_delete(hidden, { force = true })
    assert(ui:open_comment_editor())
    assert(not ui:open_comment_editor())
  end)
end

M.open_comment_editor_should_use_deleted_version_path_when_primary_source_is_old = function()
  local requests = {}
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(
      { file_id = 'deleted', operation = 'deleted', old = h.models.snapshot('removed.txt', { 'old' }) },
      'vertical'
    )
    local buffer = assert(ui:open_comment_editor())
    assert(vim.wo[vim.api.nvim_get_current_win()].winbar:find('removed.txt', 1, true))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'deleted source' })
    assert(ui:write_comment_editor())
    assert(requests[1].target.file_id == 'deleted' and requests[1].target.side == 'old')
  end, {
    on_comment_save = function(request)
      table.insert(requests, request)
      return { comment_id = 'saved' }
    end,
  })
end

M.open_comment_editor_should_accept_live_path_backed_ranges_when_buffer_contains_unsaved_lines = function()
  require('helpers.git_repo').with_repo(function(repo)
    repo:write_file('file', { 'path source' })
    repo:add('file')
    repo:commit('source')
    h.with_ui(function(ui)
      ui:display_diff_side_by_side(
        { file_id = 'file', operation = 'added', current = h.models.path(repo.cwd .. '/file') },
        'vertical'
      )
      local source = h.pane(ui, 'path source')
      assert(not ui:open_comment_editor(source, 2, 2))
      vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'unsaved' })
      assert(ui:open_comment_editor(source, 2, 2))
      assert(ui:close_comment_editor())
      vim.bo[source].modified = false
    end)
  end)
end

return M
