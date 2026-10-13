local helpers = require('diffreview.ui.quickfix_helpers')
local M = {}

---@class CommentListHandlers
---@field on_comment_navigate? fun(id: string): nil
---@field on_comment_edit? fun(id: string): nil
---@field on_comment_delete? fun(id: string): nil
---@field on_comment_toggle_resolution? fun(id: string): nil
---@field on_comment_begin_attachment? fun(id: string): nil

local comment_rows = {}
local comment_ticks = {}
local comment_bindings = {}

---@param records ReviewComment[]
---@param paths table<string, string>|nil
---@return vim.quickfix.entry[]
local function comment_entries(records, paths)
  local entries = {}
  for _, record in ipairs(records) do
    local location = record.start_line and ('%d-%d'):format(record.start_line, record.end_line) or 'file'
    entries[#entries + 1] = {
      valid = 1,
      text = ('[%s] %s %s — %s'):format(
        record.status,
        paths and paths[record.file_id] or record.file_id,
        location,
        record.body:gsub('\n', ' ')
      ),
      user_data = { comment_id = record.id },
    }
  end
  return entries
end

---@param id quickfix_id|nil
---@param instance_id integer
---@param tab integer
---@param row integer
---@return string|nil
function M.comment_row_id(id, instance_id, tab, row)
  local list = helpers.get_active_owned_list(id, instance_id, 'comments')
  local expected = comment_rows[instance_id]
  if
    not list
    or not expected
    or vim.api.nvim_get_current_tabpage() ~= tab
    or not helpers.displays_quickfix_buffer(vim.api.nvim_get_current_win(), list.qfbufnr)
    or row < 1
    or row > #expected
    or #list.items ~= #expected
    or list.changedtick ~= comment_ticks[instance_id]
  then
    return nil
  end
  for index, item in ipairs(list.items) do
    if not vim.deep_equal(item, expected[index]) then
      return nil
    end
  end
  return list.items[row].user_data.comment_id
end

---@param instance_id integer
---@return nil
local function remove_comment_bindings(instance_id)
  local binding = comment_bindings[instance_id]
  if binding and vim.api.nvim_buf_is_valid(binding.buffer) then
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(binding.buffer, 'n')) do
      if binding.callbacks[mapping.lhs] == mapping.callback then
        vim.api.nvim_buf_del_keymap(binding.buffer, 'n', mapping.lhs)
      end
    end
  end
  comment_bindings[instance_id] = nil
end

---@param id quickfix_id|nil
---@param instance_id integer
---@param records ReviewComment[]
---@param paths table<string, string>|nil
---@return quickfix_id
function M.update_review_comments(id, instance_id, records, paths)
  local cursors = helpers.drawer_cursors()
  local previous = vim.fn.getqflist({ id = 0 }).id
  if not helpers.is_owned(id, instance_id, 'comments') then
    id = nil
  end
  local properties = {
    title = 'Diff Review Comments',
    context = helpers.quickfix_context(instance_id, 'comments'),
    items = comment_entries(records, paths),
    quickfixtextfunc = helpers.format_quickfix_entries,
  }
  if id then
    properties.id = id
  else
    properties.nr = '$'
  end
  assert(vim.fn.setqflist({}, id and 'u' or ' ', properties) == 0, 'failed to update comments')
  id = id or vim.fn.getqflist({ id = 0 }).id
  local list = assert(helpers.get_quickfix_list(id))
  comment_rows[instance_id] = vim.deepcopy(list.items)
  comment_ticks[instance_id] = list.changedtick
  if previous ~= 0 and helpers.get_quickfix_list(previous) then
    helpers.select_quickfix_list(previous)
  end
  helpers.restore_cursors(cursors)
  return id
end

---@param id quickfix_id|nil
---@param instance_id integer
---@param tab integer
---@param records ReviewComment[]
---@param handlers CommentListHandlers
---@param paths table<string, string>|nil
---@return quickfix_id
function M.show_review_comments(id, instance_id, tab, records, handlers, paths)
  id = M.update_review_comments(id, instance_id, records, paths)
  helpers.select_quickfix_list(id)
  vim.cmd('botright copen')
  local buffer = assert(helpers.get_quickfix_list(id)).qfbufnr
  remove_comment_bindings(instance_id)
  local callbacks = {}
  local actions = {
    ['<CR>'] = 'on_comment_navigate',
    e = 'on_comment_edit',
    d = 'on_comment_delete',
    r = 'on_comment_toggle_resolution',
    a = 'on_comment_begin_attachment',
  }
  for key, name in pairs(actions) do
    local callback = function()
      local selected = M.comment_row_id(id, instance_id, tab, vim.api.nvim_win_get_cursor(0)[1])
      local action = handlers[name]
      if selected and action then
        action(selected)
      end
    end
    callbacks[key] = callback
    vim.keymap.set('n', key, callback, { buffer = buffer, silent = true })
  end
  comment_bindings[instance_id] = { buffer = buffer, callbacks = callbacks }
  return id
end

---@param id quickfix_id|nil
---@param instance_id integer
---@return nil
function M.cleanup_comments(id, instance_id)
  remove_comment_bindings(instance_id)
  comment_rows[instance_id] = nil
  comment_ticks[instance_id] = nil
  if helpers.is_owned(id, instance_id, 'comments') then
    helpers.close_drawer(id, instance_id, 'comments')
    vim.fn.setqflist({}, 'r', { id = id, items = {} })
  end
end

return M
