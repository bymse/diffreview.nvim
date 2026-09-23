local config = require('diffreview.config')
local M = {}

---@param options any
---@param expected_error string
local function assert_normalize_fails(options, expected_error)
  local success, normalize_error = pcall(config.normalize, options)
  assert(not success, 'expected normalization to fail')
  assert(tostring(normalize_error):find(expected_error, 1, true) ~= nil, 'expected normalization error')
end

M.normalize_should_return_defaults_when_options_are_omitted = function()
  assert(vim.deep_equal(config.normalize(nil), { layout = 'horizontal', view = 'side_by_side' }))
  assert(vim.deep_equal(config.normalize({}), { layout = 'horizontal', view = 'side_by_side' }))
end

M.normalize_should_preserve_supported_options_when_options_are_valid = function()
  assert(vim.deep_equal(config.normalize({ layout = 'vertical' }), { layout = 'vertical', view = 'side_by_side' }))
  assert(vim.deep_equal(config.normalize({ view = 'inline' }), { layout = 'horizontal', view = 'inline' }))
  assert(vim.deep_equal(config.normalize({ layout = 'vertical', view = 'inline' }), {
    layout = 'vertical',
    view = 'inline',
  }))
end

M.normalize_should_reject_options_when_options_are_not_a_table = function()
  for _, options in ipairs({ false, true, 1, 'options', function() end }) do
    assert_normalize_fails(options, 'diffreview.setup options must be a table')
  end
end

M.normalize_should_reject_layout_when_layout_is_unsupported = function()
  assert_normalize_fails({ layout = 'diagonal' }, 'diffreview.setup layout must be horizontal or vertical')
end

M.normalize_should_reject_view_when_view_is_unsupported = function()
  assert_normalize_fails({ view = 'unified' }, 'diffreview.setup view must be side_by_side or inline')
end

M.normalize_should_reject_options_when_an_option_is_unknown = function()
  assert_normalize_fails({ unknown = true }, 'diffreview.setup received an unknown option')
end

return M
