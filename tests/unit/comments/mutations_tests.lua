local comments = require('diffreview.comments')
local view_models = require('helpers.diff_view_model')
local M = {}

M.add_should_preserve_order_and_identity_when_comments_are_edited_and_deleted = function()
  local review = comments.new()
  local diff = view_models.modified({ 'one', 'two', 'three' }, { 'one', 'changed', 'three' })
  local added = { operation = 'added', current = view_models.snapshot('b.txt', { 'b' }) }
  assert(vim.deep_equal(assert(review:list()), {}))
  local first, err = review:add({ file_id = 'opaque:a', side = 'old', text = ' whole file ' }, diff)
  assert(first and err == nil and first.state == 'open' and type(first.id) == 'string' and first.id ~= '')
  assert(vim.deep_equal(first.target, { file_id = 'opaque:a', side = 'old' }))
  local second =
    assert(review:add({ file_id = 'new:b', side = 'current', text = 'b', line_start = 1, line_end = 1 }, added))
  local third =
    assert(review:add({ file_id = 'opaque:a', side = 'current', text = 'range', line_start = 1, line_end = 3 }, diff))
  local edited, edit_error = review:edit(first.id, ' \n edited\t ')
  assert(edited and edit_error == nil)
  assert(edited.id == first.id and edited.state == first.state and vim.deep_equal(edited.target, first.target))
  assert(edited.text == ' \n edited\t ')
  assert(vim.deep_equal(assert(review:list()), { edited, second, third }))
  assert(vim.deep_equal(assert(review:list('opaque:a')), { edited, third }))
  assert(vim.deep_equal(assert(review:list('unknown')), {}))
  local deleted, delete_error = review:delete(second.id)
  assert(deleted and delete_error == nil)
  assert(vim.deep_equal(assert(review:list()), { edited, third }))
  local restored =
    assert(review:add({ file_id = 'new:b', side = 'current', text = 'later', line_start = 1, line_end = 1 }, added))
  assert(restored.id == second.id and restored.text == 'later' and restored.state == 'open')
  assert(vim.deep_equal(assert(review:list()), { edited, third, restored }))
end

M.edit_should_preserve_records_when_ids_or_text_are_invalid = function()
  local review = comments.new()
  local diff = view_models.modified({ 'one' }, { 'changed' })
  local record = assert(review:add({ file_id = 'opaque:a', side = 'old', text = 'keep' }, diff))
  local deleted = assert(review:add({ file_id = 'opaque:a', side = 'current', text = 'delete' }, diff))
  assert(review:delete(deleted.id))
  local before = assert(review:list())
  for _, id in ipairs({ 'unknown', deleted.id, '', false, 4, {} }) do
    local edited, err = review:edit(id, 'change')
    assert(edited == nil and type(err) == 'string' and err ~= '')
    local removed, remove_error = review:delete(id)
    assert(removed == false and type(remove_error) == 'string' and remove_error ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
  ---@diagnostic disable-next-line: param-type-mismatch -- Exercise invalid public inputs.
  assert(review:edit(nil, 'change') == nil)
  ---@diagnostic disable-next-line: param-type-mismatch
  assert(review:delete(nil) == false)
  for _, text in ipairs({ '', ' \t\n', false, 1, {} }) do
    local edited, err = review:edit(record.id, text)
    assert(edited == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  assert(review:edit(record.id, nil) == nil)
  for _, filter in ipairs({ false, 1, {} }) do
    ---@diagnostic disable-next-line: param-type-mismatch
    local listed, err = review:list(filter)
    assert(listed == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
end

M.add_should_derive_identity_from_target_when_text_order_or_diff_paths_differ = function()
  local review, other = comments.new(), comments.new()
  local diff = view_models.modified({ 'one', 'two' }, { 'changed', 'two' })
  local input = { file_id = 'opaque:a:old:1', side = 'current', text = 'first', line_start = 1, line_end = 2 }
  local first = assert(review:add(input, diff))
  local before = assert(review:list())
  for _, text in ipairs({ 'first', 'different' }) do
    input.text = text
    local duplicate, err = review:add(input, diff)
    assert(duplicate == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
  assert(review:resolve(first.id))
  local resolved = assert(review:list())
  assert(review:add(input, diff) == nil)
  assert(vim.deep_equal(assert(review:list()), resolved))
  local different_file =
    assert(other:add({ file_id = 'another', side = 'current', text = 'other', line_start = 1, line_end = 2 }, diff))
  diff.current.display_path = 'renamed.txt'
  local same_target = assert(other:add(input, diff))
  assert(same_target.id == first.id)
  local old =
    assert(review:add({ file_id = input.file_id, side = 'old', text = 'old', line_start = 1, line_end = 2 }, diff))
  local whole = assert(review:add({ file_id = input.file_id, side = 'current', text = 'whole' }, diff))
  local line =
    assert(review:add({ file_id = input.file_id, side = 'current', text = 'line', line_start = 1, line_end = 1 }, diff))
  local second_line = assert(
    review:add({ file_id = input.file_id, side = 'current', text = 'second', line_start = 2, line_end = 2 }, diff)
  )
  local ids = {}
  for _, record in ipairs({ first, different_file, old, whole, line, second_line }) do
    assert(not ids[record.id])
    ids[record.id] = true
  end
  assert(review:delete(first.id))
  local restored = assert(review:add(input, diff))
  assert(restored.id == first.id and restored.state == 'open' and restored.text == input.text)
  assert(vim.deep_equal(assert(review:list()), { old, whole, line, second_line, restored }))
end

return M
