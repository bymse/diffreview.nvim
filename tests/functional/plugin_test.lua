local git_repo = require('helpers.git_repo')

return {
  plugin_should_expose_setup_commands_and_command_arity_behavior = function()
    assert(vim.g.loaded_diffreview == true)
    assert(package.loaded.diffreview ~= nil)
    assert(vim.fn.exists(':ReviewStart') == 0, 'expected setup-dependent commands to be absent')

    local diffreview = require('diffreview')
    diffreview.setup({})
    assert(vim.fn.exists(':ReviewStart') == 2, 'expected ReviewStart command')
    assert(vim.fn.exists(':ReviewStop') == 2, 'expected ReviewStop command')

    local notifications = {}
    ---@type any
    local vim_api = vim
    local original_notify = vim_api.notify
    vim_api.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end
    local ok, err = xpcall(function()
      diffreview.start({ to = 'HEAD' })
      assert(
        #notifications == 1 and notifications[1].message == 'Invalid review start options',
        'expected public start validation error'
      )
      git_repo.with_repo(function(repo)
        repo:write_file('file.txt', { 'base' })
        repo:add('file.txt')
        repo:commit('base')
        repo:write_file('file.txt', { 'changed' })
        local original_cwd = vim.fn.getcwd()
        local cwd_ok, cwd_err = xpcall(function()
          vim.api.nvim_set_current_dir(repo.cwd)
          vim.cmd('ReviewStart HEAD')
          assert(
            vim.wait(1000, function()
              local quickfix = vim.fn.getqflist({ context = 0, id = 0 })
              return type(quickfix.context) == 'string' and quickfix.context:match('^diffreview:files:') ~= nil
            end),
            'expected command cwd review to become active'
          )
          local quickfix_id = vim.fn.getqflist({ id = 0 }).id
          vim.cmd('ReviewStart one two three')
          assert(
            #notifications == 2 and notifications[2].level == vim.log.levels.ERROR,
            'expected one command validation error'
          )
          assert(vim.fn.getqflist({ id = 0 }).id == quickfix_id, 'expected active review to remain unchanged')
          local stopped, stop_error = pcall(function()
            vim.cmd('ReviewStop unexpected')
          end)
          assert(not stopped and stop_error ~= nil, 'expected native command arity error')
          assert(#notifications == 2, 'expected no plugin notification from invalid ReviewStop')
          assert(vim.fn.getqflist({ id = 0 }).id == quickfix_id, 'expected invalid stop to preserve active review')
          vim.cmd('ReviewStop')
        end, debug.traceback)
        vim.api.nvim_set_current_dir(original_cwd)
        assert(cwd_ok, cwd_err)
      end)
    end, debug.traceback)
    vim_api.notify = original_notify
    assert(ok, err)

    assert(not pcall(diffreview.setup, {}), 'expected setup to remain single-use')
  end,
}
