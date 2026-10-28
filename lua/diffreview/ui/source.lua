local M = {}

---@param buffer integer
---@param metadata ReviewBufferResource
---@return integer
function M.line_count(buffer, metadata)
  if metadata.snapshot_line_count ~= nil then
    return metadata.snapshot_line_count
  end
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  if
    #lines == 1
    and lines[1] == ''
    and not vim.bo[buffer].modified
    and vim.fn.getfsize(vim.api.nvim_buf_get_name(buffer)) == 0
  then
    return 0
  end
  return #lines
end

---@param registry ReviewResourceRegistry
---@param buffer integer
---@param window integer
---@param line_start integer|nil
---@param line_end integer|nil
---@return ReviewCommentTarget|nil, string|nil
function M.resolve_comment_target(registry, buffer, window, line_start, line_end)
  local display = registry:lookup(buffer, window)
  if display == nil or (display.kind ~= 'source' and display.kind ~= 'information') then
    return nil, 'No review source is associated with this buffer and window'
  end
  if line_start == nil and line_end == nil then
    return { file_id = display.file_id }, nil
  end
  if
    display.kind ~= 'source'
    or display.side == nil
    or type(line_start) ~= 'number'
    or line_start < 1
    or line_start % 1 ~= 0
    or type(line_end) ~= 'number'
    or line_end < line_start
    or line_end % 1 ~= 0
    or line_end > M.line_count(buffer, registry:resources().buffers[buffer])
  then
    return nil, 'Comment range must address displayed source lines'
  end
  return {
    file_id = display.file_id,
    side = display.side,
    line_start = line_start,
    line_end = line_end,
  },
    nil
end

return M
