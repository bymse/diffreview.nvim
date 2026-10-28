local source = require('diffreview.ui.source')
local M = {}

---@class ReviewCommentEditorContext
---@field target ReviewCommentTarget
---@field display_path string
---@field origin_window integer

---@param target any
---@return boolean
function M.valid_target(target)
  if type(target) ~= 'table' or type(target.file_id) ~= 'string' or target.file_id == '' then
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
function M.same_target(a, b)
  return a.file_id == b.file_id and a.side == b.side and a.line_start == b.line_start and a.line_end == b.line_end
end

---@param ui ReviewUi
---@param buffer integer
---@param window integer
---@return boolean
local function is_source(ui, buffer, window)
  local display = ui.registry:lookup(buffer, window)
  return display ~= nil
    and display.kind == 'source'
    and ui.selected_diff ~= nil
    and display.file_id == ui.selected_diff.file_id
end

---@param ui ReviewUi
---@param buffer integer|nil
---@param line_start integer|nil
---@param line_end integer|nil
---@return ReviewCommentEditorContext|nil, string|nil
function M.resolve(ui, buffer, line_start, line_end)
  local diff = ui.selected_diff
  if diff == nil or ui.tabpage == nil or not vim.api.nvim_tabpage_is_valid(ui.tabpage) then
    return nil, 'No selected review source'
  end
  if buffer == nil or buffer == 0 then
    buffer = vim.api.nvim_get_current_buf()
  end
  if type(buffer) ~= 'number' or buffer < 1 or buffer % 1 ~= 0 or not vim.api.nvim_buf_is_valid(buffer) then
    return nil, 'A valid source buffer is required'
  end
  local origin
  local current = vim.api.nvim_get_current_win()
  if is_source(ui, buffer, current) then
    origin = current
  else
    for _, window in ipairs(vim.api.nvim_tabpage_list_wins(ui.tabpage)) do
      if is_source(ui, buffer, window) then
        if origin ~= nil then
          return nil, 'The source buffer is displayed in more than one review window'
        end
        origin = window
      end
    end
  end
  if origin == nil then
    return nil, 'The buffer is not displayed as review source'
  end
  if line_start == nil and line_end == nil then
    line_start = vim.api.nvim_win_get_cursor(origin)[1]
    line_end = line_start
  end
  local target, err = source.resolve_comment_target(ui.registry, buffer, origin, line_start, line_end)
  if target == nil then
    return nil, err
  end
  if diff.operation == 'error' then
    return nil, 'The selected diff has no source version'
  end
  local version = target.side == 'old' and diff.old or diff.current
  if version == nil then
    return nil, 'The selected source version is unavailable'
  end
  return { target = target, display_path = version.display_path, origin_window = origin }, nil
end

---@param ui ReviewUi
---@param options ReviewCommentEditorOptions
---@return ReviewCommentEditorOptions|nil, string|nil
function M.validate(ui, options)
  if type(options) ~= 'table' or not M.valid_target(options.target) then
    return nil, 'A well-formed explicit comment target is required'
  end
  if type(options.display_path) ~= 'string' or options.display_path == '' or type(options.on_save) ~= 'function' then
    return nil, 'A display path and save handler are required'
  end
  local origin = options.origin_window
  if origin == nil or origin == 0 then
    origin = vim.api.nvim_get_current_win()
  end
  if
    ui.tabpage == nil
    or not vim.api.nvim_tabpage_is_valid(ui.tabpage)
    or type(origin) ~= 'number'
    or origin % 1 ~= 0
    or not vim.api.nvim_win_is_valid(origin)
    or vim.api.nvim_win_get_tabpage(origin) ~= ui.tabpage
  then
    return nil, 'Comment origin must be a window in the review tab'
  end
  local comment = options.comment
  if comment ~= nil then
    if
      type(comment) ~= 'table'
      or not M.valid_target(comment.target)
      or not M.same_target(comment.target, options.target)
      or type(comment.id) ~= 'string'
      or comment.id == ''
      or type(comment.text) ~= 'string'
    then
      return nil, 'Existing comment must agree with the supplied target'
    end
  end
  return {
    target = vim.deepcopy(options.target),
    display_path = options.display_path,
    comment = comment and vim.deepcopy(comment) or nil,
    on_save = options.on_save,
    origin_window = origin,
  },
    nil
end

---@param ui ReviewUi
---@param context ReviewCommentEditorContext
---@return ReviewCommentEditorOptions|nil, string|nil
function M.prepare(ui, context)
  local handlers = ui.handlers
  if handlers == nil or type(handlers.on_comment_save) ~= 'function' then
    return nil, 'A comment save handler must be configured on the review UI'
  end
  local comment
  if handlers.get_comment ~= nil then
    if type(handlers.get_comment) ~= 'function' then
      return nil, 'The comment lookup handler must be a function'
    end
    local ok, result, err = pcall(handlers.get_comment, vim.deepcopy(context.target))
    if not ok then
      return nil, 'Comment lookup failed: ' .. tostring(result)
    end
    if err ~= nil and err ~= '' then
      return nil, tostring(err)
    end
    comment = result
  end
  return {
    target = context.target,
    display_path = context.display_path,
    origin_window = context.origin_window,
    comment = comment,
    on_save = handlers.on_comment_save,
  },
    nil
end

return M
