local h = require('integration.ui.comments.helpers')
local M = {}

M.write_comment_editor_should_propagate_identity_and_exact_text_when_saving_repeatedly = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old', 'two' }, { 'current', 'two' }), 'vertical', nil, 'file')
    local source = h.pane(ui, 'current')
    assert(ui:show_comments('file', { h.comment('projection', 'current', 1, 1) }))
    local blocks = h.blocks(source)
    local requests = {}
    local target = { file_id = 'file', side = 'current', line_start = 1, line_end = 2 }
    local buffer = assert(ui:open_comment_editor({
      target = target,
      display_path = 'file',
      on_save = function(request)
        requests[#requests + 1] = vim.deepcopy(request)
        request.target.file_id = 'mutated'
        return request.action == 'delete' and {} or { comment_id = 'id-' .. #requests }
      end,
    }))
    target.file_id = 'changed'
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { '  exact ', '', 'text', '' })
    assert(ui:write_comment_editor())
    assert(not vim.bo[buffer].modified and vim.api.nvim_get_current_buf() == buffer)
    assert(ui:write_comment_editor())
    assert(requests[1].comment_id == nil and requests[2].comment_id == 'id-1')
    assert(requests[1].text == '  exact \n\ntext\n' and requests[2].text == requests[1].text)
    assert(vim.deep_equal(requests[2].target, { file_id = 'file', side = 'current', line_start = 1, line_end = 2 }))
    assert(vim.deep_equal(h.blocks(source), blocks))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { ' \t', '' })
    assert(ui:write_comment_editor())
    assert(requests[3].action == 'delete' and requests[3].comment_id == 'id-2' and requests[3].text == nil)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { '' }) and not vim.bo[buffer].modified)
    assert(ui:write_comment_editor() and #requests == 3)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'new' })
    assert(ui:write_comment_editor() and requests[4].comment_id == nil)
  end)
end

M.write_comment_editor_should_protect_identity_when_handler_fails_or_returns_malformed_results = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side({ operation = 'added', current = h.models.snapshot('file') }, 'vertical', nil, 'file')
    local mode = 'error'
    local requests = {}
    local buffer = assert(ui:open_comment_editor({
      target = { file_id = 'file' },
      display_path = 'file',
      comment = h.comment('saved', nil),
      on_save = function(request)
        requests[#requests + 1] = vim.deepcopy(request)
        if mode == 'error' then
          return nil, 'rejected'
        end
        if mode == 'throw' then
          error('unavailable')
        end
        if mode == 'missing' then
          return nil
        end
        if mode == 'malformed' then
          return {}
        end
        return request.action == 'save' and { comment_id = 'new-id' } or {}
      end,
    }))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'attempt' })
    for _, failure in ipairs({ 'error', 'throw', 'missing', 'malformed' }) do
      mode = failure
      local ok, err = ui:write_comment_editor()
      assert(not ok and type(err) == 'string' and err ~= '' and vim.bo[buffer].modified)
      assert(requests[#requests].comment_id == 'saved')
    end
    mode = 'success'
    assert(ui:write_comment_editor() and not vim.bo[buffer].modified)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { '' })
    mode = 'error'
    assert(not ui:write_comment_editor() and vim.bo[buffer].modified)
    assert(requests[#requests].action == 'delete' and requests[#requests].comment_id == 'new-id')
    mode = 'success'
    assert(ui:write_comment_editor())
    local count = #requests
    assert(ui:write_comment_editor() and #requests == count)
    assert(ui:close_comment_editor())
    assert(not ui:write_comment_editor())
  end)
end

return M
