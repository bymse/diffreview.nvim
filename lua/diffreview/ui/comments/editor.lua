local editor_request = require('diffreview.ui.comments.editor_request')
local M = {}

---@class ReviewCommentSaveRequest
---@field action 'save'|'delete'
---@field target ReviewCommentTarget
---@field comment_id string|nil
---@field text string|nil

---@class ReviewCommentSaveResult
---@field comment_id string|nil

---@alias ReviewCommentSaveHandler fun(request: ReviewCommentSaveRequest): ReviewCommentSaveResult|nil, string|nil

---@class ReviewCommentEditorOptions
---@field target ReviewCommentTarget
---@field display_path string
---@field comment ReviewComment|nil
---@field on_save ReviewCommentSaveHandler
---@field origin_window integer|nil

---@class ReviewCommentEditor
---@field buffer integer
---@field origin integer
---@field target ReviewCommentTarget
---@field display_path string
---@field comment_id string|nil
---@field on_save ReviewCommentSaveHandler
---@field group integer

local owner_variable = 'diffreview_comment_editor_owner'

---@param value any
---@return boolean
local function nonempty(value)
  return type(value) == 'string' and value ~= ''
end

---@param ui ReviewUi
---@return ReviewCommentEditor|nil
local function draft(ui)
  local editor = ui.comment_editor
  if editor ~= nil and vim.api.nvim_buf_is_valid(editor.buffer) then
    local ok, owner = pcall(vim.api.nvim_buf_get_var, editor.buffer, owner_variable)
    if ok and owner == ui.instance_id then
      return editor
    end
  end
  return nil
end

---@param ui ReviewUi
---@param editor ReviewCommentEditor
---@return nil
local function return_focus(ui, editor)
  local tab = ui.tabpage
  if ui.comment_editor ~= nil or tab == nil or not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end
  if vim.api.nvim_win_is_valid(editor.origin) and vim.api.nvim_win_get_tabpage(editor.origin) == tab then
    vim.api.nvim_set_current_win(editor.origin)
  elseif vim.api.nvim_get_current_tabpage() ~= tab then
    vim.api.nvim_set_current_win(vim.api.nvim_tabpage_list_wins(tab)[1])
  end
end

---@param ui ReviewUi
---@param editor ReviewCommentEditor
---@return nil
local function detach(ui, editor)
  if ui.comment_editor == editor then
    ui.comment_editor = nil
  end
  vim.api.nvim_del_augroup_by_id(editor.group)
end

---@param ui ReviewUi
---@param editor ReviewCommentEditor
---@return nil
local function release_after_close(ui, editor)
  detach(ui, editor)
  -- Do not delete a buffer while Neovim is still closing its window.
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(editor.buffer) then
      vim.api.nvim_buf_delete(editor.buffer, { force = true })
    end
    ui.registry:remove_buffer(editor.buffer)
    return_focus(ui, editor)
  end)
end

---@param ui ReviewUi
---@param editor ReviewCommentEditor
---@return nil
local function focus(ui, editor)
  vim.api.nvim_set_current_tabpage(assert(ui.tabpage))
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(ui.tabpage)) do
    if vim.api.nvim_win_get_buf(window) == editor.buffer then
      assert(ui.registry:bind_window(window, editor.buffer, {
        file_id = editor.target.file_id,
        kind = 'editor',
      }))
      vim.api.nvim_set_current_win(window)
      return
    end
  end
  local window = vim.api.nvim_open_win(editor.buffer, true, {
    split = 'below',
    win = -1,
    height = math.max(3, math.floor(vim.o.lines / 4)),
  })
  vim.api.nvim_win_set_var(window, owner_variable, ui.instance_id)
  assert(ui.registry:bind_window(window, editor.buffer, {
    file_id = editor.target.file_id,
    kind = 'editor',
  }))
  vim.wo[window].diff = false
  vim.wo[window].scrollbind = false
  vim.wo[window].cursorbind = false
  vim.wo[window].foldmethod = 'manual'
  local target = editor.target
  local label = editor.display_path .. (target.side and ' [' .. target.side .. ']' or '')
  label = label .. (target.line_start and (' lines %d-%d'):format(target.line_start, target.line_end) or ' whole file')
  vim.wo[window].winbar = label:gsub('%%', '%%%%'):gsub('[\r\n]', ' ')
end

---@param ui ReviewUi
---@return boolean, string|nil
function M.write(ui)
  local editor = draft(ui)
  if editor == nil then
    return false, 'No comment draft is open'
  end
  local text = table.concat(vim.api.nvim_buf_get_lines(editor.buffer, 0, -1, false), '\n')
  local blank = text:match('^%s*$') ~= nil
  if not blank or editor.comment_id ~= nil then
    local request = {
      action = blank and 'delete' or 'save',
      target = vim.deepcopy(editor.target),
      comment_id = editor.comment_id,
      text = not blank and text or nil,
    }
    local ok, result, err = pcall(editor.on_save, request)
    if not ok then
      return false, 'Comment save failed: ' .. tostring(result)
    end
    if err ~= nil and err ~= '' then
      return false, tostring(err)
    end
    if
      type(result) ~= 'table'
      or (blank and result.comment_id ~= nil)
      or (not blank and not nonempty(result.comment_id))
    then
      return false, 'Comment handler returned an invalid save result'
    end
    editor.comment_id = result.comment_id
  end
  if blank then
    vim.api.nvim_buf_set_lines(editor.buffer, 0, -1, false, { '' })
  end
  vim.bo[editor.buffer].modified = false
  return true, nil
