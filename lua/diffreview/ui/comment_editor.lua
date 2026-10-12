local M = {}

---@class CommentEditor
---@field buffer integer
---@field window integer
---@field tab integer
---@field target CommentLocation
---@field id string|nil
---@field saving boolean
---@field detached boolean
---@field save fun(editor: CommentEditor, body: string): boolean|nil, string|nil
local Editor = {}
Editor.__index = Editor

---@return boolean
function Editor:dirty()
  return vim.api.nvim_buf_is_valid(self.buffer) and vim.bo[self.buffer].modified
end

---@return boolean
function Editor:blocked()
  return self.saving or self:dirty()
end

---@return boolean
function Editor:valid()
  return not self.detached and vim.api.nvim_buf_is_valid(self.buffer)
end

---@return nil
function Editor:focus()
  vim.api.nvim_set_current_tabpage(self.tab)
  if vim.api.nvim_win_is_valid(self.window) and vim.api.nvim_win_get_buf(self.window) == self.buffer then
    vim.api.nvim_set_current_win(self.window)
  else
    self.window = vim.api.nvim_open_win(self.buffer, true, { split = 'below' })
  end
end

---@return nil
function Editor:cleanup()
  self.detached = true
  if not self:blocked() and vim.api.nvim_buf_is_valid(self.buffer) then
    vim.api.nvim_buf_delete(self.buffer, { force = true })
  end
end

---@param tab integer
---@param target CommentLocation
---@param id string|nil
---@param body string
---@param save fun(editor: CommentEditor, body: string): boolean|nil, string|nil
---@return CommentEditor
function M.open(tab, target, id, body, save)
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.bo[buffer].buftype = 'acwrite'
  vim.bo[buffer].bufhidden = 'hide'
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = 'text'
  vim.api.nvim_buf_set_name(buffer, 'diffreview://comment/' .. buffer)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(body, '\n', { plain = true }))
  vim.bo[buffer].modified = false
  ---@type CommentEditor
  local editor = setmetatable({
    buffer = buffer,
    window = 0,
    tab = tab,
    target = vim.deepcopy(target),
    id = id,
    saving = false,
    detached = false,
    save = save,
  }, Editor)
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buffer,
    callback = function()
      if editor.saving then
        vim.notify('Comment save is pending', vim.log.levels.ERROR)
        return
      end
      editor.saving = true
      local tick = vim.api.nvim_buf_get_changedtick(buffer)
      local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
      local running = coroutine.create(function()
        local ok, saved, err = pcall(editor.save, editor, text)
        editor.saving = false
        if not ok or not saved then
          vim.notify(tostring(ok and err or saved), vim.log.levels.ERROR)
        elseif vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_changedtick(buffer) == tick then
          vim.bo[buffer].modified = false
        end
      end)
      local ok, err = coroutine.resume(running)
      if not ok then
        editor.saving = false
        vim.notify(tostring(err), vim.log.levels.ERROR)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWinLeave', {
    buffer = buffer,
    callback = function()
      local was_detached = editor.detached
      vim.schedule(function()
        -- A closed review detaches drafts; an explicit editor close cancels them.
        if
          vim.api.nvim_buf_is_valid(buffer)
          and #vim.fn.win_findbuf(buffer) == 0
          and (was_detached or (editor:valid() and vim.api.nvim_tabpage_is_valid(tab)))
        then
          editor.detached = true
          vim.api.nvim_buf_delete(buffer, { force = true })
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buffer,
    callback = function()
      editor.detached = true
    end,
  })
  editor:focus()
  return editor
end

return M
