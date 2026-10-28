local source = require('diffreview.ui.source')
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

---@param ui ReviewUi
---@param file_id string
---@param comments ReviewComment[]
---@return boolean, string|nil
function M.show(ui, file_id, comments)
  if ui.selected_diff == nil or ui.selected_diff.file_id ~= file_id then
    return false, 'No matching associated diff presentation'
  end
  local panes, err = ui.registry:displays_for_file(file_id)
  if panes == nil then
    return false, err
  end
  if #panes == 0 then
    return false, 'No associated source panes'
  end
  M.clear(ui)
  for _, pane in ipairs(panes) do
    local display = pane.display
    local count = display.kind == 'source' and source.line_count(pane.buffer, pane.metadata) or 0
    local groups = {}
    for _, comment in ipairs(comments) do
      local target = comment.target
      local whole_file = target.line_start == nil and target.line_end == nil
      local matches = target.side == display.side and display.side ~= nil
        or whole_file and target.side == nil and display.primary == true
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
