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
---@param preview string[]
---@param save fun(editor: CommentEditor, body: string): boolean|nil, string|nil
---@return CommentEditor
function M.open(tab, target, id, body, preview, save)
  local buffer = vim.api.nvim_create_buf(true, false)
  vim.bo[buffer].buftype = 'acwrite'
  vim.bo[buffer].bufhidden = 'hide'
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].filetype = 'text'
  vim.api.nvim_buf_set_name(buffer, 'diffreview://comment/' .. buffer)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(body, '\n', { plain = true }))
  vim.bo[buffer].modified = false
  local virtual_lines = {}
  for _, line in ipairs(preview) do
    virtual_lines[#virtual_lines + 1] = { { line, 'Comment' } }
  end
  vim.api.nvim_buf_set_extmark(buffer, vim.api.nvim_create_namespace('diffreview.comment_editor'), 0, 0, {
    virt_lines = virtual_lines,
    virt_lines_above = true,
  })
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
      vim.bo[buffer].modified = true
      local tick = vim.api.nvim_buf_get_changedtick(buffer)
      local text = table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), '\n')
      local failure
      local running = coroutine.create(function()
        local ok, saved, err = pcall(editor.save, editor, text)
        editor.saving = false
        if not ok or not saved then
          failure = tostring(ok and err or saved)
        elseif vim.api.nvim_buf_is_valid(buffer) and vim.api.nvim_buf_get_changedtick(buffer) == tick then
          vim.bo[buffer].modified = false
        end
      end)
      local ok, err = coroutine.resume(running)
      if not ok then
        editor.saving = false
        failure = tostring(err)
      end
      -- Native :wq must not close the draft before asynchronous capture and persistence finish.
      if not vim.wait(10000, function()
        return not editor.saving
      end) then
        error('Comment save is still pending')
      end
      if failure then
        vim.schedule(function()
          vim.notify(failure, vim.log.levels.ERROR)
        end)
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
