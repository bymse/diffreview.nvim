local async = require('diffreview.async')
local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local review = require('diffreview.review')
local ui = require('diffreview.ui')

---@type any
local diffs_adapter = diffs
---@type any
local ui_adapter = ui
---@type any
local vim_api = vim
local M = {}
local config = { layout = 'horizontal', view = 'side_by_side' }

---@param files ChangedFileViewModel[]|nil
---@return DiffLoadResult, LoadedDiffs
local function loaded_result(files)
  return { ok = true, error = nil }, { files = files or {}, repo = {}, entries_by_id = {} }
end

---@param run fun(notifications: { message: string, level: integer }[], fake_ui: ReviewUi)
local function with_review_mocks(run)
  local original_load_review = diffs_adapter.load_review
  local original_get_ui = ui_adapter.get_ui
  local original_notify = vim_api.notify
  local notifications = {}
  local fake_ui = { show_review_files = function() end, cleanup = function() end }
  vim_api.notify = function(message, level)
    table.insert(notifications, { message = message, level = level })
  end
  local ok, err = xpcall(function()
    run(notifications, fake_ui)
  end, debug.traceback)
  review.stop()
  diffs_adapter.load_review = original_load_review
  ui_adapter.get_ui = original_get_ui
  vim_api.notify = original_notify
  assert(ok, err)
end

