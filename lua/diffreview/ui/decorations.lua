local M = {}

---@param content DiffPathTextContent|DiffSnapshotTextContent
---@param buffer integer
---@return integer
local function logical_text_line_count(content, buffer)
  if content.source == 'snapshot' then
    return #content.lines
  end
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  if
    #lines == 1
    and lines[1] == ''
    and vim.api.nvim_get_option_value('eol', { buf = buffer })
    and vim.api.nvim_get_option_value('endofline', { buf = buffer })
    and not vim.api.nvim_get_option_value('modified', { buf = buffer })
  then
    return vim.fn.getfsize(content.absolute_path) == 0 and 0 or 1
  end
  return #lines
end

---@param buffer integer
---@param namespace integer
---@param diff DiffViewModel
---@return boolean decorated
function M.set(buffer, namespace, diff)
  local content
  local highlight
  if diff.operation == 'added' or diff.operation == 'untracked' then
    content = diff.current.content
    highlight = 'DiffAdd'
  elseif diff.operation == 'deleted' then
    content = diff.old.content
    highlight = 'DiffDelete'
  else
    return false
  end
  if content.kind ~= 'text' then
    return false
  end
  ---@cast content DiffPathTextContent|DiffSnapshotTextContent
  for line = 0, logical_text_line_count(content, buffer) - 1 do
    vim.api.nvim_buf_set_extmark(buffer, namespace, line, 0, {
      end_row = line + 1,
      hl_group = highlight,
      hl_eol = true,
    })
  end
  return true
end

---@param buffer integer
---@param namespace integer
---@return nil
function M.clear(buffer, namespace)
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)
end

return M
