local decorations = require('diffreview.ui.comment_decorations')
local tracker = require('diffreview.ui.decoration_tracker')
local M = {}

---@class ReviewDisplayedView
---@field window integer
---@field buffer integer
---@field file_id string
---@field side 'old'|'current'|nil
---@field file_notes boolean

---@param views ReviewDisplayedView[]
---@param state DecorationTracker
---@param namespace integer
---@param records ReviewComment[]
---@return nil
function M.update(views, state, namespace, records)
  tracker.clear(state, namespace)
  for _, view in ipairs(views) do
    tracker.track(state, namespace, view.buffer)
    decorations.render(namespace, view.buffer, records, view.file_id, view.side, view.file_notes)
  end
end

---@param views ReviewDisplayedView[]
---@param record ReviewComment
---@return boolean
function M.focus(views, record)
  local text_location = record.start_line ~= nil and record.status == 'open'
  for _, view in ipairs(views) do
    if
      view.file_id == record.file_id
      and ((text_location and view.side == 'current') or (not text_location and view.file_notes))
    then
      vim.api.nvim_set_current_win(view.window)
      if text_location and record.start_line <= vim.api.nvim_buf_line_count(view.buffer) then
        vim.api.nvim_win_set_cursor(view.window, { record.start_line, 0 })
      end
      return true
    end
  end
  return false
end

return M