M.start_should_display_loaded_files_and_cleanup_when_stopped = function()
  with_review_mocks(function(notifications, fake_ui)
    local shown
    local cleaned = 0
    diffs_adapter.load_review = function(options)
      assert(options.cwd == '/explicit', 'expected explicit cwd')
      return loaded_result({
        { id = 'stored:file.txt', display_path = 'file.txt', added_lines = 1, removed_lines = 0, viewed = false },
      })
    end
    fake_ui.show_review_files = function(_, files)
      shown = files
    end
    fake_ui.cleanup = function()
      cleaned = cleaned + 1
    end
    ui_adapter.get_ui = function()
      return fake_ui
    end
    review.start(config, { cwd = '/explicit', from = 'HEAD' })
    assert(shown ~= nil and #shown == 1, 'expected loaded files to be displayed')
    review.start(config, { from = 'HEAD' })
    assert(#notifications == 1 and notifications[1].level == vim.log.levels.ERROR, 'expected conflict notification')
    review.stop()
    assert(cleaned == 1, 'expected active UI cleanup')
    assert(#notifications == 2 and notifications[2].level == vim.log.levels.INFO, 'expected stop notification')
  end)
end

M.start_should_display_real_quickfix_and_preserve_unrelated_resources_when_stopped = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'base' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'changed' })
    vim.fn.setqflist({}, ' ', {
      nr = '$',
      title = 'Unrelated list',
      items = { { text = 'unrelated' } },
      context = { plugin = 'other' },
    })
    local unrelated_id = vim.fn.getqflist({ id = 0 }).id
    local editor_buffer = vim.api.nvim_create_buf(false, true)
    local ok, err = xpcall(function()
      vim.api.nvim_set_current_buf(editor_buffer)
      review.start(config, { cwd = repo.cwd, from = 'HEAD' })
      assert(
        vim.wait(1000, function()
          local quickfix = vim.fn.getqflist({ context = 0, id = 0, items = 1 })
          return type(quickfix.context) == 'table' and quickfix.context.plugin == 'diffreview' and #quickfix.items == 1
        end),
        'expected real review quickfix projection'
      )
      local review_id = vim.fn.getqflist({ id = 0 }).id
      review.stop()
      assert(#vim.fn.getqflist({ id = review_id, items = 1 }).items == 0, 'expected owned quickfix cleanup')
      assert(vim.fn.getqflist({ id = unrelated_id, items = 1 }).items[1].text == 'unrelated', 'expected unrelated list')
      assert(vim.api.nvim_buf_is_valid(editor_buffer), 'expected unrelated editor buffer')
    end, debug.traceback)
    local cleaned, cleanup_error = pcall(function()
      review.stop()
      vim.cmd('silent! cclose')
      if vim.api.nvim_buf_is_valid(editor_buffer) then
        vim.api.nvim_buf_delete(editor_buffer, { force = true })
      end
    end)
    assert(ok, err)
    assert(cleaned, cleanup_error)
  end)
end

M.start_should_notify_and_remain_idle_when_options_are_invalid_or_comparison_is_empty = function()
  with_review_mocks(function(notifications)
    diffs_adapter.load_review = function(options)
      assert(options.cwd == nil, 'expected review to preserve cwd fallback for the loader')
      return loaded_result()
    end
    review.start(config, { to = 'HEAD' })
    review.start(config, {})
    review.stop()
    assert(#notifications == 3, 'expected invalid, empty, and idle notifications')
    assert(notifications[1].level == vim.log.levels.ERROR, 'expected invalid options error')
    assert(notifications[2].level == vim.log.levels.INFO, 'expected empty comparison info')
    assert(notifications[3].level == vim.log.levels.INFO, 'expected idle stop info')
  end)
end

M.start_should_notify_once_at_error_when_ui_creation_fails = function()
  with_review_mocks(function(notifications, fake_ui)
    diffs_adapter.load_review = function()
      return loaded_result({
        { id = 'new:file.txt', display_path = 'file.txt', added_lines = 1, removed_lines = 0, viewed = false },
      })
    end
    ui_adapter.get_ui = function()
      error('UI creation failed')
    end

    review.start(config, {})

    assert(#notifications == 1, 'expected one UI creation notification')
    assert(notifications[1].level == vim.log.levels.ERROR, 'expected UI creation error level')
  end)
end

M.start_should_cleanup_and_notify_once_at_error_when_projection_fails = function()
  with_review_mocks(function(notifications, fake_ui)
    local cleaned = 0
    diffs_adapter.load_review = function()
      return loaded_result({
        { id = 'new:file.txt', display_path = 'file.txt', added_lines = 1, removed_lines = 0, viewed = false },
      })
    end
    fake_ui.show_review_files = function()
      error('projection failed')
    end
    fake_ui.cleanup = function()
      cleaned = cleaned + 1
    end
    ui_adapter.get_ui = function()
      return fake_ui
    end

    review.start(config, {})

    assert(cleaned == 1, 'expected partial UI cleanup')
    assert(#notifications == 1, 'expected one projection notification')
    assert(notifications[1].level == vim.log.levels.ERROR, 'expected projection error level')
  end)
end

M.start_should_reject_second_start_while_loader_is_suspended = function()
  with_review_mocks(function(notifications, fake_ui)
    local original_system = vim_api.system
    local callback
    local ui_creations = 0
    local finished = false
    vim_api.system = function(_, _, completed)
      callback = completed
      return { kill = function() end }
    end
    diffs_adapter.load_review = function(_, operation)
      async.system({ 'git', 'status' }, {}, operation)
      finished = true
      return loaded_result({
        { id = 'new:file.txt', display_path = 'file.txt', added_lines = 1, removed_lines = 0, viewed = false },
      })
    end
    ui_adapter.get_ui = function()
      ui_creations = ui_creations + 1
      return fake_ui
    end
    local ok, err = xpcall(function()
      review.start(config, {})
      review.start(config, {})
      assert(#notifications == 1, 'expected one conflicting-start notification')
      assert(notifications[1].level == vim.log.levels.ERROR, 'expected conflicting-start error level')
      assert(ui_creations == 0 and callback ~= nil, 'expected suspended loader without replacement')
      review.stop()
      callback({ code = 0, signal = 0, stdout = '', stderr = '' })
      assert(
        vim.wait(1000, function()
          return finished
        end),
        'expected canceled loader callback'
      )
    end, debug.traceback)
    vim_api.system = original_system
    assert(ok, err)
  end)
end

M.start_should_complete_lifecycle_once_when_process_callback_is_repeated = function()
  with_review_mocks(function(notifications, fake_ui)
    local original_system = vim_api.system
    local ok, err = xpcall(function()
      local callback
      local displayed = 0
      vim_api.system = function(_, _, completed)
        callback = completed
        return { kill = function() end }
      end
      diffs_adapter.load_review = function(_, operation)
        async.system({ 'git', 'status' }, {}, operation)
        return loaded_result({
          { id = 'new:file.txt', display_path = 'file.txt', added_lines = 1, removed_lines = 0, viewed = false },
        })
      end
      fake_ui.show_review_files = function()
        displayed = displayed + 1
      end
      ui_adapter.get_ui = function()
        return fake_ui
      end
      review.start(config, {})
      assert(callback ~= nil, 'expected suspended process callback')
      callback({ code = 0, signal = 0, stdout = '', stderr = '' })
      callback({ code = 0, signal = 0, stdout = '', stderr = '' })
      assert(
        vim.wait(1000, function()
          return displayed == 1
        end),
        'expected one lifecycle completion'
      )
      assert(displayed == 1, 'expected duplicate callback to avoid a second continuation')
      assert(#notifications == 0, 'expected no lifecycle error notification')
    end, debug.traceback)
    vim_api.system = original_system
    assert(ok, err)
  end)
end

M.stop_should_suppress_late_canceled_start_completion = function()
  with_review_mocks(function(notifications)
    local original_system = vim_api.system
    local ok, err = xpcall(function()
      local callback
      local killed = false
      local finished = false
      vim_api.system = function(_, _, completed)
        callback = completed
        return {
          kill = function()
            killed = true
          end,
        }
      end
      diffs_adapter.load_review = function(_, operation)
        async.system({ 'git', 'status' }, {}, operation)
        finished = true
        return loaded_result({
          { id = 'new:file.txt', display_path = 'file.txt', added_lines = 1, removed_lines = 0, viewed = false },
        })
      end
      review.start(config, {})
      review.stop()
      assert(killed and callback ~= nil, 'expected in-flight process cancellation')
      callback({ code = 0, signal = 0, stdout = '', stderr = '' })
      assert(
        vim.wait(1000, function()
          return finished
        end),
        'expected canceled callback to resume the loader'
      )
      assert(#notifications == 1 and notifications[1].level == vim.log.levels.INFO, 'expected only stop notification')
    end, debug.traceback)
    vim_api.system = original_system
    assert(ok, err)
  end)
end

return M
