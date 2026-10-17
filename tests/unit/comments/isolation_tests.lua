local comments = require('diffreview.comments')
local view_models = require('helpers.diff_view_model')
local M = {}

M.add_should_use_supplied_diff_when_views_change_between_calls = function()
  local review = comments.new()
  local original = view_models.modified({ 'before' }, { 'one', 'two' })
  local input = { file_id = 'file', side = 'current', text = 'original', line_start = 1, line_end = 2 }
  local created = assert(review:add(input, original))
  local shorter = view_models.modified({ 'before' }, { 'one' })
  local before = assert(review:list())
  assert(
    review:add({ file_id = 'file', side = 'current', text = 'outside', line_start = 2, line_end = 2 }, shorter) == nil
  )
  assert(vim.deep_equal(assert(review:list()), before))
  local available = assert(
    review:add({ file_id = 'file', side = 'current', text = 'available', line_start = 2, line_end = 2 }, original)
  )
  assert(vim.deep_equal(assert(review:list()), { created, available }))
  local new_file = assert(review:add({ file_id = 'new-file', side = 'current', text = 'new file' }, shorter))
  assert(vim.deep_equal(assert(review:list()), { created, available, new_file }))
end

M.add_should_detach_records_when_arguments_and_results_are_mutated = function()
  local diff = view_models.modified({ 'before' }, { 'one', 'two' })
  local review, other = comments.new(), comments.new()
  local input = { file_id = 'file', side = 'current', text = 'original', line_start = 1, line_end = 2 }
  local created = assert(review:add(input, diff))
  local expected = vim.deepcopy(created)
  diff.current.display_path = 'changed.txt'
  diff.current.content.lines[2] = nil
  input.text, input.file_id, input.line_end = 'changed', 'extra', 99
  created.text, created.id, created.state = 'changed', 'replacement', 'stale'
  created.target.file_id, created.target.line_end = 'elsewhere', 99
  local listed = assert(review:list())
  assert(vim.deep_equal(listed, { expected }))
  listed[1].target.file_id = 'extra'
  listed[1].text = 'list change'
  listed[2] = created
  assert(vim.deep_equal(assert(review:list('file')), { expected }))
  local edited = assert(review:edit(expected.id, 'edited'))
  local expected_edit = vim.deepcopy(edited)
  edited.target.line_start, edited.text = 99, 'changed again'
  assert(vim.deep_equal(assert(review:list()), { expected_edit }))
  assert(vim.deep_equal(assert(other:list()), {}))
  local independent =
    assert(other:add({ file_id = 'file', side = 'current', text = 'independent', line_start = 1, line_end = 1 }, diff))
  assert(review:delete(expected.id))
  assert(vim.deep_equal(assert(other:list()), { independent }))
  assert(vim.deep_equal(assert(review:list()), {}))
end

return M
