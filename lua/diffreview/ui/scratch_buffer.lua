local M = {}

local owner_variable = 'diffreview_side_by_side_owner'

---@param instance_id integer
---@param buffer integer|nil
---@return boolean
local function is_owned(instance_id, buffer)
  if buffer == nil or not vim.api.nvim_buf_is_valid(buffer) then
    return false
  end
  local ok, owner = pcall(vim.api.nvim_buf_get_var, buffer, owner_variable)
  return ok and owner == instance_id
end

---@param instance_id integer
---@param buffer integer|nil
---@param name string
---@return integer
local function prepare(instance_id, buffer, name)
  if not is_owned(instance_id, buffer) then
    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buffer, ('diffreview://%d/%s'):format(instance_id, name))
    vim.api.nvim_buf_set_var(buffer, owner_variable, instance_id)
  end
  ---@cast buffer integer
  vim.api.nvim_set_option_value('buftype', 'nofile', { buf = buffer })
  vim.api.nvim_set_option_value('buflisted', false, { buf = buffer })
  vim.api.nvim_set_option_value('swapfile', false, { buf = buffer })
  vim.api.nvim_set_option_value('modifiable', true, { buf = buffer })
  vim.api.nvim_set_option_value('readonly', false, { buf = buffer })
  vim.api.nvim_set_option_value('filetype', '', { buf = buffer })
  return buffer
end

---@param buffer integer
local function lock(buffer)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buffer })
  vim.api.nvim_set_option_value('readonly', true, { buf = buffer })
end

---@param instance_id integer
---@param buffer integer|nil
---@param name string
---@param content DiffSnapshotTextContent
---@return integer
function M.snapshot(instance_id, buffer, name, content)
  buffer = prepare(instance_id, buffer, name)
  vim.api.nvim_set_option_value('fileformat', content.fileformat, { buf = buffer })
  vim.api.nvim_set_option_value('endofline', content.endofline, { buf = buffer })
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, content.lines)
  vim.api.nvim_set_option_value('modified', false, { buf = buffer })
  local filetype = vim.filetype.match({ filename = content.filetype_path, buf = buffer })
  if filetype ~= nil then
    vim.api.nvim_set_option_value('filetype', filetype, { buf = buffer })
  end
  lock(buffer)
  return buffer
end

---@param instance_id integer
---@param buffer integer|nil
---@param name string
---@param lines string[]
---@return integer
function M.information(instance_id, buffer, name, lines)
  buffer = prepare(instance_id, buffer, name)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modified', false, { buf = buffer })
  lock(buffer)
  return buffer
end

return M
