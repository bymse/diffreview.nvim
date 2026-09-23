local M = {}

---@type Config|nil
local config = nil

---@param options any
---@return Config
local function normalize_setup_options(options)
  if options == nil then
    options = {}
  end
  if type(options) ~= 'table' then
    error('diffreview.setup options must be a table', 2)
  end
  for key, value in pairs(options) do
    if key == 'layout' then
      if value ~= 'horizontal' and value ~= 'vertical' then
        error('diffreview.setup layout must be horizontal or vertical', 2)
      end
    elseif key == 'view' then
      if value ~= 'side_by_side' and value ~= 'inline' then
        error('diffreview.setup view must be side_by_side or inline', 2)
      end
    else
      error('diffreview.setup received an unknown option', 2)
    end
  end
  return { layout = options.layout or 'horizontal', view = options.view or 'side_by_side' }
end

---@return Config
local function configured_config()
  if config == nil then
    error('diffreview.setup must be called before starting or stopping a review', 3)
  end
  return config
end

---@param options SetupOptions|nil
---@return nil
function M.setup(options)
  if config ~= nil then
    error('diffreview.setup can only be called once', 2)
  end
  local normalized = normalize_setup_options(options)
  vim.api.nvim_create_user_command('ReviewStart', function(command)
    local args = command.fargs
    if #args > 2 then
      require('diffreview.review').start(normalized, args)
      return
    end
    require('diffreview.review').start(normalized, { from = args[1], to = args[2] })
  end, { nargs = '*' })
  local registered, registration_error = pcall(vim.api.nvim_create_user_command, 'ReviewStop', function()
    require('diffreview.review').stop()
  end, { nargs = 0 })
  if not registered then
    vim.api.nvim_del_user_command('ReviewStart')
    error(registration_error, 0)
  end
  config = normalized
end

---@param options ReviewStartOptions|nil
---@return nil
function M.start(options)
  if options == nil then
    options = {}
  end
  require('diffreview.review').start(configured_config(), options)
end

---@return nil
function M.stop()
  require('diffreview.review').stop()
end

return M
