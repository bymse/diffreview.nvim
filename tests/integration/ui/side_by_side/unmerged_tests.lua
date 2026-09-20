local helpers = require('integration.ui.side_by_side.helpers')
local ui = require('diffreview.ui')
local M = {}

M.display_side_by_side_should_render_unmerged_path_buffer_when_conflict_is_current = function()
  local path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile({ 'conflict' }, path)
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'unmerged',
    current = {
      display_path = 'conflict.txt',
      mode = '100644',
      content = { kind = 'text', source = 'path', absolute_path = path },
    },
  }, 'vertical')
  assert(helpers.main_buffer(review_ui) == vim.fn.bufnr(path), 'expected real path buffer')
  helpers.cleanup(review_ui)
  vim.fn.delete(path)
end

M.display_side_by_side_should_not_change_real_buffer_options_when_added_path_is_rendered = function()
  local path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile({ 'local value = 1' }, path)
  local buffer = vim.fn.bufadd(path)
  vim.fn.bufload(buffer)
  local before = {
    modifiable = vim.api.nvim_get_option_value('modifiable', { buf = buffer }),
    readonly = vim.api.nvim_get_option_value('readonly', { buf = buffer }),
    filetype = vim.api.nvim_get_option_value('filetype', { buf = buffer }),
  }
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'added',
    current = {
      display_path = 'path.txt',
      mode = '100644',
      content = { kind = 'text', source = 'path', absolute_path = path },
    },
  }, 'vertical')

  assert(helpers.main_buffer(review_ui) == buffer, 'expected existing real buffer')
  assert(
    vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'local value = 1' }),
    'expected unchanged real content'
  )
  assert(
    vim.deep_equal(before, {
      modifiable = vim.api.nvim_get_option_value('modifiable', { buf = buffer }),
      readonly = vim.api.nvim_get_option_value('readonly', { buf = buffer }),
      filetype = vim.api.nvim_get_option_value('filetype', { buf = buffer }),
    }),
    'expected unchanged real options'
  )
  helpers.cleanup(review_ui)
  vim.fn.delete(path)
end

M.display_side_by_side_should_not_decorate_truly_empty_path_backed_file = function()
  local path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile({}, path)
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'added',
    current = {
      display_path = 'empty.txt',
      mode = '100644',
      content = { kind = 'text', source = 'path', absolute_path = path },
    },
  }, 'vertical')
  local buffer = helpers.main_buffer(review_ui)
  assert(
    #vim.api.nvim_buf_get_extmarks(buffer, review_ui.side_by_side.namespace, 0, -1, {}) == 0,
    'expected no empty-file decoration'
  )
  helpers.cleanup(review_ui)
  vim.fn.delete(path)
end

M.display_side_by_side_should_decorate_newline_only_path_backed_file = function()
  local path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile({ '' }, path)
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'added',
    current = {
      display_path = 'blank.txt',
      mode = '100644',
      content = { kind = 'text', source = 'path', absolute_path = path },
    },
  }, 'vertical')
  local marks = vim.api.nvim_buf_get_extmarks(
    helpers.main_buffer(review_ui),
    review_ui.side_by_side.namespace,
    0,
    -1,
    { details = true }
  )
  assert(
    #marks == 1
      and marks[1][2] == 0
      and marks[1][3] == 0
      and marks[1][4].end_row == 1
      and marks[1][4].hl_group == 'DiffAdd',
    'expected full-line DiffAdd decoration for the logical blank line'
  )
  helpers.cleanup(review_ui)
  vim.fn.delete(path)
end

M.display_side_by_side_should_decorate_unsaved_path_buffer_content_instead_of_disk_content = function()
  local path = vim.fn.tempname() .. '.txt'
  vim.fn.writefile({}, path)
  local buffer = vim.fn.bufadd(path)
  vim.fn.bufload(buffer)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'unsaved' })
  local review_ui = ui.get_ui()
  review_ui:display_diff_side_by_side({
    operation = 'added',
    current = {
      display_path = 'unsaved.txt',
      mode = '100644',
      content = { kind = 'text', source = 'path', absolute_path = path },
    },
  }, 'vertical')
  assert(
    #vim.api.nvim_buf_get_extmarks(buffer, review_ui.side_by_side.namespace, 0, -1, {}) == 1,
    'expected displayed unsaved line decoration'
  )
  helpers.cleanup(review_ui)
  vim.fn.delete(path)
end

return M
