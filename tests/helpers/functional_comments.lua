local review = require('helpers.functional_review')
local diffs = require('diffreview.diffs')
local storage = require('diffreview.storage')
local M = {}

---@param run fun(repo: TestGitRepo, saved: fun(): ReviewProgress): nil
---@return nil
function M.with_review(run)
  review.with_review(function(repo)
    repo:write_file('file.txt', { 'one', 'anchor', 'three' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'one', 'anchor', 'changed' })
    return { from = 'HEAD' }
  end, function(repo)
    review.wait_for_list(1)
    local _, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(loaded)
    run(repo, function()
      return assert(storage.load(loaded.storage_path, loaded.identity))
    end)
  end)
end

---@param keys string
---@return nil
function M.keys(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt', false)
end

---@param body string
---@param saved fun(): ReviewProgress
---@return integer
function M.write(body, saved)
  local buffer = vim.api.nvim_get_current_buf()
  assert(vim.bo[buffer].buftype == 'acwrite')
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { body })
  vim.cmd('write')
  assert(vim.wait(2000, function()
    for _, record in ipairs(saved().comments) do
      if record.body == body then
        return not vim.bo[buffer].modified
      end
    end
    return false
  end))
  return buffer
end

---@param row integer
---@return integer
function M.row(row)
  local list = vim.fn.getqflist({ id = 0, qfbufnr = 1, title = 1 })
  assert(list.title == 'Diff Review Comments')
  for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(window) == list.qfbufnr then
      vim.api.nvim_set_current_win(window)
      vim.api.nvim_win_set_cursor(window, { row, 0 })
      return list.id
    end
  end
  error('expected comment drawer')
end

---@return nil
function M.close_editor()
  local buffer = vim.api.nvim_get_current_buf()
  vim.cmd('close')
  assert(vim.wait(1000, function()
    return not vim.api.nvim_buf_is_valid(buffer)
  end))
end

return M
