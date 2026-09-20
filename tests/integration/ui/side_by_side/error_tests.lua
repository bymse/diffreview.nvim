local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

M.display_side_by_side_should_preserve_empty_error_lines_when_content_load_fails = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(
    { operation = 'error', attempted_operation = 'untracked', path = 'bad%\nname', message = 'first\n\nthird' },
    'vertical'
  )
  assert(
    vim.deep_equal(helpers.lines(review_ui), {
      'Content load error',
      'Attempted operation: untracked',
      'Path: bad%\\x0Aname',
      'Error:',
      'first',
      '',
      'third',
    }),
    'expected error message lines'
  )
  helpers.cleanup(review_ui)
end

return M
