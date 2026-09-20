local M = {}

local active_instances = {}
local scrollopt_hor_owned = nil
local window_option_names = {
  'diff',
  'scrollbind',
  'cursorbind',
  'wrap',
  'foldmethod',
  'foldcolumn',
  'foldenable',
  'foldlevel',
}

---@class NativeDiffState
---@field active boolean
---@field window_options table<integer, table<string, any>>

---@class NativeDiffTransition
---@field preserve_removed_hor boolean

---@return boolean
local function scrollopt_has_hor()
  return vim.tbl_contains(vim.split(vim.o.scrollopt, ',', { plain = true, trimempty = true }), 'hor')
end

---@param present boolean
local function set_scrollopt_hor(present)
  local result = {}
  for _, value in ipairs(vim.split(vim.o.scrollopt, ',', { plain = true, trimempty = true })) do
    if value ~= 'hor' then
      table.insert(result, value)
    end
  end
  if present then
    table.insert(result, 'hor')
  end
  vim.o.scrollopt = table.concat(result, ',')
end

---@param state NativeDiffState
local function activate(state)
  if not state.active then
    if next(active_instances) == nil then
      scrollopt_hor_owned = not scrollopt_has_hor()
      if scrollopt_hor_owned then
        set_scrollopt_hor(true)
      end
    elseif scrollopt_hor_owned and not scrollopt_has_hor() then
      set_scrollopt_hor(true)
    end
    active_instances[state] = true
    state.active = true
  elseif scrollopt_hor_owned and not scrollopt_has_hor() then
    set_scrollopt_hor(true)
  end
end

---@param state NativeDiffState
local function release(state)
  if not state.active then
    return
  end
  active_instances[state] = nil
  state.active = false
  if next(active_instances) == nil then
    if scrollopt_hor_owned then
      set_scrollopt_hor(false)
    end
    scrollopt_hor_owned = nil
  elseif scrollopt_hor_owned and not scrollopt_has_hor() then
    set_scrollopt_hor(true)
  end
end

---@return NativeDiffState
function M.new_state()
  return { active = false, window_options = {} }
end

---@param state NativeDiffState
---@param windows integer[]
---@param release_active boolean
---@param active_window_lost boolean
---@return NativeDiffTransition
function M.reset(state, windows, release_active, active_window_lost)
  local preexisting_hor_missing = scrollopt_hor_owned == false and not scrollopt_has_hor()
  local restore_preexisting_hor = scrollopt_hor_owned == false and scrollopt_has_hor()

  for _, window in ipairs(windows) do
    local options = state.window_options[window]
    if options ~= nil then
      vim.api.nvim_win_call(window, function()
        vim.cmd('silent! diffoff')
      end)
      for option, value in pairs(options) do
        vim.api.nvim_set_option_value(option, value, { win = window })
      end
    end
  end
  state.window_options = {}

  if restore_preexisting_hor and not scrollopt_has_hor() then
    set_scrollopt_hor(true)
  end
  if release_active then
    release(state)
  end
  if active_window_lost and preexisting_hor_missing then
    set_scrollopt_hor(true)
  end

  return { preserve_removed_hor = not active_window_lost and preexisting_hor_missing }
end

---@param state NativeDiffState
---@param windows integer[]
---@param transition NativeDiffTransition
---@return nil
function M.enable(state, windows, transition)
  activate(state)
  for _, window in ipairs(windows) do
    local options = {}
    for _, option in ipairs(window_option_names) do
      options[option] = vim.api.nvim_get_option_value(option, { win = window })
    end
    state.window_options[window] = options
    vim.api.nvim_win_call(window, function()
      vim.cmd('diffthis')
    end)
  end
  if transition.preserve_removed_hor then
    set_scrollopt_hor(false)
  end
end

return M
