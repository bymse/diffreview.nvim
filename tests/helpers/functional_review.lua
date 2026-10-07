local diffreview = require('diffreview')
local git_repo = require('helpers.git_repo')

local M = {}

---@return nil
function M.ensure_setup()
  if vim.fn.exists(':ReviewStart') == 0 then
    diffreview.setup({ layout = 'vertical' })
  end
end

---@param prepare fun(repo: TestGitRepo): ReviewStartOptions
---@param run fun(repo: TestGitRepo, options: ReviewStartOptions): nil
---@param start_review? boolean
---@return nil
function M.with_review(prepare, run, start_review)
  M.ensure_setup()
  git_repo.with_repo(function(repo)
    local options = prepare(repo)
    local original_cwd = vim.fn.getcwd()
    local ok, err = xpcall(function()
      vim.api.nvim_set_current_dir(repo.cwd)
      if start_review ~= false then
        diffreview.start({ cwd = repo.cwd, from = options.from, to = options.to })
      end
      run(repo, options)
    end, debug.traceback)
    pcall(function()
      diffreview.stop()
    end)
    vim.api.nvim_set_current_dir(original_cwd)
    assert(ok, err)
  end)
end

---@param expected_entries integer
---@return integer
function M.wait_for_list(expected_entries)
  assert(
    vim.wait(2000, function()
      local list = vim.fn.getqflist({ id = 0, title = 1, items = 1 })
      return list.title == 'Diff Review' and #list.items == expected_entries
    end),
    'expected review quickfix entries'
  )
  return vim.fn.getqflist({ id = 0 }).id
end

---@param review_id integer
---@param path string
---@return integer
function M.select_path(review_id, path)
  local list = vim.fn.getqflist({ id = review_id, items = 1, qfbufnr = 1 })
  assert(list.id == review_id and vim.fn.getqflist({ id = 0 }).id == review_id, 'expected active review list')
  local selected
  for row, item in ipairs(list.items) do
    if item.text:sub(-#path) == path and item.text:sub(-#path - 1, -#path - 1) == ' ' then
      assert(selected == nil, 'expected exactly one matching path')
      selected = row
    end
  end
  assert(selected ~= nil, 'expected matching quickfix path')
  local drawer
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local info = vim.fn.getwininfo(win)[1]
    if info.quickfix == 1 and info.loclist == 0 and vim.api.nvim_win_get_buf(win) == list.qfbufnr then
      drawer = win
      break
    end
  end
  assert(drawer ~= nil, 'expected review quickfix window')
  vim.api.nvim_set_current_win(drawer)
  vim.api.nvim_win_set_cursor(drawer, { selected, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'xt', false)
  return selected
end

---@param repo TestGitRepo
---@param path string
---@param content string
---@return nil
function M.wait_for_one_sided_current(repo, path, content)
  assert(
    vim.wait(2000, function()
      local tab = vim.api.nvim_get_current_tabpage()
      local window = vim.api.nvim_get_current_win()
      local buffer = vim.api.nvim_win_get_buf(window)
      return #vim.api.nvim_tabpage_list_wins(tab) == 1
        and vim.api.nvim_buf_get_name(buffer) == repo.cwd .. '/' .. path
        and vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { content })
    end),
    'expected one-sided current worktree presentation'
  )
end

---@param repo TestGitRepo
---@param path string
---@param old_content string|string[]
---@param current_content string|string[]
---@param source string|nil
---@param indication string|nil
---@param tab? integer
---@return nil
function M.wait_for_two_sided_current(repo, path, old_content, current_content, source, indication, tab)
  assert(
    vim.wait(2000, function()
      local target_tab = tab or vim.api.nvim_get_current_tabpage()
      if not vim.api.nvim_tabpage_is_valid(target_tab) then
        return false
      end
      local windows = vim.api.nvim_tabpage_list_wins(target_tab)
      if #windows ~= 2 then
        return false
      end
      local left, right = windows[1], windows[2]
      if vim.api.nvim_win_get_position(left)[2] > vim.api.nvim_win_get_position(right)[2] then
        left, right = right, left
      end
      return vim.api.nvim_win_get_position(left)[2] < vim.api.nvim_win_get_position(right)[2]
        and (target_tab ~= vim.api.nvim_get_current_tabpage() or right == vim.api.nvim_get_current_win())
        and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(right)) == repo.cwd .. '/' .. path
        and vim.deep_equal(
          vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(left), 0, -1, false),
          type(old_content) == 'table' and old_content or { old_content }
        )
        and (source == nil or vim.bo[vim.api.nvim_win_get_buf(left)].buftype == 'nofile')
        and vim.deep_equal(
          vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(right), 0, -1, false),
          type(current_content) == 'table' and current_content or { current_content }
        )
        and (indication == nil or vim.wo[right].winbar:find(indication .. ' ' .. source, 1, true) ~= nil)
        and vim.wo[left].diff
        and vim.wo[right].diff
    end),
    'expected focused two-pane worktree diff with baseline on the left'
  )
