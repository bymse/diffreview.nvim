local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand('<sfile>:p')), ':h:h')
vim.opt.runtimepath = { root, vim.env.VIMRUNTIME }
vim.opt.packpath = { vim.env.VIMRUNTIME }
package.path = table.concat({
  root .. '/?.lua',
  root .. '/tests/?.lua',
  root .. '/tests/?/init.lua',
  package.path,
}, ';')

local sandbox_name = vim.env.DIFFREVIEW_SANDBOX_NAME or ''
local sandbox_path
if sandbox_name == '' then
  sandbox_path = vim.fn.tempname()
  vim.api.nvim_create_autocmd('VimLeavePre', {
    once = true,
    callback = function()
      vim.fn.delete(sandbox_path, 'rf')
    end,
  })
else
  assert(
    sandbox_name ~= '.' and sandbox_name ~= '..' and sandbox_name:match('^[%w._-]+$'),
    'sandbox names may only contain letters, numbers, dots, underscores, and hyphens'
  )
  sandbox_path = root .. '/.artifacts/sandboxes/' .. sandbox_name
end

local git_repo = require('helpers.git_repo')
local playground = require('sandbox.playground')
local sandbox_existed = vim.fn.isdirectory(sandbox_path) == 1
local repo
if sandbox_existed then
  repo = git_repo.get_repo(sandbox_path)
else
  repo = git_repo.create_repo(sandbox_path)
  playground.prepare_sandbox(repo)
end

vim.api.nvim_set_current_dir(sandbox_path)
vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    playground.work_in_sandbox(repo)
  end,
})
