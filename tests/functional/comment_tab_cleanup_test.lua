local git_repo = require('helpers.git_repo')
local models = require('helpers.diff_view_model')
local ui = require('diffreview.ui')
local M = {}

M.cleanup_should_clear_borrowed_annotations_when_tab_closes_without_handler_cleanup = function()
  git_repo.with_repo(function(repo)
    repo:write_file('file', { 'borrowed' })
    repo:add('file')
    repo:commit('source')
    local notifications = 0
    local review_ui = ui.get_ui({
      on_file_selected = function() end,
      on_tab_closed = function()
        notifications = notifications + 1
      end,
    })
    local ok, err = xpcall(function()
      review_ui:display_diff_side_by_side(
        { operation = 'added', current = models.path(repo.cwd .. '/file') },
        'vertical',
        nil,
        'file'
      )
      local buffer = vim.fn.bufnr(repo.cwd .. '/file')
      assert(buffer ~= -1 and vim.api.nvim_buf_is_valid(buffer))
      local original_marks = vim.api.nvim_buf_get_extmarks(buffer, -1, 0, -1, { details = true })
      assert(review_ui:show_comments('file', {
        { id = 'body', text = 'body', state = 'open', target = { file_id = 'file' } },
      }))
      assert(#vim.api.nvim_buf_get_extmarks(buffer, -1, 0, -1, { details = true }) > #original_marks)
      vim.cmd('tabclose!')
      assert(notifications == 1)
      assert(vim.api.nvim_buf_is_valid(buffer) and not vim.bo[buffer].modified)
      assert(vim.deep_equal(vim.api.nvim_buf_get_extmarks(buffer, -1, 0, -1, { details = true }), original_marks))
      assert(not review_ui:show_comments('file', {}))
    end, debug.traceback)
    review_ui:cleanup()
    review_ui:cleanup()
    assert(ok, err)
  end)
end

return M
