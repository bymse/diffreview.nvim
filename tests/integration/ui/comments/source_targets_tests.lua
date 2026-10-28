local h = require('integration.ui.comments.helpers')
local M = {}

M.resolve_comment_target_should_use_originating_pane_when_both_source_sides_are_displayed = function()
  for _, layout in ipairs({ 'vertical', 'horizontal' }) do
    h.with_ui(function(ui)
      ui:display_diff_side_by_side(h.models.modified({ 'old', 'second' }, { 'current', 'second' }), layout)
      for _, side in ipairs({ 'old', 'current' }) do
        local buffer, window = h.pane(ui, side)
        local target = assert(h.resolve_target(ui, buffer, window, 1, 2))
        assert(vim.deep_equal(target, { file_id = 'file', side = side, line_start = 1, line_end = 2 }))
        local whole = assert(h.resolve_target(ui, buffer, window))
        assert(vim.deep_equal(whole, { file_id = 'file' }))
      end
      local old = h.pane(ui, 'old')
      local _, current_window = h.pane(ui, 'current')
      assert(not h.resolve_target(ui, old, current_window, 1, 1))
    end)
  end
end

M.resolve_comment_target_should_preserve_old_role_when_deleted_source_is_primary = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(
      { file_id = 'file', operation = 'deleted', old = h.models.snapshot('file', { 'deleted' }) },
      'vertical'
    )
    local buffer, window = h.pane(ui, 'deleted')
    local target = assert(h.resolve_target(ui, buffer, window, 1, 1))
    assert(target.side == 'old' and target.file_id == 'file')
  end)
end

M.resolve_comment_target_should_reject_non_source_ranges_when_view_is_empty_or_informational = function()
  h.with_ui(function(ui)
    for _, current in ipairs({ h.models.snapshot('file', {}), h.models.binary('file') }) do
      ui:display_diff_side_by_side({ file_id = 'file', operation = 'added', current = current }, 'vertical')
      local window = vim.api.nvim_get_current_win()
      local buffer = vim.api.nvim_win_get_buf(window)
      assert(h.resolve_target(ui, buffer, window))
      assert(not h.resolve_target(ui, buffer, window, 1, 1))
      assert(not h.resolve_target(ui, buffer, window, 1))
    end
  end)
end

M.resolve_comment_target_should_reject_lost_association_when_buffer_changes_or_diff_is_cleared = function()
  h.with_ui(function(ui)
    local diff = h.models.modified({ 'old' }, { 'current' })
    ui:display_diff_side_by_side(diff, 'vertical')
    local old, window = h.pane(ui, 'old')
    local current = h.pane(ui, 'current')
    vim.api.nvim_win_set_buf(window, current)
    assert(not h.resolve_target(ui, old, window, 1, 1))
    assert(not h.resolve_target(ui, current, window, 1, 1))
    ui:refresh_selected_diff(diff, 'vertical')
    old, window = h.pane(ui, 'old')
    assert(h.resolve_target(ui, old, window, 1, 1))
    ui:clear_selected_diff()
    assert(not h.resolve_target(ui, old, window, 1, 1))
  end)
end

M.resolve_comment_target_should_keep_captured_target_when_reused_buffer_displays_another_file = function()
  local calls = 0
  h.with_ui(function(ui)
    local diff = h.models.modified({ 'old' }, { 'current' })
    ui:display_diff_side_by_side(diff, 'vertical')
    local buffer, window = h.pane(ui, 'current')
    local target = assert(h.resolve_target(ui, buffer, window, 1, 1))
    local editor = assert(ui:open_comment_editor(buffer, 1, 1))
    vim.api.nvim_buf_set_lines(editor, 0, -1, false, { 'draft' })
    diff.file_id = 'next-file'
    ui:display_diff_side_by_side(diff, 'vertical')
    local next_target = assert(h.resolve_target(ui, buffer, window, 1, 1))
    assert(next_target.file_id == 'next-file' and target.file_id == 'file')
    assert(not ui:open_comment_editor(buffer, 1, 1))
    assert(ui:write_comment_editor() and calls == 1)
    local editor_window = vim.fn.bufwinid(editor)
    assert(not h.resolve_target(ui, editor, editor_window, 1, 1))
  end, {
    on_comment_save = function(request)
      calls = calls + 1
      assert(request.target.file_id == 'file' and request.target.side == 'current')
      return { comment_id = 'saved' }
    end,
  })
end

M.resolve_comment_target_should_use_live_source_bounds_when_path_buffer_is_edited = function()
  require('helpers.git_repo').with_repo(function(repo)
    repo:write_file('file', { 'path source' })
    repo:add('file')
    repo:commit('source')
    h.with_ui(function(ui)
      ui:display_diff_side_by_side(
        { file_id = 'file', operation = 'added', current = h.models.path(repo.cwd .. '/file') },
        'vertical'
      )
      local buffer, window = h.pane(ui, 'path source')
      assert(not h.resolve_target(ui, buffer, window, 2, 2))
      vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { 'unsaved source' })
      assert(h.resolve_target(ui, buffer, window, 2, 2))
      vim.bo[buffer].modified = false
    end)
  end)
end

M.resolve_comment_target_should_refresh_source_bounds_when_snapshot_buffers_are_reused = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old', 'second' }, { 'current' }), 'vertical')
    local old, old_window = h.pane(ui, 'old')
    local current, current_window = h.pane(ui, 'current')
    assert(h.resolve_target(ui, old, old_window, 2, 2))
    assert(not h.resolve_target(ui, current, current_window, 2, 2))

    ui:refresh_selected_diff(h.models.modified({}, { 'expanded', 'second', 'third' }), 'vertical')
    assert(not h.resolve_target(ui, old, old_window, 1, 1))
    assert(h.resolve_target(ui, current, current_window, 3, 3))
    assert(ui:show_comments('file', {
      h.comment('stale old', 'old', 8, 8, 'stale'),
      h.comment('expanded current', 'current', 3, 3),
    }))
    assert(h.blocks(old)[1].row == 0 and h.blocks(current)[1].row == 2)

    ui:refresh_selected_diff(h.models.modified({ 'restored' }, {}), 'vertical')
    assert(h.resolve_target(ui, old, old_window, 1, 1))
    assert(not h.resolve_target(ui, current, current_window, 1, 1))
    assert(ui:show_comments('file', {
      h.comment('restored old', 'old', 1, 1),
      h.comment('empty current', 'current', 1, 1),
    }))
    assert(#h.blocks(old) == 1 and #h.blocks(current) == 0)
  end)
end

return M
