local file_mode = require('diffreview.file_mode')

local M = {}

M.is_valid_mode_should_accept_all_git_modes = function()
  for _, mode in ipairs({ '000000', '100644', '100755', '120000', '160000' }) do
    assert(file_mode.is_valid_mode(mode), 'expected valid mode ' .. mode)
  end
end

M.is_valid_mode_should_reject_unsupported_values = function()
  assert(not file_mode.is_valid_mode('040000'), 'expected unsupported mode to be rejected')
  assert(not file_mode.is_valid_mode(nil), 'expected missing mode to be rejected')
end

M.is_present_mode_should_reject_git_absence_mode = function()
  assert(not file_mode.is_present_mode('000000'), 'expected absence mode to be rejected')
end

M.is_present_mode_should_accept_all_present_diff_modes = function()
  for _, mode in ipairs({ '100644', '100755', '120000', '160000' }) do
    assert(file_mode.is_present_mode(mode), 'expected present mode ' .. mode)
  end
end

M.classify_file_type_should_classify_present_modes = function()
  assert(file_mode.classify_file_type('100644') == 'regular', 'expected regular file')
  assert(file_mode.classify_file_type('100755') == 'regular', 'expected executable regular file')
  assert(file_mode.classify_file_type('120000') == 'symlink', 'expected symbolic link')
  assert(file_mode.classify_file_type('160000') == 'submodule', 'expected submodule')
end

M.display_label_should_describe_present_modes = function()
  assert(file_mode.display_label('100644') == 'file', 'expected file label')
  assert(file_mode.display_label('100755') == 'executable file', 'expected executable label')
  assert(file_mode.display_label('120000') == 'symbolic link', 'expected symlink label')
  assert(file_mode.display_label('160000') == 'submodule', 'expected submodule label')
end

return M
