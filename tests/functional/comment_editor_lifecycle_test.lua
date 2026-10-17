local h = require('integration.ui.comments.helpers')
local M = {}

M.quit_should_protect_draft_and_forced_quit_should_discard_when_editor_is_modified = function()
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
    local hidden = vim.o.hidden
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'discard me' })
    assert(not pcall(function()
      vim.cmd('quit')
    end))
    assert(vim.api.nvim_get_current_buf() == buffer and vim.bo[buffer].modified)
    assert(vim.o.hidden == hidden and calls == 0)
    vim.cmd('hide')
    assert(vim.api.nvim_buf_is_valid(buffer) and vim.bo[buffer].modified)
    assert(ui:open_comment_editor(options) == buffer)
    assert(vim.api.nvim_buf_get_lines(buffer, 0, -1, false)[1] == 'discard me')
    vim.cmd('quit!')
    assert(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end))
    assert(calls == 0 and vim.api.nvim_get_current_win() == origin)
    assert(vim.api.nvim_win_get_buf(origin) == source and vim.wo[origin].diff)
    local fresh = assert(ui:open_comment_editor(options))
    assert(fresh ~= buffer and not vim.bo[fresh].modified)
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(fresh, 0, -1, false), { '' }))
    vim.cmd('quit')
    assert(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(fresh)
    end))
    assert(calls == 0)
  end)
end

M.cleanup_should_release_draft_when_native_tab_closes = function()
  local ui = require('diffreview.ui').get_ui({ on_file_selected = function() end, on_tab_closed = function() end })
  local ok, err = xpcall(function()
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
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'draft' })
    vim.cmd('tabclose!')
    assert(vim.wait(1000, function()
      return not vim.api.nvim_buf_is_valid(buffer)
    end))
    assert(calls == 0 and not ui:write_comment_editor())
  end, debug.traceback)
  ui:cleanup()
  assert(ok, err)
end

return M