end

---@param ui ReviewUi
---@param force boolean|nil
---@return boolean, string|nil
function M.close(ui, force)
  local editor = draft(ui)
  if editor == nil then
    return true, nil
  end
  if vim.bo[editor.buffer].modified and not force then
    return false, 'Comment draft has unsaved changes'
  end
  detach(ui, editor)
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if
      vim.api.nvim_win_get_buf(window) == editor.buffer
      and #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(window)) > 1
    then
      vim.api.nvim_win_close(window, true)
    end
  end
  vim.api.nvim_buf_delete(editor.buffer, { force = true })
  ui.registry:remove_buffer(editor.buffer)
  return_focus(ui, editor)
  return true, nil
end

---@param ui ReviewUi
---@return nil
function M.cleanup(ui)
  M.close(ui, true)
  for buffer, metadata in pairs(ui.registry:resources().buffers) do
    if metadata.purpose == 'comment-editor' and metadata.owned then
      if vim.api.nvim_buf_is_valid(buffer) then
        local ok, owner = pcall(vim.api.nvim_buf_get_var, buffer, owner_variable)
        if ok and owner == ui.instance_id then
          vim.api.nvim_buf_delete(buffer, { force = true })
        end
      end
      ui.registry:remove_buffer(buffer)
    end
  end
end

---@param ui ReviewUi
---@param target ReviewCommentTarget
---@return integer|nil
function M.reuse(ui, target)
  local editor = draft(ui)
  if editor ~= nil and editor_request.same_target(editor.target, target) then
    focus(ui, editor)
    return editor.buffer
  end
  return nil
end

---@param ui ReviewUi
---@param options ReviewCommentEditorOptions Explicit target for lower-level record editing.
---@return integer|nil, string|nil
function M.open(ui, options)
  if type(options) ~= 'table' or not editor_request.valid_target(options.target) then
    return nil, 'A well-formed explicit comment target is required'
  end
  local reused = M.reuse(ui, options.target)
  if reused ~= nil then
    return reused, nil
  end
  local prepared, validation_err = editor_request.validate(ui, options)
  if prepared == nil then
    return nil, validation_err
  end
  options = prepared
  local comment = options.comment
  local closed, err = M.close(ui)
  if not closed then
    return nil, err
  end
  local buffer = vim.api.nvim_create_buf(false, false)
  assert(ui.registry:register_buffer(buffer, { owned = true, purpose = 'comment-editor' }))
  vim.api.nvim_buf_set_var(buffer, owner_variable, ui.instance_id)
  vim.api.nvim_buf_set_name(buffer, ('diffreview://%d/comment-%d'):format(ui.instance_id, buffer))
  vim.bo[buffer].buftype = 'acwrite'
  vim.bo[buffer].bufhidden = ''
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = true
  vim.bo[buffer].readonly = false
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(comment and comment.text or '', '\n', { plain = true }))
  vim.bo[buffer].modified = false
  local editor = {
    buffer = buffer,
    origin = assert(options.origin_window),
    target = vim.deepcopy(options.target),
    display_path = options.display_path,
    comment_id = comment and comment.id or nil,
    on_save = options.on_save,
    group = vim.api.nvim_create_augroup('diffreview.comment_editor.' .. ui.instance_id, { clear = true }),
  }
  ui.comment_editor = editor
  local owned = editor
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    group = owned.group,
    buffer = buffer,
    callback = function()
      local ok, write_err = M.write(ui)
      if not ok then
        -- An actual autocmd error is required: a notification would let :wq discard the draft.
        error(write_err, 0)
      end
    end,
  })
  vim.api.nvim_create_autocmd('QuitPre', {
    group = owned.group,
    buffer = buffer,
    callback = function()
      -- Make native quit check for changes even when 'hidden' is enabled.
      -- Restore the normal hide policy before a successful window departure.
      vim.bo[buffer].bufhidden = 'unload'
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer) then
          vim.bo[buffer].bufhidden = ''
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('BufLeave', {
    group = owned.group,
    buffer = buffer,
    callback = function()
      -- BufWinLeave is too late: native close has already chosen whether to unload.
      vim.bo[buffer].bufhidden = ''
    end,
  })
  vim.api.nvim_create_autocmd('BufHidden', {
    group = owned.group,
    buffer = buffer,
    callback = function()
      if not vim.bo[buffer].modified then
        release_after_close(ui, owned)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufUnload', {
    group = owned.group,
    buffer = buffer,
    callback = function()
      release_after_close(ui, owned)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = owned.group,
    buffer = buffer,
    callback = function()
      detach(ui, owned)
    end,
  })
  focus(ui, owned)
  return buffer, nil
end

return M
