local quickfix = require('diffreview.ui.quickfix')
local native_diff = require('diffreview.ui.native_diff')
local side_by_side = require('diffreview.ui.side_by_side')
local validator = require('diffreview.ui.diff_view_model_validator')
local M = {}

---@class ReviewSideBySideState
---@field namespace integer
---@field main_window integer|nil
---@field companion_window integer|nil
---@field main_snapshot_buffer integer|nil
---@field companion_snapshot_buffer integer|nil
---@field information_buffer integer|nil
---@field decorated_buffer integer|nil
---@field active_layout ViewLayout|nil
---@field native_diff NativeDiffState

---@class ReviewUiHandlers
---@field on_file_selected fun(file_id: string): nil
---@field on_tab_closed fun(): nil

---@class ReviewUi
---@field instance_id integer
---@field tabpage integer|nil
---@field side_by_side ReviewSideBySideState
---@field quickfix_id quickfix_id|nil
---@field handlers ReviewUiHandlers|nil
---@field tab_closed_autocmd integer|nil
---@field tab_acquired boolean
local ReviewUi = {}
ReviewUi.__index = ReviewUi

local next_instance_id = 0

---@param self ReviewUi
---@return integer
local function acquire_tab(self)
  if self.tabpage == nil then
    assert(not self.tab_acquired, 'review tab is closed')
    vim.cmd('tabnew')
    self.tabpage = vim.api.nvim_get_current_tabpage()
    self.tab_acquired = true
    self.tab_closed_autocmd = vim.api.nvim_create_autocmd('TabClosed', {
      callback = function()
        if self.tabpage ~= nil and not vim.api.nvim_tabpage_is_valid(self.tabpage) then
          vim.api.nvim_del_autocmd(self.tab_closed_autocmd)
          self.tab_closed_autocmd = nil
          self.tabpage = nil
          local handlers = self.handlers
          if handlers ~= nil then
            handlers.on_tab_closed()
          end
        end
      end,
    })
  end
  assert(vim.api.nvim_tabpage_is_valid(self.tabpage), 'review tab is closed')
  return self.tabpage
end

---@param tab integer
---@param present fun(): nil
---@return nil
local function present_in_review_tab(tab, present)
  local previous = vim.api.nvim_get_current_tabpage()
  if previous ~= tab then
    vim.api.nvim_set_current_tabpage(tab)
  end
  local ok, err = pcall(present)
  if previous ~= tab and vim.api.nvim_tabpage_is_valid(previous) then
    vim.api.nvim_set_current_tabpage(previous)
  end
  if not ok then
    error(err, 0)
  end
end

---@param files ChangedFileViewModel[]
---@return nil
function ReviewUi:show_review_files(files)
  local handlers = assert(self.handlers, 'review UI handlers are unavailable')
  local tab = acquire_tab(self)
  present_in_review_tab(tab, function()
    quickfix.show_review_files(self.quickfix_id, self.instance_id, files, handlers.on_file_selected, function(id)
      self.quickfix_id = id
    end)
  end)
end

---@param self ReviewUi
---@return boolean
local function in_review_tab(self)
  return self.tabpage ~= nil and vim.api.nvim_get_current_tabpage() == self.tabpage
end

---@return 'diff'|'quickfix'|nil, string|nil
function ReviewUi:mark_context()
  if not in_review_tab(self) then
    return nil, nil
  end
  local window = vim.api.nvim_get_current_win()
  if vim.fn.getwininfo(window)[1].quickfix == 1 then
    local row = vim.api.nvim_win_get_cursor(window)[1]
    local id = quickfix.row_id(self.quickfix_id, self.instance_id, self.tabpage, row)
    return id and 'quickfix' or nil, id
  end
  return 'diff', nil
end

---@param files ChangedFileViewModel[]
---@return boolean
function ReviewUi:toggle_review_files(files)
  if not in_review_tab(self) then
    return false
  end
  if quickfix.drawer_open(self.quickfix_id, self.instance_id, self.tabpage) then
    quickfix.close_drawer(self.quickfix_id, self.instance_id)
  else
    self:show_review_files(files)
  end
  return true
end

---@param files ChangedFileViewModel[]
---@return nil
function ReviewUi:update_review_files(files)
  quickfix.update_review_files(self.quickfix_id, self.instance_id, files)
end

---@return boolean
function ReviewUi:files_open()
  return self.tabpage ~= nil and quickfix.drawer_open(self.quickfix_id, self.instance_id, self.tabpage)
end

---@return nil
function ReviewUi:clear_selected_diff()
  local tab = assert(self.tabpage)
  present_in_review_tab(tab, function()
    side_by_side.clear(self)
  end)
end

---@param diff DiffViewModel
---@param layout ViewLayout
---@return nil
function ReviewUi:refresh_selected_diff(diff, layout)
  self:display_diff_side_by_side(diff, layout, true)
end

---@param diff DiffViewModel
---@param layout ViewLayout
---@param keep_drawer boolean|nil
---@return nil
function ReviewUi:display_diff_side_by_side(diff, layout, keep_drawer)
  validator.validate(diff)
  if layout ~= 'horizontal' and layout ~= 'vertical' then
    error('Invalid view layout: ' .. tostring(layout))
  end
  local tab = acquire_tab(self)
  present_in_review_tab(tab, function()
    if not keep_drawer then
      quickfix.close_drawer(self.quickfix_id, self.instance_id)
    end
    side_by_side.display_side_by_side(self, diff, layout)
  end)
end

---@param diff DiffViewModel
---@return nil
function ReviewUi:display_diff_inlinde(diff) end

---@return nil
function ReviewUi:cleanup()
  self.handlers = nil
  if self.tab_closed_autocmd ~= nil then
    vim.api.nvim_del_autocmd(self.tab_closed_autocmd)
    self.tab_closed_autocmd = nil
  end
  local ok, err = pcall(side_by_side.cleanup, self)
  quickfix.cleanup(self.quickfix_id, self.instance_id)
  self.quickfix_id = nil
  local tab = self.tabpage
  self.tabpage = nil
  if tab ~= nil and vim.api.nvim_tabpage_is_valid(tab) then
    local current = vim.api.nvim_get_current_tabpage()
    if #vim.api.nvim_list_tabpages() == 1 then
      vim.cmd('tabnew')
      current = vim.api.nvim_get_current_tabpage()
    end
    vim.api.nvim_set_current_tabpage(tab)
    vim.cmd('tabclose!')
    if current ~= tab and vim.api.nvim_tabpage_is_valid(current) then
      vim.api.nvim_set_current_tabpage(current)
    end
  end
  if not ok then
    error(err, 0)
  end
end

---@param handlers ReviewUiHandlers
---@return ReviewUi
function M.get_ui(handlers)
  assert(
    handlers ~= nil and type(handlers.on_file_selected) == 'function' and type(handlers.on_tab_closed) == 'function',
    'review UI requires file selection handlers'
  )
  next_instance_id = next_instance_id + 1
  return setmetatable({
    instance_id = next_instance_id,
    tabpage = nil,
    tab_closed_autocmd = nil,
    tab_acquired = false,
    quickfix_id = nil,
    handlers = handlers,
    side_by_side = {
      namespace = vim.api.nvim_create_namespace('diffreview.side_by_side.' .. next_instance_id),
      main_window = nil,
      companion_window = nil,
      main_snapshot_buffer = nil,
      companion_snapshot_buffer = nil,
      information_buffer = nil,
      decorated_buffer = nil,
      active_layout = nil,
      native_diff = native_diff.new_state(),
    },
  }, ReviewUi)
end

return M
