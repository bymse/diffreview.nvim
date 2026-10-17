local h = require('integration.ui.comments.helpers')
local M = {}

M.write_should_keep_open_and_wq_should_close_when_save_succeeds = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current' }), 'vertical', nil, 'file')
    local source, origin = h.pane(ui, 'current')
    local requests = {}
    local buffer = assert(ui:open_comment_editor({
      target = { file_id = 'file', side = 'current', line_start = 1, line_end = 1 },
      display_path = 'file',
      on_save = function(request)
        requests[#requests + 1] = request
        return { comment_id = 'id' }
      end,
    }))
    local editor = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'native', '' })
    vim.cmd('write')
    assert(vim.api.nvim_get_current_win() == editor and not vim.bo[buffer].modified)
    assert(requests[1].text == 'native\n' and requests[1].comment_id == nil)
    vim.cmd('wq')
    assert(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end))
    assert(#requests == 2 and requests[2].comment_id == 'id')
    assert(
      vim.api.nvim_get_current_win() == origin and vim.api.nvim_win_get_buf(origin) == source and vim.wo[origin].diff
    )
  end)
end

M.wq_should_abort_and_allow_retry_when_save_delete_or_handler_throws = function()
  for _, failure in ipairs({ 'save', 'delete', 'throw', 'new' }) do
    h.with_ui(function(ui)
      ui:display_diff_side_by_side(
        { operation = 'added', current = h.models.snapshot('file') },
        'vertical',
        nil,
        'file'
      )
      local failed = true
      local requests = {}
      local options = {
        target = { file_id = 'file' },
        display_path = 'file',
        comment = h.comment('saved', nil),
        on_save = function(request)
          requests[#requests + 1] = request
          if failed then
            if failure == 'throw' then
              error('handler failed')
            end
            return nil, 'save rejected'
          end
          return request.action == 'delete' and {} or { comment_id = 'id' }
        end,
      }
      if failure == 'new' then
        options.comment = nil
      end
      local buffer = assert(ui:open_comment_editor(options))
      local editor = vim.api.nvim_get_current_win()
      local body = failure == 'delete' and '' or 'attempt'
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { body })
      local ok, err = pcall(function()
        vim.cmd('wq')
      end)
      assert(not ok and tostring(err) ~= '')
      assert(vim.api.nvim_win_is_valid(editor) and vim.api.nvim_get_current_buf() == buffer and vim.bo[buffer].modified)
      assert(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)[1] == body)
      assert(requests[1].comment_id == (failure ~= 'new' and 'saved' or nil))
      failed = false
      vim.cmd('wq')
      assert(vim.wait(1000, function()
        return not vim.api.nvim_buf_is_valid(buffer)
      end))
      assert(#requests == 2 and requests[2].comment_id == (failure ~= 'new' and 'saved' or nil))
    end)
  end
end

M.wq_should_close_without_handler_when_new_draft_is_blank = function()
  h.with_ui(function(ui)
    ui:display_diff_side_by_side({ operation = 'added', current = h.models.snapshot('file') }, 'vertical', nil, 'file')
    local calls = 0
    local buffer = assert(ui:open_comment_editor({
      target = { file_id = 'file' },
      display_path = 'file',
      on_save = function()
        calls = calls + 1
        return { comment_id = 'id' }
      end,
    }))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { ' \t' })
    vim.cmd('wq')
    assert(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end))
    assert(calls == 0)
  end)
end

return M
