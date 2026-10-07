local M = {}

---@alias quickfix_id integer

local quickfix_title = 'Diff Review'
local selection_bindings = {}

---@param instance_id integer
---@return string
local function quickfix_context(instance_id)
  return 'diffreview:files:' .. instance_id
end

---@param id quickfix_id|nil
---@return table|nil
local function get_quickfix_list(id)
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
  })
  return list.id == id and list or nil
end

---@return quickfix_id|nil
---@param id quickfix_id
---@return nil
local function select_quickfix_list(id)
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
---@return boolean
local function is_owned(id, instance_id)
  local list = get_quickfix_list(id)
  return list ~= nil and list.context == quickfix_context(instance_id)
end

---@param id quickfix_id|nil
---@param instance_id integer
---@return table|nil
local function get_active_owned_list(id, instance_id)
  if not is_owned(id, instance_id) then
    return nil
  end
  local current = vim.fn.getqflist({ id = 0 })
  if current.id ~= id then
    return nil
  end
  return get_quickfix_list(id)
end

---@param window integer
---@param buffer integer
---@return boolean
local function displays_quickfix_buffer(window, buffer)
  local info = vim.fn.getwininfo(window)[1]
  return info ~= nil and info.quickfix == 1 and info.loclist == 0 and vim.api.nvim_win_get_buf(window) == buffer
end

---@param buffer integer
---@return nil
local function close_quickfix_windows(buffer)
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if displays_quickfix_buffer(window, buffer) then
      vim.api.nvim_win_close(window, false)
    end
  end
end

---@param instance_id integer
---@return nil
local function remove_selection_binding(instance_id)
  local binding = selection_bindings[instance_id]
  if binding == nil then
    return
  end

  if vim.api.nvim_buf_is_valid(binding.buffer) then
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(binding.buffer, 'n')) do
      if mapping.lhs == '<CR>' and mapping.callback == binding.callback then
        vim.api.nvim_buf_del_keymap(binding.buffer, 'n', '<CR>')
        break
      end
    end
  end
  selection_bindings[instance_id] = nil
end

---@param id quickfix_id
---@param instance_id integer
---@param buffer integer
---@param file_ids table<string, boolean>
---@param on_file_selected fun(file_id: string): nil
---@return nil
local function bind_selection(id, instance_id, buffer, file_ids, on_file_selected)
  remove_selection_binding(instance_id)
  local binding
  binding = {
    buffer = buffer,
    callback = function()
      if selection_bindings[instance_id] ~= binding then
        return
      end

      local row = vim.api.nvim_win_get_cursor(0)[1]
      local list = get_active_owned_list(id, instance_id)
      local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
      if
        list == nil
        or list.qfbufnr ~= buffer
        or vim.api.nvim_get_current_buf() ~= buffer
        or info == nil
        or info.quickfix ~= 1
        or info.loclist ~= 0
      then
        return
      end

      local item = list.items[row]
      local user_data = item and item.user_data
      local file_id = type(user_data) == 'table' and user_data.file_id or nil
      if item == nil or not item.valid or type(file_id) ~= 'string' or not file_ids[file_id] then
        return
      end

      on_file_selected(file_id)
    end,
  }
  selection_bindings[instance_id] = binding
  vim.keymap.set('n', '<CR>', binding.callback, {
    buffer = buffer,
    desc = 'Open selected Diff Review file',
    silent = true,
  })
end

---@class QuickfixTextInfo
---@field id quickfix_id
---@field start_idx integer
---@field end_idx integer

---@param info QuickfixTextInfo
---@return string[]
local function format_quickfix_entries(info)
  local items = vim.fn.getqflist({ id = info.id, items = 1 }).items
  local lines = {}

  for index = info.start_idx, info.end_idx do
    local item = items[index]
    table.insert(lines, item.text)
  end

  return lines
end

---@param files ChangedFileViewModel[]
---@return vim.quickfix.entry[]
local function create_quickfix_entries(files)
  local unviewed = {}
  local viewed = {}

  for _, file in ipairs(files) do
    local entry = {
      lnum = 1,
      col = 1,
      text = ('%s -%d/+%d %s'):format(
        file.viewed and '[x]' or '[ ]',
        file.removed_lines,
        file.added_lines,
        file.display_path
      ),
      valid = 1,
      user_data = {
        file_id = file.id,
      },
    }

    table.insert(file.viewed and viewed or unviewed, entry)
  end

  vim.list_extend(unviewed, viewed)
  return unviewed
end

---@param id quickfix_id|nil
---@param instance_id integer
---@param files ChangedFileViewModel[]
---@param on_file_selected fun(file_id: string): nil
---@param on_list_acquired fun(id: quickfix_id): nil
---@return quickfix_id
function M.show_review_files(id, instance_id, files, on_file_selected, on_list_acquired)
  if not is_owned(id, instance_id) then
    id = nil
  end
  local action = id == nil and ' ' or 'u'
  local properties = {
    title = quickfix_title,
    context = quickfix_context(instance_id),
    items = create_quickfix_entries(files),
    quickfixtextfunc = format_quickfix_entries,
  }

  if id == nil then
    properties.nr = '$'
  else
    properties.id = id
  end

  if vim.fn.setqflist({}, action, properties) ~= 0 then
    error('failed to update the Diff Review quickfix list')
  end

  local quickfix_id = id or vim.fn.getqflist({ id = 0 }).id
  on_list_acquired(quickfix_id)
  select_quickfix_list(quickfix_id)
  vim.cmd('botright copen')
  local list = assert(get_quickfix_list(quickfix_id))
  local file_ids = {}
  for _, file in ipairs(files) do
    file_ids[file.id] = true
  end
  bind_selection(quickfix_id, instance_id, list.qfbufnr, file_ids, on_file_selected)

  return quickfix_id
end

---@param id quickfix_id|nil
---@param instance_id integer
---@return nil
function M.close_drawer(id, instance_id)
  local list = get_active_owned_list(id, instance_id)
  if list ~= nil then
    close_quickfix_windows(list.qfbufnr)
  end
end

---@param id quickfix_id|nil
---@param instance_id integer
---@return nil
function M.cleanup(id, instance_id)
  remove_selection_binding(instance_id)
  local list = get_quickfix_list(id)
  if list == nil or list.context ~= quickfix_context(instance_id) then
    return
  end

  ---@cast id quickfix_id
  if get_active_owned_list(id, instance_id) ~= nil then
    close_quickfix_windows(list.qfbufnr)
  end
  pcall(vim.fn.setqflist, {}, 'r', { id = id, items = {} })
end

return M
