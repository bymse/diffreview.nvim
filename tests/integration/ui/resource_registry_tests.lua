local registries = require('diffreview.ui.resource_registry')
local M = {}

---@param run fun(registry: ReviewResourceRegistry, buffers: integer[], windows: integer[]): nil
---@return nil
local function with_registry(run)
  local buffers = {}
  local windows = {}
  local registry = registries.new(vim.api.nvim_get_current_tabpage())
  local ok, err = xpcall(function()
    for _ = 1, 3 do
      table.insert(buffers, vim.api.nvim_create_buf(false, true))
    end
    for index = 1, 2 do
      table.insert(windows, vim.api.nvim_open_win(buffers[index], false, { split = 'below' }))
    end
    run(registry, buffers, windows)
  end, debug.traceback)
  for _, window in ipairs(windows) do
    if vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
  for _, buffer in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
  end
  assert(ok, err)
end

M.bind_window_should_require_matching_registered_buffer_when_binding_is_created = function()
  with_registry(function(registry, buffers, windows)
    local display = { file_id = 'file', kind = 'source', side = 'old' }
    local ok, err = registry:bind_window(windows[1], buffers[1], display)
    assert(not ok and err and next(registry:resources().windows) == nil)
    assert(registry:register_buffer(buffers[1], { owned = true, purpose = 'snapshot' }))
    assert(registry:bind_window(windows[1], buffers[1], display))
    local before = registry:resources()
    assert(not registry:bind_window(windows[2], buffers[1], display))
    assert(vim.deep_equal(registry:resources(), before))
    assert(registry:lookup(buffers[1], windows[1]).side == 'old')
  end)
end

M.register_buffer_should_preserve_ownership_when_registration_conflicts = function()
  with_registry(function(registry, buffers)
    local metadata = { owned = false, purpose = 'source' }
    assert(registry:register_buffer(buffers[1], metadata))
    metadata.owned = true
    assert(not registry:register_buffer(buffers[1], metadata))
    assert(not registry:resources().buffers[buffers[1]].owned)
    assert(registry:register_buffer(buffers[1], { owned = false, purpose = 'source' }))
    vim.api.nvim_buf_delete(buffers[3], { force = true })
    assert(not registry:register_buffer(buffers[3], metadata))
  end)
end

M.lookup_should_return_detached_window_specific_identity_when_buffer_is_shared = function()
  with_registry(function(registry, buffers, windows)
    assert(registry:register_buffer(buffers[1], { owned = true, purpose = 'snapshot' }))
    vim.api.nvim_win_set_buf(windows[2], buffers[1])
    local display = { file_id = 'file', kind = 'source', side = 'old' }
    assert(registry:bind_window(windows[1], buffers[1], display))
    display.side = 'current'
    assert(registry:bind_window(windows[2], buffers[1], display))
    display.file_id = 'mutated'
    local old = assert(registry:lookup(buffers[1], windows[1]))
    assert(old.file_id == 'file' and old.side == 'old')
    old.file_id = 'also mutated'
    assert(registry:lookup(buffers[1], windows[1]).file_id == 'file')
    assert(registry:lookup(buffers[1], windows[2]).side == 'current')
    assert(registry:lookup(buffers[2], windows[1]) == nil)
  end)
end

M.lookup_should_reject_unavailable_associations_when_resources_are_replaced_or_closed = function()
  with_registry(function(registry, buffers, windows)
    assert(registry:register_buffer(buffers[1], { owned = false, purpose = 'source' }))
    assert(registry:register_buffer(buffers[2], { owned = true, purpose = 'information' }))
    assert(registry:bind_window(windows[1], buffers[1], { file_id = 'old-file', kind = 'source', side = 'old' }))
    vim.api.nvim_win_set_buf(windows[1], buffers[2])
    assert(registry:lookup(buffers[1], windows[1]) == nil)
    assert(registry:lookup(buffers[2], windows[1]) == nil)
    assert(registry:bind_window(windows[1], buffers[2], { file_id = 'new-file', kind = 'information' }))
    local display = assert(registry:lookup(buffers[2], windows[1]))
    assert(display.file_id == 'new-file' and display.side == nil)
    assert(registry:bind_window(windows[1], buffers[2], nil))
    assert(registry:lookup(buffers[2], windows[1]) == nil)
    assert(registry:resources().windows[windows[1]].buffer == buffers[2])
    vim.api.nvim_win_close(windows[1], true)
    assert(registry:lookup(buffers[2], windows[1]) == nil)
    assert(registry:resources().windows[windows[1]] ~= nil)
  end)
end

M.bind_window_should_preserve_registry_when_window_belongs_to_another_tab = function()
  with_registry(function(registry, buffers, windows)
    assert(registry:register_buffer(buffers[1], { owned = false, purpose = 'source' }))
    assert(registry:bind_window(windows[1], buffers[1], { file_id = 'file', kind = 'source', side = 'current' }))
    require('integration.ui.comments.helpers').with_ui(function(ui)
      ui:display_diff_side_by_side({
        file_id = 'other',
        operation = 'added',
        current = require('helpers.diff_view_model').snapshot('other', { 'foreign' }),
      }, 'vertical')
      local window = vim.api.nvim_get_current_win()
      local buffer = vim.api.nvim_win_get_buf(window)
      assert(registry:register_buffer(buffer, { owned = false, purpose = 'source' }))
      local before = registry:resources()
      assert(not registry:bind_window(window, buffer, { file_id = 'other', kind = 'source', side = 'current' }))
      assert(vim.deep_equal(registry:resources(), before))
    end)
  end)
