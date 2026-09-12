local M = {}

---@alias quickfix_id integer

local quickfix_title = 'Diff Review'

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

---@param id quickfix_id
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
---@param files ChangedFileViewModel[]
---@return quickfix_id
function M.show_review_files(id, files)
  local action = id == nil and ' ' or 'u'
  local properties = {
    title = quickfix_title,
    context = { plugin = 'diffreview', view = 'review_files' },
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
  select_quickfix_list(quickfix_id)
  vim.cmd('botright copen')

  return quickfix_id
end

return M
