local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

M.display_side_by_side_should_render_type_information_when_file_type_changes = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side(
    { operation = 'type_changed', old = helpers.binary('entry', '100644'), current = helpers.binary('entry', '120000') },
    'vertical'
  )
  assert(
    vim.deep_equal(helpers.lines(review_ui), {
      'Type change',
      'Operation: type_changed',
      'Path: entry',
      'Old type: regular',
      'Old mode: file (100644)',
      'Old object: a1b2',
      'Old size: 12 bytes',
      'Current type: symlink',
      'Current mode: symbolic link (120000)',
      'Current object: a1b2',
      'Current size: 12 bytes',
      'Text diff is unavailable for a type change.',
    }),
    'expected type information'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_emit_unavailable_binary_metadata_for_text_side = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'modified',
    old = helpers.snapshot('mixed.txt'),
    current = helpers.binary('mixed.txt', '100755'),
    content_changed = false,
  }, 'vertical')
  assert(
    vim.deep_equal(helpers.lines(review_ui), {
      'Binary file',
      'Operation: modified',
      'Path: mixed.txt',
      'Old object: Unavailable',
      'Old size: Unavailable',
      'Current object: a1b2',
      'Current size: 12 bytes',
      'Text diff is unavailable for binary content.',
    }),
    'expected binary metadata for every side'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_not_emit_metadata_when_type_change_is_text_only = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'type_changed',
    old = helpers.snapshot('entry', { 'target' }, '100644'),
    current = helpers.snapshot('entry', { 'target' }, '120000'),
  }, 'vertical')
  assert(
    vim.deep_equal(helpers.lines(review_ui), {
      'Type change',
      'Operation: type_changed',
      'Path: entry',
      'Old type: regular',
      'Old mode: file (100644)',
      'Current type: symlink',
      'Current mode: symbolic link (120000)',
      'Text diff is unavailable for a type change.',
    }),
    'expected text-only type information'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_emit_type_change_metadata_only_for_binary_side = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'type_changed',
    old = helpers.snapshot('entry', { 'target' }, '100644'),
    current = helpers.binary('entry', '120000'),
  }, 'vertical')
  assert(
    vim.deep_equal(helpers.lines(review_ui), {
      'Type change',
      'Operation: type_changed',
      'Path: entry',
      'Old type: regular',
      'Old mode: file (100644)',
      'Current type: symlink',
      'Current mode: symbolic link (120000)',
      'Current object: a1b2',
      'Current size: 12 bytes',
      'Text diff is unavailable for a type change.',
    }),
    'expected only binary-side metadata'
  )
  helpers.cleanup(review_ui)
end

M.display_side_by_side_should_render_unavailable_binary_fields_independently_when_metadata_is_missing = function()
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'type_changed',
    old = { display_path = 'entry', mode = '100644', content = { kind = 'binary', size = 7 } },
    current = { display_path = 'entry', mode = '120000', content = { kind = 'binary', oid = 'cafe' } },
  }, 'vertical')
  assert(
    vim.deep_equal(helpers.lines(review_ui), {
      'Type change',
      'Operation: type_changed',
      'Path: entry',
      'Old type: regular',
      'Old mode: file (100644)',
      'Old object: Unavailable',
      'Old size: 7 bytes',
      'Current type: symlink',
      'Current mode: symbolic link (120000)',
      'Current object: cafe',
      'Current size: Unavailable',
      'Text diff is unavailable for a type change.',
    }),
    'expected independent unavailable binary fields'
  )
  helpers.cleanup(review_ui)
end

return M