end

---@param old_content string
---@return nil
function M.wait_for_one_sided_old(old_content)
  assert(
    vim.wait(2000, function()
      local windows = vim.api.nvim_tabpage_list_wins(0)
      if #windows ~= 1 then
        return false
      end
      local win = windows[1]
      local buffer = vim.api.nvim_win_get_buf(win)
      return win == vim.api.nvim_get_current_win()
        and vim.bo[buffer].buftype == 'nofile'
        and vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { old_content })
        and vim.wo[win].winbar:find('Deleted file', 1, true) ~= nil
        and not vim.wo[win].diff
    end),
    'expected one-sided deleted snapshot without native diff'
  )
end

---@param expected_lines string[]
---@return nil
function M.wait_for_information(expected_lines)
  assert(
    vim.wait(2000, function()
      local windows = vim.api.nvim_tabpage_list_wins(0)
      if #windows ~= 1 then
        return false
      end
      local window = windows[1]
      local buffer = vim.api.nvim_win_get_buf(window)
      if window ~= vim.api.nvim_get_current_win() or vim.bo[buffer].buftype ~= 'nofile' or vim.wo[window].diff then
        return false
      end
      local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
      for _, expected in ipairs(expected_lines) do
        local found = false
        for _, line in ipairs(lines) do
          if line == expected then
            found = true
            break
          end
        end
        if not found then
          return false
        end
      end
      return true
    end),
    'expected focused information view without native diff'
  )
end

---@param repo TestGitRepo
---@param path string
---@param target string
---@return nil
function M.wait_for_one_sided_snapshot(repo, path, target)
  assert(
    vim.wait(2000, function()
      local tab = vim.api.nvim_get_current_tabpage()
      local window = vim.api.nvim_get_current_win()
      local buffer = vim.api.nvim_win_get_buf(window)
      return #vim.api.nvim_tabpage_list_wins(tab) == 1
        and vim.bo[buffer].buftype == 'nofile'
        and vim.api.nvim_buf_get_name(buffer) ~= repo.cwd .. '/' .. path
        and vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { target })
        and vim.wo[window].winbar:find('Added file', 1, true) ~= nil
        and not vim.wo[window].diff
    end),
    'expected one-sided symlink target snapshot'
  )
end

---@param repo TestGitRepo
---@param path string
---@param old_target string
---@param current_target string
---@return nil
function M.wait_for_two_sided_snapshot(repo, path, old_target, current_target)
  assert(
    vim.wait(2000, function()
      local windows = vim.api.nvim_tabpage_list_wins(0)
      if #windows ~= 2 then
        return false
      end
      local right = vim.api.nvim_get_current_win()
      local left = windows[1] == right and windows[2] or windows[1]
      return vim.api.nvim_win_get_position(left)[2] < vim.api.nvim_win_get_position(right)[2]
        and vim.bo[vim.api.nvim_win_get_buf(left)].buftype == 'nofile'
        and vim.bo[vim.api.nvim_win_get_buf(right)].buftype == 'nofile'
        and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(left)) ~= repo.cwd .. '/' .. path
        and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(right)) ~= repo.cwd .. '/' .. path
        and vim.deep_equal(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(left), 0, -1, false), { old_target })
        and vim.deep_equal(
          vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(right), 0, -1, false),
          { current_target }
        )
        and vim.wo[left].diff
        and vim.wo[right].diff
    end),
    'expected two-pane symlink target snapshot diff'
  )
end

return M
