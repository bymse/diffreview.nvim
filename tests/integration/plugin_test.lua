local review = require('diffreview.review')
local async = require('diffreview.async')

---@type any
local review_module = review
---@type any
local vim_api = vim
---@type any
local async_module = async

return {
  plugin_should_validate_setup_and_register_commands_transactionally = function()
    local diffreview = require('diffreview')
    assert(vim.fn.exists(':ReviewStart') == 0, 'expected no command before setup')
    for _, options in ipairs({
      'invalid',
      { unknown = true },
      { layout = true },
      { layout = 'diagonal' },
      { view = true },
      { view = 'tree' },
    }) do
      assert(not pcall(diffreview.setup, options), 'expected setup validation failure')
      assert(vim.fn.exists(':ReviewStart') == 0 and vim.fn.exists(':ReviewStop') == 0, 'expected validation rollback')
    end

    local original_create = vim_api.api.nvim_create_user_command
    local calls = 0
    vim_api.api.nvim_create_user_command = function(...)
      calls = calls + 1
      if calls == 2 then
        error('injected ReviewStop registration failure')
      end
      return original_create(...)
    end
    local registered, registration_error = pcall(diffreview.setup, {})
    vim_api.api.nvim_create_user_command = original_create
    assert(not registered and registration_error ~= nil, 'expected second command registration failure')
    assert(
      vim.fn.exists(':ReviewStart') == 0 and vim.fn.exists(':ReviewStop') == 0,
      'expected command registration rollback'
    )

    diffreview.setup()
    local original_notify = vim_api.notify
    local notifications = {}
    vim_api.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end
    local notify_ok, notify_error = xpcall(function()
      local invalid_start_options = {
        'invalid',
        { unknown = true },
        { cwd = '' },
        { from = '' },
        { to = '' },
        { cwd = true },
        { from = true },
        { to = true },
        { to = 'HEAD' },
      }
      for _, options in ipairs(invalid_start_options) do
        diffreview.start(options)
      end
      assert(#notifications == #invalid_start_options, 'expected public start validation notifications')
      for _, notification in ipairs(notifications) do
        assert(notification.level == vim.log.levels.ERROR, 'expected public start validation error level')
      end
    end, debug.traceback)
    vim_api.notify = original_notify
    assert(notify_ok, notify_error)

    local original_start = review_module.start
    local received_starts = {}
    review_module.start = function(config, options)
      table.insert(received_starts, { config = config, options = options })
    end
    local ok, err = xpcall(function()
      diffreview.start()
      diffreview.start({})
      diffreview.start({ cwd = '/explicit', from = 'from', to = 'to' })
      assert(#received_starts == 3, 'expected public empty start options')
      for _, start in ipairs(received_starts) do
        assert(start.config.layout == 'horizontal' and start.config.view == 'side_by_side', 'expected setup defaults')
      end
      assert(received_starts[3].options.cwd == '/explicit', 'expected explicit public cwd')
      assert(vim.fn.exists(':ReviewStart') == 2 and vim.fn.exists(':ReviewStop') == 2, 'expected registered commands')
      vim.cmd('ReviewStart')
      vim.cmd('ReviewStart HEAD')
      vim.cmd('ReviewStart HEAD HEAD')
      assert(#received_starts == 6, 'expected zero, one, and two command revisions')
      assert(received_starts[4].options.from == nil and received_starts[4].options.to == nil, 'expected zero revisions')
      assert(
        received_starts[5].options.from == 'HEAD' and received_starts[5].options.to == nil,
        'expected one revision'
      )
      assert(
        received_starts[6].options.from == 'HEAD' and received_starts[6].options.to == 'HEAD',
        'expected two revisions'
      )
      assert(not pcall(diffreview.setup, {}), 'expected repeated setup failure')
      assert(vim.fn.exists(':ReviewStart') == 2 and vim.fn.exists(':ReviewStop') == 2, 'expected commands preserved')
    end, debug.traceback)
    review_module.start = original_start
    assert(ok, err)

    notifications = {}
    local original_new_operation = async_module.new_operation
    local operations_started = 0
    ---@type any
    local command_vim = vim
    command_vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end
    async_module.new_operation = function()
      operations_started = operations_started + 1
      return original_new_operation()
    end
    local command_ok, command_error = xpcall(function()
      vim.cmd('ReviewStart one two three')
      assert(#notifications == 1, 'expected one over-arity notification')
      assert(notifications[1].level == vim.log.levels.ERROR, 'expected over-arity error level')
      assert(operations_started == 0, 'expected over-arity to avoid the lifecycle coroutine path')
    end, debug.traceback)
    async_module.new_operation = original_new_operation
    command_vim.notify = original_notify
    assert(command_ok, command_error)
  end,
}
