local M = {}

---@param ui ReviewUi
---@return nil
function M.clear(ui)
  for buffer in pairs(ui.comment_buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_clear_namespace(buffer, ui.comment_namespace, 0, -1)
    end
  end
  ui.comment_buffers = {}
end

---@param pane ReviewSourcePane
---@return integer
function M.source_line_count(pane)
  if pane.snapshot_line_count ~= nil then
    return pane.snapshot_line_count
  end
  local lines = vim.api.nvim_buf_get_lines(pane.buffer, 0, -1, false)
  if
    #lines == 1
    and lines[1] == ''
    and not vim.bo[pane.buffer].modified
    and vim.fn.getfsize(vim.api.nvim_buf_get_name(pane.buffer)) == 0
  then
    return 0
  end
  return #lines
end

---@param ui ReviewUi
---@param file_id string
---@param comments ReviewComment[]
---@return boolean, string|nil
function M.show(ui, file_id, comments)
  local presentation = ui.side_by_side.presentation
  if presentation == nil or presentation.file_id == nil or presentation.file_id ~= file_id then
    return false, 'No matching associated diff presentation'
  end
  for _, pane in ipairs(presentation.panes) do
    if
      not vim.api.nvim_win_is_valid(pane.window)
      or not vim.api.nvim_buf_is_valid(pane.buffer)
      or vim.api.nvim_win_get_buf(pane.window) ~= pane.buffer
      or vim.api.nvim_win_get_tabpage(pane.window) ~= ui.tabpage
    then
      return false, 'Displayed source pane is no longer available'
    end
  end
  M.clear(ui)
  for index, pane in ipairs(presentation.panes) do
    local count = M.source_line_count(pane)
    local groups = {}
    for _, comment in ipairs(comments) do
      local target = comment.target
      local whole_file = target.line_start == nil and target.line_end == nil
      local matches = target.side == pane.side and pane.side ~= nil or whole_file and target.side == nil and index == 1
      if comment.state ~= 'resolved' and target.file_id == file_id and matches then
        local stale = comment.state == 'stale'
        if whole_file or stale or (target.line_start >= 1 and target.line_end <= count) then
          local row = whole_file and 0 or math.max(0, math.min(target.line_end - 1, count - 1))
          local key = (whole_file and 'above:' or 'below:') .. row
          if groups[key] == nil then
            groups[key] = { row = row, above = whole_file, lines = {} }
          end
          local lines = groups[key].lines
          local label = target.side or 'file'
          if whole_file then
            label = target.side and label .. ' file' or label
          elseif target.line_start == target.line_end then
            label = label .. ' line ' .. target.line_start
          else
            label = label .. ' lines ' .. target.line_start .. '-' .. target.line_end
          end
          table.insert(lines, { { (stale and 'Stale: ' or '') .. label, stale and 'WarningMsg' or 'Comment' } })
          for _, text in ipairs(vim.split(comment.text, '\n', { plain = true })) do
            table.insert(lines, { { text, 'Comment' } })
          end
        end
      end
    end
    for _, group in pairs(groups) do
      vim.api.nvim_buf_set_extmark(pane.buffer, ui.comment_namespace, group.row, 0, {
        virt_lines = group.lines,
        virt_lines_above = group.above,
      })
      ui.comment_buffers[pane.buffer] = true
    end
  end
  return true, nil
end

return M
