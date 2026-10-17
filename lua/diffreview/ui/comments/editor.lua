local source = require('diffreview.ui.comments.decorations')
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

---@param target any
---@return boolean
local function valid_target(target)
  if type(target) ~= 'table' or not nonempty(target.file_id) then
    return false
  end
  if target.side ~= nil and target.side ~= 'old' and target.side ~= 'current' then
    return false
  end
  if target.line_start == nil and target.line_end == nil then
    return true
  end
  return target.side ~= nil
    and type(target.line_start) == 'number'
    and target.line_start >= 1
    and target.line_start % 1 == 0
    and type(target.line_end) == 'number'
    and target.line_end >= target.line_start
    and target.line_end % 1 == 0
end

---@param a ReviewCommentTarget
---@param b ReviewCommentTarget
---@return boolean
local function same_target(a, b)
  return a.file_id == b.file_id and a.side == b.side and a.line_start == b.line_start and a.line_end == b.line_end
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
      vim.api.nvim_set_current_win(window)
      return
    end
  end
  local window = vim.api.nvim_open_win(editor.buffer, true, {
    split = 'below',
    win = -1,
    height = math.max(3, math.floor(vim.o.lines / 4)),
  })
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
  return_focus(ui, editor)
  return true, nil
end

---@param ui ReviewUi
---@param target ReviewCommentTarget
---@return boolean
local function displayed_range(ui, target)
  local presentation = ui.side_by_side.presentation
  if presentation == nil or presentation.file_id ~= target.file_id then
    return false
  end
  for _, pane in ipairs(presentation.panes) do
    if
      pane.side == target.side
      and vim.api.nvim_win_is_valid(pane.window)
      and vim.api.nvim_buf_is_valid(pane.buffer)
      and vim.api.nvim_win_get_tabpage(pane.window) == ui.tabpage
      and vim.api.nvim_win_get_buf(pane.window) == pane.buffer
    then
      return target.line_end <= source.source_line_count(pane)
    end
  end
  return false
end

---@param ui ReviewUi
---@param options ReviewCommentEditorOptions
---@return integer|nil, string|nil
function M.open(ui, options)
  if type(options) ~= 'table' or not valid_target(options.target) then
    return nil, 'A well-formed explicit comment target is required'
  end
  local editor = draft(ui)
  if editor ~= nil and same_target(editor.target, options.target) then
    focus(ui, editor)
    return editor.buffer, nil
  end
  if not nonempty(options.display_path) or type(options.on_save) ~= 'function' then
    return nil, 'A display path and save handler are required'
  end
  local tab = ui.tabpage
  local origin = options.origin_window
  if origin == nil or origin == 0 then
    origin = vim.api.nvim_get_current_win()
  end
  if
    tab == nil
    or not vim.api.nvim_tabpage_is_valid(tab)
    or type(origin) ~= 'number'
    or origin % 1 ~= 0
    or not vim.api.nvim_win_is_valid(origin)
    or vim.api.nvim_win_get_tabpage(origin) ~= tab
  then
    return nil, 'Comment origin must be a window in the review tab'
  end
  local comment = options.comment
  if comment ~= nil then
    if
      type(comment) ~= 'table'
      or not valid_target(comment.target)
      or not same_target(comment.target, options.target)
      or not nonempty(comment.id)
      or type(comment.text) ~= 'string'
    then
      return nil, 'Existing comment must agree with the supplied target'
    end
  elseif options.target.line_start ~= nil and not displayed_range(ui, options.target) then
    return nil, 'Comment range must address displayed source lines'
  end
  local closed, err = M.close(ui)
  if not closed then
    return nil, err
  end
  local buffer = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buffer, ('diffreview://%d/comment-%d'):format(ui.instance_id, buffer))
  vim.api.nvim_buf_set_var(buffer, owner_variable, ui.instance_id)
  vim.bo[buffer].buftype = 'acwrite'
  vim.bo[buffer].bufhidden = ''
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = true
  vim.bo[buffer].readonly = false
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, vim.split(comment and comment.text or '', '\n', { plain = true }))
  vim.bo[buffer].modified = false
  editor = {
    buffer = buffer,
    origin = origin,
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
      local ok, write_err = ui:write_comment_editor()
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
