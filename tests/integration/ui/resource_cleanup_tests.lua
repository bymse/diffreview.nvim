local h = require('integration.ui.comments.helpers')
local M = {}

M.cleanup_should_release_hidden_registered_resources_when_multiple_views_and_editor_have_been_opened = function()
  require('helpers.git_repo').with_repo(function(repo)
    repo:write_file('file', { 'borrowed' })
    repo:add('file')
    repo:commit('source')
    h.with_ui(function(ui)
      ui:display_diff_side_by_side(
        { file_id = 'file', operation = 'added', current = h.models.path(repo.cwd .. '/file') },
        'vertical'
      )
      local borrowed = h.pane(ui, 'borrowed')
      ui:display_diff_side_by_side(
        { file_id = 'file', operation = 'added', current = h.models.binary('file') },
        'vertical'
      )
      ui:display_diff_side_by_side(h.models.modified({ 'old' }, { 'current' }), 'vertical')
      assert(ui:open_comment_editor())
      local resources = ui.registry:resources()
      local hidden_owned = false
      for buffer, metadata in pairs(resources.buffers) do
        hidden_owned = hidden_owned or metadata.owned and vim.fn.bufwinid(buffer) == -1
      end
      assert(hidden_owned and not resources.buffers[borrowed].owned)
      ui:cleanup()
      for buffer, metadata in pairs(resources.buffers) do
        if metadata.owned then
          assert(not vim.api.nvim_buf_is_valid(buffer))
        end
      end
      for window in pairs(resources.windows) do
        assert(not vim.api.nvim_win_is_valid(window))
      end
      assert(vim.api.nvim_buf_is_valid(borrowed))
      assert(vim.deep_equal(vim.api.nvim_buf_get_lines(borrowed, 0, -1, false), { 'borrowed' }))
      assert(next(ui.registry:resources().buffers) == nil and next(ui.registry:resources().windows) == nil)
    end, {
      on_comment_save = function()
        error('Cleanup must not save')
      end,
    })
  end)
end

M.display_diff_side_by_side_should_invalidate_and_retain_cleanup_inventory_when_scratch_creation_fails = function()
  h.with_ui(function(ui)
    local diff = h.models.modified({ 'old' }, { 'current' })
    ui:display_diff_side_by_side(diff, 'vertical')
    local source, window = h.pane(ui, 'current')
    local name = vim.api.nvim_buf_get_name(source)
    vim.api.nvim_buf_delete(source, { force = true })
    local collision = vim.api.nvim_create_buf(false, true)
    local ok, err = xpcall(function()
      vim.api.nvim_buf_set_name(collision, name)
      assert(not pcall(ui.display_diff_side_by_side, ui, diff, 'vertical'))
      assert(not ui:show_comments('file', {}))
      assert(not h.resolve_target(ui, source, window, 1, 1))
      local resources = ui.registry:resources()
      local owned_count = 0
      for _, metadata in pairs(resources.buffers) do
        if metadata.owned then
          owned_count = owned_count + 1
        end
      end
      assert(owned_count >= 2)
      ui:cleanup()
      for buffer, metadata in pairs(resources.buffers) do
        if metadata.owned then
          assert(not vim.api.nvim_buf_is_valid(buffer))
        end
      end
      assert(vim.api.nvim_buf_is_valid(collision))
    end, debug.traceback)
    vim.api.nvim_buf_delete(collision, { force = true })
    assert(ok, err)
  end)
end

return M
