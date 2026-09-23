local M = {}

---@alias quickfix_id integer

---@class QuickfixContext
---@field plugin 'diffreview'
---@field view 'review_files'
---@field instance_id integer

local quickfix_title = 'Diff Review'

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
local function quickfix_id_for_buffer()
  local id = vim.fn.getqflist({ id = 0 }).id
  if id ~= 0 then
    return id
  end
end

---@return table[]
local function current_tab_quickfix_windows()
  local windows = {}

  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local info = vim.fn.getwininfo(window)[1]
    if info.quickfix == 1 and info.loclist == 0 then
      table.insert(windows, { id = window, quickfix_id = quickfix_id_for_buffer() })
    end
  end

  return windows
end

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

---@param windows table[]
---@return nil
local function restore_windows(windows)
  for _, window in ipairs(windows) do
    pcall(function()
      if window.quickfix_id ~= nil and vim.api.nvim_win_is_valid(window.id) then
        local list = get_quickfix_list(window.quickfix_id)
        if list ~= nil and list.qfbufnr ~= 0 then
          vim.api.nvim_win_set_buf(window.id, list.qfbufnr)
        end
      end
    end)
  end
end

---@param windows table[]
---@return nil
local function close_new_quickfix_windows(windows)
  local existing = {}
  for _, window in ipairs(windows) do
    existing[window.id] = true
  end

  for _, window in ipairs(current_tab_quickfix_windows()) do
    if not existing[window.id] then
      pcall(vim.api.nvim_win_close, window.id, false)
    end
  end
end

---@param id quickfix_id|nil
---@param context QuickfixContext
---@return boolean
function M.is_owned(id, context)
  local list = get_quickfix_list(id)
  return list ~= nil and vim.deep_equal(list.context, context)
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
---@param context QuickfixContext
---@param files ChangedFileViewModel[]
---@return quickfix_id
function M.show_review_files(id, context, files)
  local previous = vim.fn.getqflist({ id = 0, nr = 0 })
  local windows = current_tab_quickfix_windows()
  local existing = get_quickfix_list(id)
  local created_id = nil
  local action = id == nil and ' ' or 'u'
  local properties = {
    title = quickfix_title,
    context = context,
    items = create_quickfix_entries(files),
    quickfixtextfunc = format_quickfix_entries,
  }

  if id == nil then
    properties.nr = '$'
  else
    properties.id = id
  end

  local ok, result = xpcall(function()
    if vim.fn.setqflist({}, action, properties) ~= 0 then
      error('failed to update the Diff Review quickfix list')
    end

    local quickfix_id = id or vim.fn.getqflist({ id = 0 }).id
    if id == nil then
      created_id = quickfix_id
    end
    select_quickfix_list(quickfix_id)
    vim.cmd('botright copen')
    return quickfix_id
  end, debug.traceback)

  if ok then
    return result
  end

  if existing ~= nil then
    pcall(vim.fn.setqflist, {}, 'r', {
      id = existing.id,
      items = existing.items,
      title = existing.title,
      context = existing.context,
      quickfixtextfunc = existing.quickfixtextfunc,
    })
  elseif created_id ~= nil then
    if created_id ~= 0 then
      pcall(vim.fn.setqflist, {}, 'r', { id = created_id, items = {} })
    end
  end

  pcall(select_quickfix_list, previous.id)
  restore_windows(windows)
  close_new_quickfix_windows(windows)

  error(result, 0)
end

---@param id quickfix_id|nil
---@param context QuickfixContext
---@return nil
function M.cleanup(id, context)
  if not M.is_owned(id, context) then
    return
  end

  ---@cast id quickfix_id
  pcall(vim.fn.setqflist, {}, 'r', { id = id, items = {} })
  for _, window in ipairs(current_tab_quickfix_windows()) do
    if window.quickfix_id == id then
      pcall(vim.api.nvim_win_close, window.id, false)
    end
  end
end

return M
