local M = {}

---@type ReviewSession|nil
local session = nil

---@return ReviewSession
local function configured_session()
  if session == nil then
    error('diffreview.setup must be called before starting or stopping a review', 3)
  end
  return session
end

---@param options SetupOptions|nil
---@return nil
function M.setup(options)
  if session ~= nil then
    error('diffreview.setup can only be called once', 2)
  end
  local normalized = require('diffreview.config').normalize(options)
  local review_session = require('diffreview.review').new(normalized)
  vim.api.nvim_create_user_command('ReviewStart', function(command)
    local args = command.fargs
    if #args > 2 then
      vim.notify('ReviewStart accepts at most two revisions', vim.log.levels.ERROR)
      return
    end
    review_session:start({ from = args[1], to = args[2] })
  end, { nargs = '*' })
  local registered, registration_error = pcall(vim.api.nvim_create_user_command, 'ReviewStop', function()
    review_session:stop()
  end, { nargs = 0 })
  if not registered then
    vim.api.nvim_del_user_command('ReviewStart')
    error(registration_error, 0)
  end
  session = review_session
end

---@param options ReviewStartOptions|nil
---@return nil
function M.start(options)
  if options == nil then
    options = {}
  end
  configured_session():start(options)
end

---@return nil
function M.stop()
  configured_session():stop()
end

return M
