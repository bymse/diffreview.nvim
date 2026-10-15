local comments = require('diffreview.comments')
local M = {}

M.text_matches_should_require_exact_displayed_lines_when_comparing_snapshot_text = function()
  local cases = {
    { lines = {}, displayed = { '' }, expected = true },
    { lines = { '' }, displayed = { '' }, expected = true },
    { lines = { 'one', 'two' }, displayed = { 'one', 'two' }, expected = true },
    { lines = {}, expected = false },
    { lines = { 'one' }, displayed = { 'changed' }, expected = false },
    { lines = { 'one' }, displayed = { 'one', '' }, expected = false },
    { lines = { 'one', 'two' }, displayed = { 'two', 'one' }, expected = false },
  }
  for _, case in ipairs(cases) do
    assert(comments.text_matches(case.lines, case.displayed) == case.expected)
  end
end

return M
