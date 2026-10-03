return {
  plugin_should_load_without_registering_commands = function()
    assert(vim.g.loaded_diffreview == true)
    assert(package.loaded.diffreview ~= nil)
    assert(vim.fn.exists(':ReviewStart') == 0, 'expected setup-dependent commands to be absent')
    assert(vim.fn.exists(':ReviewStop') == 0, 'expected setup-dependent commands to be absent')
  end,
}
