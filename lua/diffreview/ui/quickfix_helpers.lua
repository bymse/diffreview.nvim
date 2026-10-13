local M = {}

---@alias quickfix_id integer

---@param instance_id integer
---@param kind 'files'|'comments'|nil
---@return string
function M.quickfix_context(instance_id, kind)
  return 'diffreview:' .. (kind or 'files') .. ':' .. instance_id
end

---@param id quickfix_id|nil
---@return table|nil
function M.get_quickfix_list(id)
  if id == nil then
    return nil
  end
  local list = vim.fn.getqflist({
    id = id,
    items = 1,
    title = 1,
    context = 1,
    quickfixtextfunc = 1,
    nr = 0,
    qfbufnr = 1,
    changedtick = 1,
  })
  return list.id == id and list or nil
end

---@param id quickfix_id
---@return nil
function M.select_quickfix_list(id)
  local current = vim.fn.getqflist({ nr = 0 })
  local target = vim.fn.getqflist({ id = id, nr = 0 })
  local distance = target.nr - current.nr
  if distance > 0 then
    vim.cmd(('silent %dcnewer'):format(distance))
  elseif distance < 0 then
    vim.cmd(('silent %dcolder'):format(-distance))
  end
end

---@param id quickfix_id|nil
---@param instance_id integer
---@param kind 'files'|'comments'|nil
---@return boolean
function M.is_owned(id, instance_id, kind)
  local list = M.get_quickfix_list(id)
  return list ~= nil and list.context == M.quickfix_context(instance_id, kind)
end

---@param id quickfix_id|nil
---@param instance_id integer
---@param kind 'files'|'comments'|nil
---@return table|nil
function M.get_active_owned_list(id, instance_id, kind)
  if not M.is_owned(id, instance_id, kind) then
    return nil
  end
  local current = vim.fn.getqflist({ id = 0 })
  if current.id ~= id then
    return nil
  end
  return M.get_quickfix_list(id)
end

---@param window integer
---@param buffer integer
---@return boolean
function M.displays_quickfix_buffer(window, buffer)
  local info = vim.fn.getwininfo(window)[1]
  return info ~= nil and info.quickfix == 1 and info.loclist == 0 and vim.api.nvim_win_get_buf(window) == buffer
end

---@param buffer integer
---@return nil
function M.close_quickfix_windows(buffer)
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if M.displays_quickfix_buffer(window, buffer) then
      vim.api.nvim_win_close(window, false)
    end
  end
end

---@return table<integer, integer[]>
function M.drawer_cursors()
  local cursors = {}
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    local info = vim.fn.getwininfo(window)[1]
    if info.quickfix == 1 and info.loclist == 0 then
      cursors[window] = vim.api.nvim_win_get_cursor(window)
    end
  end
  return cursors
end

---@param cursors table<integer, integer[]>
---@return nil
function M.restore_cursors(cursors)
  for window, cursor in pairs(cursors) do
    if vim.api.nvim_win_is_valid(window) then
      cursor[1] = math.min(cursor[1], vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(window)))
      vim.api.nvim_win_set_cursor(window, cursor)
    end
  end
end

---@param id quickfix_id|nil
---@param instance_id integer
---@param tab integer
---@param kind 'files'|'comments'|nil
---@return boolean
function M.drawer_open(id, instance_id, tab, kind)
  local list = M.get_active_owned_list(id, instance_id, kind)
  if list == nil then
    return false
  end
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if M.displays_quickfix_buffer(window, list.qfbufnr) then
      return true
    end
  end
  return false
end

---@class QuickfixTextInfo
---@field id quickfix_id
---@field start_idx integer
---@field end_idx integer

---@param info QuickfixTextInfo
---@return string[]
function M.format_quickfix_entries(info)
  local items = vim.fn.getqflist({ id = info.id, items = 1 }).items
  local lines = {}
  for index = info.start_idx, info.end_idx do
    table.insert(lines, items[index].text)
  end
  return lines
end

---@param id quickfix_id|nil
---@param instance_id integer
---@param kind 'files'|'comments'|nil
---@return nil
function M.close_drawer(id, instance_id, kind)
  local list = M.get_active_owned_list(id, instance_id, kind)
  if list ~= nil then
    M.close_quickfix_windows(list.qfbufnr)
  end
end

return M
