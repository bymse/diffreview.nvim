local comments = require('diffreview.comments')
local async_operation = require('diffreview.async_operation')
local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local ui = require('diffreview.ui')
local handlers = require('helpers.ui_handlers')
local helpers = require('integration.ui.side_by_side.helpers')

local M = {}
local file_id = 'stored:file.txt'

local function with_capture(run)
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'before', 'same' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'after', 'same' })
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded ~= nil)
    local view = ui.get_ui(handlers)
    local model = assert(diffs.load_selected_view_model(loaded, file_id))
    view:display_diff_side_by_side(model, 'vertical')
    local current, fingerprint = diffs.load_selected_view_model(loaded, file_id, nil, true)
    assert(current ~= nil and diffs.selected_fingerprint_matches(loaded, file_id, async_operation.new(), fingerprint))
    ---@type CommentCaptureContext
    local context = {
      loaded = loaded,
      selected_id = file_id,
      selected_presented = true,
      view_model = current,
      displayed_lines = view:current_text(file_id),
    }
    local ok, err = xpcall(function()
      run(comments.new({}), context, view)
    end, debug.traceback)
    view:cleanup()
    assert(ok, err)
  end)
end

M.add_should_reject_invalid_targets_when_called_without_session_validation = function()
  with_capture(function(state, context)
    local locations = {
      false,
      {},
      { file_id = file_id, side = 'old' },
      { file_id = file_id, end_line = 1 },
      { file_id = file_id, start_line = 0, end_line = 1 },
      { file_id = file_id, start_line = 2, end_line = 1 },
      { file_id = file_id, start_line = 1, end_line = 1.5 },
      { file_id = 'missing' },
      { file_id = file_id, start_line = 1, end_line = 3 },
    }
    for _, location in ipairs(locations) do
      assert(state:add(location, 'note', context) == nil)
    end
    local location = { file_id = file_id, start_line = 1, end_line = 1 }
    context.selected_id = nil
    assert(state:add(location, 'unselected', context) == nil)
    context.selected_id = file_id
    context.selected_presented = false
    assert(state:add(location, 'unpresented', context) == nil)
    context.selected_presented = true
    assert(state:add(location, ' \n', context) == nil)
    assert(#state.records == 0)
    local record = assert(state:add(location, 'valid', context))
    assert(record.anchor_hash == vim.fn.sha256('after') and record.comment_id ~= nil and record.id == nil)
    record.body = 'detached'
    assert(state:resolve(record.comment_id).body == 'valid')
    assert(comments.validate(state.records))
  end)
end

M.add_should_reject_unseen_text_when_display_or_preview_differs_from_snapshot = function()
  with_capture(function(state, context, view)
    local location = { file_id = file_id, start_line = 1, end_line = 1 }
    local buffer = helpers.main_buffer(view)
    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'unsaved' })
    context.displayed_lines = view:current_text(file_id)
    assert(state:add(location, 'unsaved', context) == nil)
    vim.api.nvim_buf_set_lines(buffer, 0, 1, false, { 'after' })
    vim.bo[buffer].modified = false
    context.displayed_lines = view:current_text(file_id)
    context.preview_lines = { 'unseen', 'same' }
    assert(state:add(location, 'unseen', context) == nil)
    assert(#state.records == 0)
    context.preview_lines = { 'after', 'same' }
    assert(state:add(location, 'seen', context).anchor_hash == vim.fn.sha256('after'))
  end)
end

M.add_should_allow_file_notes_when_file_is_not_selected_or_presented = function()
  with_capture(function(state, context)
    context.selected_id = nil
    context.selected_presented = false
    context.view_model = nil
    context.displayed_lines = nil
    local record = assert(state:add({ file_id = file_id }, 'file note', context))
    assert(record.start_line == nil and record.anchor_hash == nil and record.status == 'open')
    assert(comments.validate(state.records))
  end)
end

M.add_should_reject_unavailable_capture_data_when_preloaded_context_cannot_verify_target = function()
  with_capture(function(state, context)
    local location = { file_id = file_id, start_line = 1, end_line = 1 }
    local model = context.view_model
    context.view_model = nil
    assert(state:add(location, 'missing snapshot', context) == nil)
    context.view_model = vim.deepcopy(model)
    context.view_model.file_id = 'other'
    assert(state:add(location, 'wrong snapshot', context) == nil)
    context.view_model = model
    local displayed = context.displayed_lines
    context.displayed_lines = nil
    assert(state:add(location, 'missing display', context) == nil)
    assert(#state.records == 0)
    context.displayed_lines = displayed
    assert(state:add(location, 'verified', context).anchor_hash == vim.fn.sha256('after'))
  end)
end

return M
