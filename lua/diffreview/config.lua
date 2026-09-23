---@alias ViewLayout 'horizontal'|'vertical'
---@alias ReviewView 'side_by_side'|'inline'
---@class SetupOptions
---@field layout ViewLayout|nil
---@field view ReviewView|nil
---@class Config
---@field layout ViewLayout
---@field view ReviewView

local M = {}

---@param options any
---@return Config
function M.normalize(options)
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

return M
