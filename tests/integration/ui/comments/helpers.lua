local M = {}
M.models = require('helpers.diff_view_model')

---@param run fun(review_ui: ReviewUi): nil
---@return nil
function M.with_ui(run)
  local review_ui = require('diffreview.ui').get_ui(require('helpers.ui_handlers'))
  local ok, err = xpcall(function()
    run(review_ui)
  end, debug.traceback)
  review_ui:cleanup()
  assert(ok, err)
end

---@param text string
---@param side ReviewCommentSide|nil
---@param first integer|nil
---@param last integer|nil
---@param state ReviewCommentState|nil
---@return ReviewComment
function M.comment(text, side, first, last, state)
  return {
    id = text,
    text = text,
    state = state or 'open',
    target = { file_id = 'file', side = side, line_start = first, line_end = last },
  }
end

---@param review_ui ReviewUi
---@param first_line string
---@return integer, integer
function M.pane(review_ui, first_line)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(assert(review_ui.tabpage))) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == first_line then
      return buf, win
    end
  end
  error('source pane not found: ' .. first_line)
end

---@param buffer integer
---@return table[]
function M.blocks(buffer)
  local blocks = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buffer, -1, 0, -1, { details = true })) do
    if mark[4].virt_lines then
      local text = {}
      for _, line in ipairs(mark[4].virt_lines) do
        local chunks = {}
        for _, chunk in ipairs(line) do
          table.insert(chunks, chunk[1])
        end
        table.insert(text, table.concat(chunks))
      end
      table.insert(blocks, { row = mark[2], above = mark[4].virt_lines_above, text = text })
    end
  end
  return blocks
end

return M
