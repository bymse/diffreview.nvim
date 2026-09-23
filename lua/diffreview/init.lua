local M = {}

---@class ReviewStartOptions
---@field cwd string|nil
---@field from string|nil
---@field to string|nil

---@type ReviewSession|nil
local session = nil

---@return ReviewSession
local function configured_session()
  if session == nil then
    error('diffreview.setup must be called before starting or stopping a review', 3)
  end
  return session
end

---@param options any
---@return DiffLoadOptions|nil
local function validate_start_options(options)
  if type(options) ~= 'table' then
    return nil
  end
  for key, value in pairs(options) do
    if (key ~= 'cwd' and key ~= 'from' and key ~= 'to') or type(value) ~= 'string' or value == '' then
      return nil
    end
  end
  if options.to ~= nil and options.from == nil then
    return nil
  end
  return options
end

---@param review_session ReviewSession
---@param options any
---@return nil
local function start(review_session, options)
  local valid_options = validate_start_options(options)
  if valid_options == nil then
    vim.notify('Invalid review start options', vim.log.levels.ERROR)
    return
  end
  review_session:start(valid_options)
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
    start(review_session, { from = args[1], to = args[2] })
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
  start(configured_session(), options)
end

---@return nil
function M.stop()
  configured_session():stop()
end

return M