end

M.resources_should_include_hidden_buffers_and_preserve_tracking_when_snapshot_is_modified = function()
  with_registry(function(registry, buffers, windows)
    assert(registry:register_buffer(buffers[1], { owned = false, purpose = 'source' }))
    assert(registry:register_buffer(buffers[3], { owned = true, purpose = 'snapshot' }))
    assert(registry:bind_window(windows[1], buffers[1], { file_id = 'file', kind = 'source', side = 'current' }))
    local resources = registry:resources()
    assert(resources.buffers[buffers[3]].owned and vim.fn.bufwinid(buffers[3]) == -1)
    resources.buffers[buffers[3]] = nil
    resources.windows[windows[1]].display.file_id = 'mutated'
    assert(registry:resources().buffers[buffers[3]].owned)
    assert(registry:lookup(buffers[1], windows[1]).file_id == 'file')
    registry:remove_window(windows[1])
    assert(registry:resources().buffers[buffers[1]] ~= nil)
    assert(vim.api.nvim_win_is_valid(windows[1]) and vim.api.nvim_buf_is_valid(buffers[1]))
  end)
end

M.remove_buffer_should_forget_dependent_bindings_when_buffer_is_unregistered = function()
  with_registry(function(registry, buffers, windows)
    assert(registry:register_buffer(buffers[1], { owned = false, purpose = 'source' }))
    vim.api.nvim_win_set_buf(windows[2], buffers[1])
    for _, window in ipairs(windows) do
      assert(registry:bind_window(window, buffers[1], { file_id = 'file', kind = 'source', side = 'current' }))
    end
    registry:remove_buffer(buffers[1])
    registry:remove_buffer(buffers[1])
    assert(next(registry:resources().windows) == nil and next(registry:resources().buffers) == nil)
    for _, window in ipairs(windows) do
      assert(vim.api.nvim_win_get_buf(window) == buffers[1])
    end
  end)
end

M.displays_for_file_should_return_detached_source_and_information_bindings_when_file_matches = function()
  with_registry(function(registry, buffers, windows)
    assert(registry:register_buffer(buffers[1], { owned = true, purpose = 'snapshot', snapshot_line_count = 2 }))
    assert(registry:register_buffer(buffers[2], { owned = true, purpose = 'information' }))
    assert(registry:register_buffer(buffers[3], { owned = true, purpose = 'snapshot' }))
    assert(registry:bind_window(windows[1], buffers[1], { file_id = 'file', kind = 'source', side = 'old' }))
    assert(registry:bind_window(windows[2], buffers[2], { file_id = 'file', kind = 'editor' }))
    local displays = assert(registry:displays_for_file('file'))
    assert(#displays == 1 and displays[1].window == windows[1] and displays[1].buffer == buffers[1])
    assert(displays[1].display.side == 'old' and displays[1].metadata.snapshot_line_count == 2)
    displays[1].display.file_id = 'mutated'
    displays[1].metadata.snapshot_line_count = 99
    displays = assert(registry:displays_for_file('file'))
    assert(displays[1].display.file_id == 'file' and displays[1].metadata.snapshot_line_count == 2)
    assert(registry:bind_window(windows[2], buffers[2], { file_id = 'other', kind = 'information' }))
    assert(#assert(registry:displays_for_file('file')) == 1)
    assert(registry:bind_window(windows[2], buffers[2], { file_id = 'file', kind = 'information', primary = true }))
    displays = assert(registry:displays_for_file('file'))
    assert(#displays == 2)
    local information
    for _, pane in ipairs(displays) do
      if pane.window == windows[2] then
        information = pane
      end
    end
    assert(information and information.display.kind == 'information' and information.display.primary)
    assert(registry:bind_window(windows[2], buffers[2], nil))
    assert(#assert(registry:displays_for_file('file')) == 1)
    assert(#assert(registry:displays_for_file('missing')) == 0)
  end)
end

M.displays_for_file_should_reject_whole_query_when_matching_association_is_lost = function()
  for _, loss in ipairs({ 'replacement', 'window', 'buffer' }) do
    with_registry(function(registry, buffers, windows)
      for index = 1, 2 do
        assert(registry:register_buffer(buffers[index], { owned = false, purpose = 'source' }))
        assert(registry:bind_window(windows[index], buffers[index], {
          file_id = index == 1 and 'file' or 'other',
          kind = 'source',
          side = 'current',
        }))
      end
      if loss == 'replacement' then
        vim.api.nvim_win_set_buf(windows[2], buffers[3])
      elseif loss == 'window' then
        vim.api.nvim_win_close(windows[2], true)
      else
        vim.api.nvim_buf_delete(buffers[2], { force = true })
      end
      assert(#assert(registry:displays_for_file('file')) == 1)
      local displays, err = registry:displays_for_file('other')
      assert(displays == nil and type(err) == 'string' and err ~= '')
      local binding = registry:resources().windows[windows[1]]
      assert(registry:bind_window(windows[1], binding.buffer, { file_id = 'other', kind = 'source', side = 'old' }))
      displays, err = registry:displays_for_file('other')
      assert(displays == nil and type(err) == 'string' and err ~= '')
      assert(registry:lookup(buffers[1], windows[1]).side == 'old')
    end)
  end
end

return M
