local h = require('integration.ui.comments.helpers')
local M = {}

M.open_comment_editor_should_capture_lookup_record_when_same_target_is_reopened = function()
  local lookups = 0
  local record = h.comment('saved\n\n', 'current', 1, 2)
  local requests = {}
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old', 'second' }, { 'current', 'second' }), 'vertical')
    local source = h.pane(ui, 'current')
    local buffer = assert(ui:open_comment_editor(source, 1, 2))
    assert(lookups == 1 and not vim.bo[buffer].modified)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'saved', '', '' }))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    record.id = 'replacement-id'
    record.text = 'replacement body'
    record.target.line_start = 2
    assert(ui:open_comment_editor(source, 1, 2) == buffer and lookups == 1)
    assert(ui:write_comment_editor())
    assert(requests[1].comment_id == 'saved\n\n' and requests[1].text == 'draft')
    assert(vim.deep_equal(requests[1].target, { file_id = 'file', side = 'current', line_start = 1, line_end = 2 }))
  end, {
    get_comment = function(target)
      lookups = lookups + 1
      assert(vim.deep_equal(target, record.target))
      target.file_id = 'mutated lookup input'
      return record
    end,
    on_comment_save = function(request)
      table.insert(requests, request)
      return { comment_id = 'saved' }
    end,
  })
end

M.open_comment_editor_should_preserve_existing_draft_when_lookup_fails_or_returns_invalid_record = function()
  local mode = 'new'
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old', 'second' }, { 'current', 'second' }), 'vertical')
    local source = h.pane(ui, 'current')
    local first = assert(ui:open_comment_editor(source, 1, 1))
    for _, failure in ipairs({ 'error', 'throw', 'mismatch', 'malformed' }) do
      mode = failure
      local buffer, err = ui:open_comment_editor(source, 2, 2)
      assert(buffer == nil and type(err) == 'string' and err ~= '')
      assert(vim.api.nvim_buf_is_valid(first) and not vim.bo[first].modified)
      assert(vim.api.nvim_get_current_buf() == first)
    end
  end, {
    on_comment_save = h.save,
    get_comment = function()
      if mode == 'error' then
        return nil, 'lookup unavailable'
      elseif mode == 'throw' then
        error('lookup unavailable')
      elseif mode == 'mismatch' then
        return h.comment('wrong target', 'old', 2, 2)
      elseif mode == 'malformed' then
        ---@type any
        local malformed = { id = 'missing target and body' }
        return malformed
      end
      return nil
    end,
  })
end

M.open_comment_editor_should_report_missing_save_dependency_when_ui_has_no_comment_handlers = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current' }), 'vertical')
    local source, origin = h.pane(ui, 'current')
    local count = #vim.api.nvim_tabpage_list_wins(assert(ui.tabpage))
    local buffer, err = ui:open_comment_editor()
    assert(buffer == nil and type(err) == 'string' and err ~= '')
    assert(vim.api.nvim_get_current_win() == origin and vim.api.nvim_win_get_buf(origin) == source)
    assert(#vim.api.nvim_tabpage_list_wins(ui.tabpage) == count)
  end, {})
end

M.open_comment_editor_should_prefer_current_binding_and_reject_ambiguity_when_buffer_has_multiple_sources = function()
  local requests = {}
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current' }), 'vertical')
    local source, origin = h.pane(ui, 'current')
    local _, other = h.pane(ui, 'old')
    local duplicate = vim.api.nvim_open_win(source, false, { split = 'below' })
    assert(ui.registry:bind_window(duplicate, source, { file_id = 'file', kind = 'source', side = 'old' }))
    vim.api.nvim_set_current_win(origin)
    local buffer = assert(ui:open_comment_editor(source))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'preferred current' })
    assert(ui:write_comment_editor() and requests[1].target.side == 'current')
    assert(ui:close_comment_editor())
    vim.api.nvim_set_current_win(other)
    local result, err = ui:open_comment_editor(source)
    assert(result == nil and type(err) == 'string' and err ~= '')
    ui.registry:remove_window(duplicate)
    assert(ui:open_comment_editor(source))
  end, {
    on_comment_save = function(request)
      table.insert(requests, request)
      return { comment_id = 'saved' }
    end,
  })
end

M.open_comment_editor_should_use_supplied_range_when_current_buffer_is_selected_with_zero = function()
  local requests = {}
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current', 'second' }), 'vertical')
    vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { 2, 0 })
    local buffer = assert(ui:open_comment_editor(0, 1, 2))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'range' })
    assert(ui:write_comment_editor())
    assert(requests[1].target.line_start == 1 and requests[1].target.line_end == 2)
  end, {
    on_comment_save = function(request)
      table.insert(requests, request)
      return { comment_id = 'saved' }
    end,
  })
end

return M
