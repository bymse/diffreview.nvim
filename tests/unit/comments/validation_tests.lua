local comments = require('diffreview.comments')
local view_models = require('helpers.diff_view_model')
local M = {}

M.add_should_preserve_records_when_supplied_diff_content_is_invalid = function()
  local review = comments.new()
  local diff = view_models.modified({ 'before' }, { 'after' })
  assert(review:add({ file_id = 'keep', side = 'old', text = 'keep' }, diff))
  local before = assert(review:list())
  ---@param invalid any
  ---@return nil
  local function reject(invalid)
    local record, err = review:add({ file_id = 'file', side = 'current', text = 'text' }, invalid)
    assert(record == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
  reject(nil)
  for _, invalid in ipairs({
    false,
    3,
    '',
    {},
    { operation = 'unknown' },
    { operation = 'modified' },
    { operation = 'error', current = diff.current },
  }) do
    reject(invalid)
  end
  for _, side in ipairs({
    false,
    1,
    {},
    { content = false },
    { content = {} },
    { content = { kind = 'unknown' } },
    { content = { kind = 'text' } },
    { content = { kind = 'text', source = 'path', absolute_path = '' } },
  }) do
    reject({ file_id = 'file', operation = 'added', current = side })
  end
  for _, lines in ipairs({
    false,
    'lines',
    { 1 },
    { [2] = 'gap' },
    { [1] = 'one', [3] = 'three' },
    { [0] = 'zero' },
    { extra = 'line' },
    { [1.5] = 'fraction' },
  }) do
    reject({
      file_id = 'file',
      operation = 'added',
      current = { content = { kind = 'text', source = 'snapshot', lines = lines } },
    })
  end
end

M.add_should_leave_records_unchanged_when_text_targets_or_ranges_are_invalid = function()
  local review = comments.new()
  local diff = view_models.modified({ 'unchanged', 'changed', '' }, { 'unchanged', 'new', '' })
  assert(review:add({ file_id = 'keep', side = 'old', text = 'keep' }, diff))
  local before = assert(review:list())
  ---@param input any
  ---@return nil
  local function reject(input)
    local record, err = review:add(input, diff)
    assert(record == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), before))
  end
  reject(nil)
  for _, input in ipairs({ false, 1, 'input', {}, { file_id = 'file', side = 'old' } }) do
    reject(input)
  end
  for _, text in ipairs({ '', ' \n\t\r', false, 3, {} }) do
    reject({ file_id = 'file', side = 'old', text = text })
  end
  for _, file_id in ipairs({ '', false, 3, {} }) do
    reject({ file_id = file_id, side = 'old', text = 'text' })
  end
  reject({ side = 'old', text = 'text' })
  for _, side in ipairs({ '', 'new', 'OLD', false, 3, {} }) do
    reject({ file_id = 'file', side = side, text = 'text' })
  end
  local whole = assert(review:add({ file_id = 'file', text = 'text' }, diff))
  assert(vim.deep_equal(whole.target, { file_id = 'file' }))
  before = assert(review:list())
  for _, range in ipairs({
    { line_start = 1 },
    { line_end = 1 },
    { line_start = 2, line_end = 1 },
    { line_start = 1, line_end = 4 },
    { line_start = 0, line_end = 1 },
    { line_start = -1, line_end = 1 },
    { line_start = 1.5, line_end = 2 },
    { line_start = 1, line_end = 2.5 },
    { line_start = math.huge, line_end = math.huge },
    { line_start = -math.huge, line_end = 1 },
    { line_start = 0 / 0, line_end = 1 },
    { line_start = 1, line_end = 0 / 0 },
    { line_start = '1', line_end = 1 },
    { line_start = 1, line_end = false },
    { line_start = {}, line_end = 1 },
  }) do
    reject(vim.tbl_extend('force', { file_id = 'file', side = 'old', text = 'text' }, range))
  end
end

M.add_should_enforce_side_availability_when_diff_operations_have_only_one_side = function()
  for _, operation in ipairs({ 'added', 'untracked', 'unmerged', 'deleted' }) do
    local review = comments.new()
    local diff = {
      file_id = 'file',
      operation = operation,
      old = view_models.snapshot('file.txt', { 'old' }),
      current = view_models.snapshot('file.txt', { 'new' }),
    }
    local available = operation == 'deleted' and 'old' or 'current'
    local missing = available == 'old' and 'current' or 'old'
    local record = assert(review:add({ file_id = 'file', side = available, text = 'text' }, diff))
    local rejected, err = review:add({ file_id = 'file', side = missing, text = 'text' }, diff)
    assert(rejected == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), { record }))
  end
end

M.add_should_accept_available_snapshots_when_targets_are_whole_file_or_in_bounds = function()
  local review = comments.new()
  local diff = view_models.modified({ 'unchanged', 'changed', '' }, { 'unchanged', 'new', '' })
  for _, side in ipairs({ 'old', 'current' }) do
    local record = assert(
      review:add({ file_id = 'file', side = side, text = ' whole\nfile ', id = 'chosen', state = 'resolved' }, diff)
    )
    assert(record.state == 'open' and record.text == ' whole\nfile ')
    assert(vim.deep_equal(record.target, { file_id = 'file', side = side }))
    local line =
      assert(review:add({ file_id = 'file', side = side, text = 'line', line_start = 1, line_end = 1 }, diff))
    local range =
      assert(review:add({ file_id = 'file', side = side, text = 'range', line_start = 1, line_end = 3 }, diff))
    assert(line.target.line_start == 1 and line.target.line_end == 1)
    assert(range.target.line_start == 1 and range.target.line_end == 3)
  end
  local blank = { file_id = 'blank', operation = 'added', current = view_models.snapshot('blank.txt', { '' }) }
  assert(review:add({ file_id = 'blank', side = 'current', text = 'empty line', line_start = 1, line_end = 1 }, blank))
end

M.add_should_allow_only_whole_file_targets_when_content_is_binary_empty_or_path_backed = function()
  local contents = {
    view_models.binary('binary').content,
    view_models.snapshot('empty.txt', {}).content,
    view_models.path('/repo/file.txt').content,
  }
  for _, content in ipairs(contents) do
    local review = comments.new()
    local diff = {
      file_id = 'file',
      operation = 'added',
      current = { display_path = 'file.txt', mode = '100644', content = content },
    }
    local record = assert(review:add({ file_id = 'file', side = 'current', text = 'whole' }, diff))
    local rejected, err =
      review:add({ file_id = 'file', side = 'current', text = 'line', line_start = 1, line_end = 1 }, diff)
    assert(rejected == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), { record }))
  end
end

return M
