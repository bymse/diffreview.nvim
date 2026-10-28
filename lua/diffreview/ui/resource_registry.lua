local M = {}

---@class ReviewBufferResource
---@field owned boolean
---@field purpose string
---@field snapshot_line_count integer|nil

---@class ReviewDisplayInfo
---@field file_id string
---@field kind 'source'|'information'|'editor'
---@field side ReviewCommentSide|nil
---@field primary boolean|nil

---@class ReviewWindowResource
---@field buffer integer
---@field display ReviewDisplayInfo|nil

---@class ReviewResources
---@field buffers table<integer, ReviewBufferResource>
---@field windows table<integer, ReviewWindowResource>

---@class ReviewFileDisplay
---@field window integer
---@field buffer integer
---@field display ReviewDisplayInfo
---@field metadata ReviewBufferResource

---@class ReviewResourceRegistry
---@field private buffers table<integer, ReviewBufferResource>
---@field private windows table<integer, ReviewWindowResource>
---@field private tabpage integer|nil
local Registry = {}
Registry.__index = Registry

---@param buffer integer
---@param metadata ReviewBufferResource
---@return boolean, string|nil
function Registry:register_buffer(buffer, metadata)
  if not vim.api.nvim_buf_is_valid(buffer) then
    return false, 'Cannot register an unavailable buffer'
  end
  local previous = self.buffers[buffer]
  if previous ~= nil and (previous.owned ~= metadata.owned or previous.purpose ~= metadata.purpose) then
    return false, 'Buffer registration conflicts with its existing ownership or purpose'
  end
  self.buffers[buffer] = vim.deepcopy(metadata)
  return true, nil
end

---@param window integer
---@param buffer integer
---@param display ReviewDisplayInfo|nil Nil invalidates display identity while retaining the window.
---@return boolean, string|nil
function Registry:bind_window(window, buffer, display)
  if
    self.buffers[buffer] == nil
    or not vim.api.nvim_buf_is_valid(buffer)
    or not vim.api.nvim_win_is_valid(window)
    or vim.api.nvim_win_get_buf(window) ~= buffer
  then
    return false, 'A window binding requires a registered buffer displayed in that window'
  end
  local tab = vim.api.nvim_win_get_tabpage(window)
  if self.tabpage ~= nil and tab ~= self.tabpage then
    return false, 'Window belongs to another review tab'
  end
  self.tabpage = tab
  self.windows[window] = { buffer = buffer, display = display and vim.deepcopy(display) or nil }
  return true, nil
end

---@param buffer integer
---@param window integer
---@return ReviewDisplayInfo|nil
function Registry:lookup(buffer, window)
  local binding = self.windows[window]
  if
    binding == nil
    or binding.buffer ~= buffer
    or not vim.api.nvim_buf_is_valid(buffer)
    or not vim.api.nvim_win_is_valid(window)
    or vim.api.nvim_win_get_tabpage(window) ~= self.tabpage
    or vim.api.nvim_win_get_buf(window) ~= buffer
  then
    return nil
  end
  return binding.display and vim.deepcopy(binding.display) or nil
end

---@param file_id string
---@return ReviewFileDisplay[]|nil, string|nil
function Registry:displays_for_file(file_id)
  local displays = {}
  for window, binding in pairs(self.windows) do
    local display = binding.display
    if
      display ~= nil
      and display.file_id == file_id
      and (display.kind == 'source' or display.kind == 'information')
    then
      local associated = self:lookup(binding.buffer, window)
      if associated == nil then
        return nil, 'Displayed source pane is no longer available'
      end
      table.insert(displays, {
        window = window,
        buffer = binding.buffer,
        display = associated,
        metadata = vim.deepcopy(self.buffers[binding.buffer]),
      })
    end
  end
  return displays, nil
end

---@param window integer
---@return nil
function Registry:remove_window(window)
  self.windows[window] = nil
end

---@param buffer integer
---@return nil
function Registry:remove_buffer(buffer)
  self.buffers[buffer] = nil
  for window, binding in pairs(self.windows) do
    if binding.buffer == buffer then
      self.windows[window] = nil
    end
  end
end

---@return ReviewResources
function Registry:resources()
  return { buffers = vim.deepcopy(self.buffers), windows = vim.deepcopy(self.windows) }
end

---@param tabpage integer|nil When omitted, the first successful binding establishes the tab.
---@return ReviewResourceRegistry
function M.new(tabpage)
  return setmetatable({ buffers = {}, windows = {}, tabpage = tabpage }, Registry)
end

return M
