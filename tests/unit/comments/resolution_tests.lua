local comments = require('diffreview.comments')
local view_models = require('helpers.diff_view_model')
local M = {}

M.resolve_should_preserve_text_targets_and_order_when_feedback_is_edited_and_reopened = function()
  local review = comments.new()
  local diff = view_models.modified({ 'one', 'two' }, { 'one', 'changed' })
  local old =
    assert(review:add({ file_id = 'file', side = 'old', text = 'baseline', line_start = 1, line_end = 2 }, diff))
  local current = assert(review:add({ file_id = 'file', side = 'current', text = 'current' }, diff))
  local extra = assert(review:add({ file_id = 'extra', side = 'current', text = 'extra' }, diff))
  local expected = vim.deepcopy(old)
  expected.state = 'resolved'
  local resolved, err = review:resolve(old.id)
  assert(resolved and err == nil and vim.deep_equal(resolved, expected))
  assert(vim.deep_equal(assert(review:list()), { expected, current, extra }))
  assert(vim.deep_equal(assert(review:list('file')), { expected, current }))
  expected.text = ' \n edited\t '
  local edited, edit_error = review:edit(old.id, expected.text)
  assert(edited and edit_error == nil and vim.deep_equal(edited, expected))
  expected.state = 'open'
  local reopened, reopen_error = review:reopen(old.id)
  assert(reopened and reopen_error == nil and vim.deep_equal(reopened, expected))
  assert(vim.deep_equal(assert(review:list()), { expected, current, extra }))
  assert(vim.deep_equal(assert(review:list('file')), { expected, current }))
end

M.resolve_should_return_detached_records_when_transitions_are_repeated_in_independent_collections = function()
  local review, other = comments.new(), comments.new()
  local diff = view_models.modified({ 'one', 'two' }, { 'one', 'changed' })
  local old = assert(review:add({ file_id = 'file', side = 'old', text = 'old', line_start = 1, line_end = 2 }, diff))
  local current = assert(review:add({ file_id = 'file', side = 'current', text = 'current' }, diff))
  local independent = assert(other:add({ file_id = 'file', side = 'old', text = 'independent' }, diff))
  local expected = vim.deepcopy(old)
  for _, method in ipairs({ 'resolve', 'reopen' }) do
    expected.state = method == 'resolve' and 'resolved' or 'open'
    for _ = 1, 2 do
      local result, err = review[method](review, old.id)
      assert(result and err == nil and vim.deep_equal(result, expected))
      result.id, result.text, result.state = 'changed', 'changed', 'stale'
      result.target.file_id, result.target.line_end = 'elsewhere', 99
      assert(vim.deep_equal(assert(review:list()), { expected, current }))
      assert(vim.deep_equal(assert(other:list()), { independent }))
    end
  end
  local other_resolved = assert(other:resolve(independent.id))
  assert(other_resolved.state == 'resolved')
  assert(vim.deep_equal(assert(review:list()), { expected, current }))
end

M.resolve_should_preserve_records_when_ids_or_resolved_text_edits_are_invalid = function()
  local review = comments.new()
  local diff = view_models.modified({ 'one', 'two' }, { 'one', 'changed' })
  local record = assert(review:add({ file_id = 'file', side = 'old', text = 'keep' }, diff))
  local deleted = assert(review:add({ file_id = 'file', side = 'current', text = 'delete' }, diff))
  assert(review:delete(deleted.id))
  local resolved = assert(review:resolve(record.id))
  local before = assert(review:list())
  ---@param id any
  ---@return nil
  local function reject_id(id)
    for _, method in ipairs({ 'resolve', 'reopen' }) do
      local result, err = review[method](review, id)
      assert(result == nil and type(err) == 'string' and err ~= '')
      assert(vim.deep_equal(assert(review:list()), before))
    end
  end
  reject_id(nil)
  for _, id in ipairs({ 'unknown', deleted.id, '', false, 4, {} }) do
    reject_id(id)
  end
  ---@param text any
  ---@return nil
  local function reject_text(text)
    local result, err = review:edit(record.id, text)
    assert(result == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
  reject_text(nil)
  for _, text in ipairs({ '', ' \t\n', false, 1, {} }) do
    reject_text(text)
  end
  local removed, err = review:delete(resolved.id)
  assert(removed and err == nil and vim.deep_equal(assert(review:list()), {}))
  before = assert(review:list())
  reject_id(resolved.id)
end

return M
