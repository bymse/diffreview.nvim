local M = {}

---@class TestGitRepo
---@field cwd string
local TestGitRepo = {}
TestGitRepo.__index = TestGitRepo

---@param args string[]
---@param env table<string, string>|nil
---@return string
function TestGitRepo:run_git(args, env)
  local command = { 'git' }
  vim.list_extend(command, args)

  local result = vim.system(command, { cwd = self.cwd, text = true, env = env }):wait()
  assert(result.code == 0, 'git command failed: ' .. result.stderr)
  return vim.trim(result.stdout)
end

---@param path string
---@param lines string[]
---@return nil
function TestGitRepo:write_file(path, lines)
  assert(vim.fn.writefile(lines, self.cwd .. '/' .. path) == 0, 'failed to write repository file')
end

---@param path string
---@return nil
function TestGitRepo:add(path)
  self:run_git({ 'add', '--', path })
end

---@param message string
---@return nil
function TestGitRepo:commit(message)
  self:run_git({
    '-c',
    'user.name=Diff Review Tests',
    '-c',
    'user.email=diffreview@example.com',
    'commit',
    '--quiet',
    '--no-gpg-sign',
    '-m',
    message,
  }, {
    GIT_AUTHOR_DATE = '2026-08-30T00:00:00Z',
    GIT_COMMITTER_DATE = '2026-08-30T00:00:00Z',
  })
end

---@return string
function TestGitRepo:current_sha()
  return self:run_git({ 'rev-parse', 'HEAD' })
end

---@param name string
---@return nil
function TestGitRepo:branch(name)
  self:run_git({ 'branch', name })
end

---@param cwd string
---@return TestGitRepo
function M.get_repo(cwd)
  return setmetatable({ cwd = cwd }, TestGitRepo)
end

---@param cwd string
---@return TestGitRepo
function M.create_repo(cwd)
  local directory_exists = vim.fn.isdirectory(cwd) == 1
  if not directory_exists then
    assert(vim.fn.mkdir(cwd, 'p') == 1, 'failed to create Git repository directory')
  end

  local init_result = vim
    .system({ 'git', 'init', '--quiet', '--object-format=sha1' }, {
      cwd = cwd,
      text = true,
    })
    :wait()

  if init_result.code ~= 0 then
    if not directory_exists then
      vim.fn.delete(cwd, 'rf')
    end
    error('failed to initialize Git repository: ' .. init_result.stderr)
  end

  return M.get_repo(cwd)
end

---@param run fun(repo: TestGitRepo)
---@return nil
function M.with_repo(run)
  local cwd = vim.fn.tempname()
  local repo = M.create_repo(cwd)
  local success, test_error = xpcall(function()
    run(repo)
  end, debug.traceback)

  vim.fn.delete(cwd, 'rf')
  assert(success, test_error)
end

return M
