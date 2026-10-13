local quickfix = require('diffreview.ui.quickfix')
local native_diff = require('diffreview.ui.native_diff')
local side_by_side = require('diffreview.ui.side_by_side')
local validator = require('diffreview.ui.diff_view_model_validator')
local comment_decorations = require('diffreview.ui.comment_decorations')
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
---@field main_buffer integer|nil
---@field companion_buffer integer|nil
---@field main_side 'old'|'current'|nil
---@field presented_id string|nil
---@field comments CommentDecorations

---@class ReviewUiHandlers
---@field on_file_selected fun(file_id: string): nil
---@field on_tab_closed fun(): nil
---@field on_comment_action? fun(key: string, id: string): nil

---@class ReviewUi
---@field instance_id integer
---@field tabpage integer|nil
---@field side_by_side ReviewSideBySideState
---@field quickfix_id quickfix_id|nil
---@field comment_quickfix_id quickfix_id|nil
---@field comment_paths table<string, string>|nil
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

---@param first integer|nil
---@param last integer|nil
---@return CommentLocation|nil
function ReviewUi:comment_context(first, last)
  if not in_review_tab(self) then
    return nil
  end
  local window = vim.api.nvim_get_current_win()
  if vim.fn.getwininfo(window)[1].quickfix == 1 then
    local row = vim.api.nvim_win_get_cursor(window)[1]
    local id = quickfix.row_id(self.quickfix_id, self.instance_id, self.tabpage, row)
    return id and { file_id = id } or nil
  end
  local id, side = side_by_side.comment_context(self, window)
  if id == nil or side == 'old' then
    return nil
  end
  if side == nil then
    return { file_id = id }
  end
  local line = vim.api.nvim_win_get_cursor(window)[1]
  return { file_id = id, start_line = first or line, end_line = last or line }
end

---@param id string
---@param side 'old'|'current'
---@param lines string[]
---@return boolean
function ReviewUi:comment_text_matches(id, side, lines)
  return side_by_side.text_matches(self, id, side, lines)
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

---@return boolean
function ReviewUi:comments_open()
  return self.tabpage ~= nil
    and quickfix.drawer_open(self.comment_quickfix_id, self.instance_id, self.tabpage, 'comments')
end

---@param records ReviewComment[]
---@param files ReviewFileRecord[]|nil
---@return nil
function ReviewUi:update_review_comments(records, files)
  if files then
    self.comment_paths = {}
    for _, file in ipairs(files) do
      self.comment_paths[file.id] = file.display_path
    end
  end
  self.comment_quickfix_id =
    quickfix.update_review_comments(self.comment_quickfix_id, self.instance_id, records, self.comment_paths)
  side_by_side.update_comments(self, records)
end

---@param records ReviewComment[]
---@return nil
function ReviewUi:show_review_comments(records)
  local tab = acquire_tab(self)
  present_in_review_tab(tab, function()
    self.comment_quickfix_id = quickfix.show_review_comments(
      self.comment_quickfix_id,
      self.instance_id,
      tab,
      records,
      function(key, id)
        if self.handlers and self.handlers.on_comment_action then
          self.handlers.on_comment_action(key, id)
        end
      end,
      self.comment_paths
    )
  end)
end

---@param records ReviewComment[]
---@return boolean
function ReviewUi:toggle_review_comments(records)
  if not in_review_tab(self) then
    return false
  end
  if self:comments_open() then
    quickfix.close_drawer(self.comment_quickfix_id, self.instance_id, 'comments')
  else
    self:show_review_comments(records)
  end
  return true
end

---@param record ReviewComment
---@return boolean
function ReviewUi:focus_comment(record)
  return side_by_side.focus_comment(self, record)
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
---@param file_id string|nil
---@return nil
function ReviewUi:refresh_selected_diff(diff, layout, file_id)
  self:display_diff_side_by_side(diff, layout, true, file_id)
end

---@param diff DiffViewModel
---@param layout ViewLayout
---@param keep_drawer boolean|nil
---@param file_id string|nil
---@return nil
function ReviewUi:display_diff_side_by_side(diff, layout, keep_drawer, file_id)
  validator.validate(diff)
  if layout ~= 'horizontal' and layout ~= 'vertical' then
    error('Invalid view layout: ' .. tostring(layout))
  end
  local tab = acquire_tab(self)
  present_in_review_tab(tab, function()
    if not keep_drawer then
      quickfix.close_drawer(self.quickfix_id, self.instance_id)
      quickfix.close_drawer(self.comment_quickfix_id, self.instance_id, 'comments')
    end
    side_by_side.display_side_by_side(self, diff, layout)
    self.side_by_side.presented_id = diff.operation ~= 'error' and file_id or nil
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
  quickfix.cleanup_comments(self.comment_quickfix_id, self.instance_id)
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
      comments = comment_decorations.new_state(next_instance_id),
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
