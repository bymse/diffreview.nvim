local comments = require('diffreview.comments')
local view_models = require('helpers.diff_view_model')
local M = {}

M.add_should_accept_sideless_targets_when_an_operation_allowed_version_is_valid = function()
  for _, operation in ipairs({
    'added',
    'untracked',
    'unmerged',
    'deleted',
    'modified',
    'renamed',
    'copied',
    'type_changed',
  }) do
    for _, side in ipairs({ 'old', 'current' }) do
      local diff = { file_id = 'file', operation = operation, [side] = view_models.snapshot('file.txt', { 'text' }) }
      local review = comments.new()
      local record, err = review:add({ file_id = 'file', text = 'whole file' }, diff)
      local allowed = operation == 'deleted' and side == 'old'
        or (operation == 'added' or operation == 'untracked' or operation == 'unmerged') and side == 'current'
        or operation == 'modified'
        or operation == 'renamed'
        or operation == 'copied'
        or operation == 'type_changed'
      if allowed then
        assert(record and err == nil)
        assert(vim.deep_equal(record.target, { file_id = 'file' }))
        assert(vim.deep_equal(assert(review:list()), { record }))
      else
        assert(record == nil and type(err) == 'string' and err ~= '')
        assert(vim.deep_equal(assert(review:list()), {}))
      end
    end
  end
end

