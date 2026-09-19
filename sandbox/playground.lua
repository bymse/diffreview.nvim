local M = {}

---@param repo TestGitRepo
---@return nil
function M.prepare_sandbox(repo)
  repo:run_git({ 'symbolic-ref', 'HEAD', 'refs/heads/main' })
  repo:write_file('justfile', {
    'default:',
    '    @echo "before review"',
  })
  repo:add('justfile')
  repo:commit('Initial commit')
  repo:write_file('justfile', {
    'default:',
    '    @echo "sandbox ready"',
  })
end

---@param repo TestGitRepo
---@return nil
function M.work_in_sandbox(repo) end

return M
