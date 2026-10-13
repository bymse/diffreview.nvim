local M = {}

---@class CommentDecorations
---@field namespace integer
---@field buffers table<integer, boolean>

---@param instance_id integer
---@return CommentDecorations
function M.new_state(instance_id)
  return { namespace = vim.api.nvim_create_namespace('diffreview.comments.' .. instance_id), buffers = {} }
end

---@param state CommentDecorations
---@return nil
function M.clear(state)
  for buffer in pairs(state.buffers) do
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_clear_namespace(buffer, state.namespace, 0, -1)
    end
  end
  state.buffers = {}
end

---@param state CommentDecorations
---@param buffer integer
---@param records ReviewComment[]
---@param file_id string
---@param side 'old'|'current'|nil
---@param main boolean
---@return nil
function M.render(state, buffer, records, file_id, side, main)
  state.buffers[buffer] = true
  local count = vim.api.nvim_buf_line_count(buffer)
  for _, record in ipairs(records) do
    if record.file_id == file_id then
      local file_note = record.start_line == nil or record.status ~= 'open'
      local first, last = record.start_line, record.end_line
      if (file_note and main) or (not file_note and side == 'current' and first and last and last <= count) then
        local text = ('[%s%s] %s'):format(
          record.status == 'stale' and 'stale file note; ' or '',
          record.status,
          record.body:gsub('\n', ' ')
        )
        local options = {
          virt_text = {
            {
              text,
              record.status == 'stale' and 'WarningMsg'
                or (record.status == 'resolved' and 'Comment' or 'DiagnosticInfo'),
            },
          },
        }
        if not file_note then
          options.end_row = last
          options.hl_group = 'DiagnosticUnderlineInfo'
          options.hl_eol = true
        end
        vim.api.nvim_buf_set_extmark(buffer, state.namespace, file_note and 0 or first - 1, 0, options)
      end
    end
  end
end

return M