M.add_should_preserve_records_when_sideless_inputs_or_diffs_are_invalid = function()
  local review = comments.new()
  local diff = view_models.modified({ 'before' }, { 'after' })
  assert(review:add({ file_id = 'keep', text = 'keep' }, diff))
  local before = assert(review:list())
  ---@param input any
  ---@param supplied any
  ---@return nil
  local function reject(input, supplied)
    local record, err = review:add(input, supplied)
    assert(record == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
  reject({ file_id = 'file', text = 'text' }, nil)
  for _, invalid in ipairs({
    false,
    3,
    '',
    {},
    { operation = 'unknown', current = diff.current },
    { operation = 'error', old = diff.old, current = diff.current },
    { operation = 'modified' },
  }) do
    reject({ file_id = 'file', text = 'text' }, invalid)
  end
  for _, content in ipairs({
    false,
    {},
    { kind = 'unknown' },
    { kind = 'text' },
    { kind = 'text', source = 'path', absolute_path = '' },
    { kind = 'text', source = 'snapshot', lines = { [2] = 'gap' } },
  }) do
    reject(
      { file_id = 'file', text = 'text' },
      { file_id = 'file', operation = 'modified', old = { content = content }, current = { content = content } }
    )
    for _, operation in ipairs({ 'added', 'untracked', 'unmerged', 'deleted' }) do
      local available = operation == 'deleted' and 'old' or 'current'
      local disallowed = available == 'old' and 'current' or 'old'
      reject({ file_id = 'file', text = 'text' }, {
        file_id = 'file',
        operation = operation,
        [available] = { content = content },
        [disallowed] = diff.old,
      })
    end
    for _, side in ipairs({ 'old', 'current' }) do
      local other = side == 'old' and 'current' or 'old'
      local available = {
        file_id = 'file',
        operation = 'modified',
        [side] = { content = content },
        [other] = diff.old,
      }
      assert(comments.new():add({ file_id = 'file', text = 'text' }, available))
    end
  end
  for _, input in ipairs({
    { text = 'text' },
    { file_id = '', text = 'text' },
    { file_id = false, text = 'text' },
    { file_id = 'file' },
    { file_id = 'file', text = '' },
    { file_id = 'file', text = ' \n\t' },
    { file_id = 'file', side = false, text = 'text' },
    { file_id = 'file', side = 'new', text = 'text' },
  }) do
    reject(input, diff)
  end
  for _, range in ipairs({
    { line_start = 1 },
    { line_end = 1 },
    { line_start = 1, line_end = 1 },
    { line_start = 1, line_end = 2 },
    { line_start = 0, line_end = 1 },
    { line_start = 2, line_end = 1 },
    { line_start = false },
    { line_end = '1' },
  }) do
    reject(vim.tbl_extend('force', { file_id = 'file', text = 'text' }, range), diff)
  end
end

M.add_should_accept_sideless_whole_files_when_content_is_binary_empty_or_path_backed = function()
  for _, version in ipairs({
    view_models.binary('binary'),
    view_models.snapshot('empty', {}),
    view_models.path('/repo/file'),
  }) do
    local record = assert(
      comments
        .new()
        :add({ file_id = 'file', text = 'whole' }, { file_id = 'file', operation = 'added', current = version })
    )
    assert(vim.deep_equal(record.target, { file_id = 'file' }))
  end
end

M.add_should_preserve_target_identity_when_sideless_and_explicit_targets_coexist = function()
  local review, other = comments.new(), comments.new()
  local diff = view_models.modified({ 'before', 'two' }, { 'after', 'two' })
  local input = { file_id = 'opaque:file', text = 'first' }
  local whole = assert(review:add(input, diff))
  local different = assert(other:add({ file_id = 'different', text = 'first' }, diff))
  input.text = 'different text'
  diff.old.display_path, diff.current.display_path = 'old-path', 'new-path'
  local same = assert(other:add(input, diff))
  assert(same.id == whole.id and different.id ~= whole.id)
  local ids = { [whole.id] = true, [different.id] = true }
  for _, side in ipairs({ 'old', 'current' }) do
    for _, range in ipairs({ {}, { line_start = 1, line_end = 1 }, { line_start = 1, line_end = 2 } }) do
      local record = assert(review:add(vim.tbl_extend('force', input, { side = side }, range), diff))
      local expected =
        vim.fn.sha256(vim.json.encode({ input.file_id, side, range.line_start or 0, range.line_end or 0 }))
      assert(record.id == expected and not ids[record.id])
      ids[record.id] = true
    end
  end
  for _, resolved in ipairs({ false, true }) do
    if resolved then
      assert(review:resolve(whole.id))
    end
    local before = assert(review:list())
    local duplicate, err = review:add(input, diff)
    assert(duplicate == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
  assert(review:delete(whole.id))
  local restored = assert(review:add(input, diff))
  assert(restored.id == whole.id and restored.state == 'open')
end

M.add_should_detach_sideless_records_when_inputs_and_lifecycle_results_are_mutated = function()
  local review = comments.new()
  local diff = view_models.modified({ 'before' }, { 'after' })
  local input = { file_id = 'file', text = 'original' }
  local created = assert(review:add(input, diff))
  local expected = vim.deepcopy(created)
  input.file_id, input.text, input.side = 'elsewhere', 'changed', 'old'
  diff.current.display_path = 'elsewhere'
  created.target.side, created.target.file_id, created.text = 'current', 'elsewhere', 'changed'
  assert(vim.deep_equal(assert(review:list('file')), { expected }))
  local edited = assert(review:edit(expected.id, 'edited'))
  expected.text = 'edited'
  assert(vim.deep_equal(edited, expected))
  edited.target.side, edited.text = 'old', 'changed'
  local resolved = assert(review:resolve(expected.id))
  expected.state = 'resolved'
  assert(vim.deep_equal(resolved, expected))
  resolved.target.side, resolved.state = 'old', 'stale'
  assert(vim.deep_equal(assert(review:list()), { expected }))
  local reopened = assert(review:reopen(expected.id))
  expected.state = 'open'
  assert(vim.deep_equal(reopened, expected))
  reopened.target.side = 'current'
  local listed = assert(review:list())
  assert(vim.deep_equal(listed, { expected }))
  listed[1].target.side, listed[1].text = 'old', 'changed'
  assert(vim.deep_equal(assert(review:list()), { expected }))
  assert(review:delete(expected.id))
  assert(vim.deep_equal(assert(review:list()), {}))
end

return M
