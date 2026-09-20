local validator = require('diffreview.ui.diff_view_model_validator')

local M = {}

local function path_text(path)
  return { kind = 'text', source = 'path', absolute_path = path or '/repo/current.lua' }
end

local function snapshot_text()
  return {
    kind = 'text',
    source = 'snapshot',
    lines = { 'line' },
    endofline = true,
    fileformat = 'unix',
    filetype_path = 'current.lua',
  }
end

local function version(path, mode, content)
  return { display_path = path, mode = mode or '100644', content = content or snapshot_text() }
end

local function assert_invalid(diff)
  local success, error_message = pcall(validator.validate, diff)
  assert(not success, 'expected invalid diff model')
  assert(
    type(error_message) == 'string' and error_message:match('Invalid diff view model'),
    'expected descriptive error'
  )
end

M.validate_should_accept_every_valid_operation_shape = function()
  local current = version('current.lua', '100644', path_text())
  local old = version('old.lua')
  local diffs = {
    { operation = 'added', current = current },
    { operation = 'untracked', current = current },
    { operation = 'deleted', old = old },
    { operation = 'deleted', old = version('old.bin', nil, { kind = 'binary', oid = '1a2B', size = 0 }) },
    { operation = 'deleted', old = version('old.bin', nil, { kind = 'binary' }) },
    { operation = 'modified', old = old, current = current, content_changed = true },
    { operation = 'renamed', old = old, current = current, content_changed = false },
    { operation = 'copied', old = old, current = current, content_changed = false },
    {
      operation = 'type_changed',
      old = version('old.lua', '100644'),
      current = version('current-link', '120000', snapshot_text()),
    },
    { operation = 'unmerged', current = current },
    { operation = 'error', attempted_operation = 'modified', path = 'current.lua', message = 'could not load file' },
  }

  for _, diff in ipairs(diffs) do
    validator.validate(diff)
  end
end

M.validate_should_accept_mode_only_modified_diff_when_content_is_unchanged = function()
  validator.validate({
    operation = 'modified',
    old = version('file.lua', '100644'),
    current = version('file.lua', '100755', path_text()),
    content_changed = false,
  })
end

M.validate_should_accept_rename_and_copy_content_change_values_independent_of_modes = function()
  local diffs = {
    { operation = 'renamed', content_changed = false, old_mode = '100644', current_mode = '100644' },
    { operation = 'renamed', content_changed = true, old_mode = '100644', current_mode = '100755' },
    { operation = 'copied', content_changed = false, old_mode = '100644', current_mode = '100755' },
    { operation = 'copied', content_changed = true, old_mode = '100644', current_mode = '100644' },
  }

  for _, diff in ipairs(diffs) do
    validator.validate({
      operation = diff.operation,
      old = version('old.lua', diff.old_mode),
      current = version('current.lua', diff.current_mode, path_text()),
      content_changed = diff.content_changed,
    })
  end
end

M.validate_should_reject_unsupported_version_modes = function()
  assert_invalid({ operation = 'added', current = version('current.lua', '000000', path_text()) })
  assert_invalid({ operation = 'added', current = version('current.lua', '040000', path_text()) })
end

M.validate_should_reject_empty_display_paths = function()
  assert_invalid({ operation = 'added', current = version('', nil, path_text()) })
end

M.validate_should_reject_nonabsolute_path_text = function()
  assert_invalid({ operation = 'added', current = version('current.lua', nil, path_text('relative.lua')) })
end

M.validate_should_reject_forbidden_old_or_symlink_path_text = function()
  assert_invalid({ operation = 'deleted', old = version('old.lua', nil, path_text()) })
  assert_invalid({ operation = 'added', current = version('link', '120000', path_text()) })
end

M.validate_should_reject_empty_snapshot_filetype_path = function()
  local invalid_filetype_path = snapshot_text()
  invalid_filetype_path.filetype_path = ''
  assert_invalid({ operation = 'deleted', old = version('old.lua', nil, invalid_filetype_path) })
end

M.validate_should_reject_invalid_binary_metadata = function()
  assert_invalid({ operation = 'deleted', old = version('old.bin', nil, { kind = 'binary', oid = 'xyz', size = 1 }) })
  assert_invalid({ operation = 'deleted', old = version('old.bin', nil, { kind = 'binary', oid = '', size = 1 }) })
  assert_invalid({ operation = 'deleted', old = version('old.bin', nil, { kind = 'binary', size = -1 }) })
end

M.validate_should_reject_modified_noops = function()
  assert_invalid({
    operation = 'modified',
    old = version('old.lua'),
    current = version('current.lua', nil, path_text()),
    content_changed = false,
  })
end

M.validate_should_reject_equal_rename_or_copy_paths = function()
  local old = version('same.lua')
  local current = version('same.lua', nil, path_text())
  assert_invalid({ operation = 'renamed', old = old, current = current, content_changed = false })
  assert_invalid({ operation = 'copied', old = old, current = current, content_changed = true })
end

M.validate_should_reject_invalid_type_change_and_unmerged_fields = function()
  assert_invalid({
    operation = 'type_changed',
    old = version('old.lua'),
    current = version('current.lua', '100755', path_text()),
  })
  assert_invalid({ operation = 'unmerged', current = version('current.lua') })
end

M.validate_should_reject_empty_error_fields = function()
  assert_invalid({ operation = 'error', attempted_operation = 'added', path = '', message = 'failed' })
  assert_invalid({ operation = 'error', attempted_operation = 'added', path = 'file.lua', message = '' })
end

return M
