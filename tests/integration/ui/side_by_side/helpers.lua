local M = {}

---@param path string
---@param lines string[]|nil
---@param mode DiffFileMode|nil
---@return DiffFileVersion
function M.snapshot(path, lines, mode)
  return {
    display_path = path,
    mode = mode or '100644',
    content = {
      kind = 'text',
      source = 'snapshot',
      lines = lines or { 'text' },
      endofline = true,
      fileformat = 'unix',
      filetype_path = path,
    },
  }
end

---@param path string
---@param mode DiffFileMode|nil
---@return DiffFileVersion
function M.binary(path, mode)
  return {
    display_path = path,
    mode = mode or '100644',
    content = { kind = 'binary', oid = 'a1b2', size = 12 },
  }
end

---@param path string
---@return DiffFileVersion
function M.path(path)
  return {
    display_path = path,
    mode = '100644',
    content = { kind = 'text', source = 'path', absolute_path = path },
  }
end

---@param review_ui ReviewUi
---@return integer
function M.main_buffer(review_ui)
  local window = review_ui.side_by_side.main_window
  assert(window ~= nil, 'expected main window')
  return vim.api.nvim_win_get_buf(window)
end

---@param review_ui ReviewUi
---@return string[]
function M.lines(review_ui)
  return vim.api.nvim_buf_get_lines(M.main_buffer(review_ui), 0, -1, false)
end

---@param review_ui ReviewUi
function M.cleanup(review_ui)
  local state = review_ui.side_by_side
  if state.native_diff.active then
    review_ui:display_diff_side_by_side({
      operation = 'error',
      attempted_operation = 'modified',
      path = 'cleanup',
      message = 'cleanup',
    }, 'vertical')
  end
  if state.tabpage ~= nil and vim.api.nvim_tabpage_is_valid(state.tabpage) then
    vim.api.nvim_set_current_tabpage(state.tabpage)
    vim.cmd('tabclose!')
  end
  for _, buffer in pairs({
    state.main_snapshot_buffer,
    state.companion_snapshot_buffer,
    state.information_buffer,
  }) do
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
  end
end

return M
