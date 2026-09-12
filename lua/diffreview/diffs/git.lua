local async = require('diffreview.async')
local parsers = require('diffreview.diffs.parsers')

---@class GitResult
---@field ok boolean
---@field error string|nil

---@class GitRemote
---@field name string
---@field url string

---@class GitRepoMeta
---@field root string|nil
---@field remotes GitRemote[]
---@field branch string|nil
---@field upstream_branch string|nil
---@field default_branch string|nil

local M = {}

---@class GitRepo
---@field private dir string|nil
local GitRepo = {}
GitRepo.__index = GitRepo

---@param cmd string[]
---@param cwd string|nil
---@param parse_output fun(raw_out: string): any
---@param text boolean
---@return GitResult, any|nil
local function run_parsed(cmd, cwd, parse_output, text)
  local started, result = pcall(async.system, cmd, { cwd = cwd, text = text })
  if not started then
    return { ok = false, error = tostring(result) }
  end

  if result.code ~= 0 then
    return { ok = false, error = result.stderr }
  end

  local success, output = pcall(parse_output, result.stdout)

  if success then
    return { ok = true }, output
  else
    return { ok = false, error = tostring(output) }
  end
end

---@param cmd string[]
---@param cwd string|nil
---@return string|nil
local function run_optional_trimmed(cmd, cwd)
  local result, output = run_parsed(cmd, cwd, vim.trim, true)
  if not result.ok then
    return nil
  end

  return output
end

---@param expression string
---@return GitResult, string|nil
function GitRepo:rev_parse(expression)
  local cmd = {
    'git',
    'rev-parse',
    '--verify',
    '--end-of-options',
    expression .. '^{commit}',
  }

  return run_parsed(cmd, self.dir, vim.trim, true)
end

---@param from_commit_oid string|nil
---@param to_commit_oid string|nil
---@return GitResult, GitDiff[]|nil
function GitRepo:diff(from_commit_oid, to_commit_oid)
  if from_commit_oid ~= nil and not from_commit_oid:match('^%x+$') then
    error('invalid from commit object ID: ' .. from_commit_oid)
  end
  if to_commit_oid ~= nil and not to_commit_oid:match('^%x+$') then
    error('invalid to commit object ID: ' .. to_commit_oid)
  end

  local cmd = { 'git', 'diff', '--raw', '--numstat', '-z', '-M', '-C' }
  if from_commit_oid ~= nil then
    table.insert(cmd, from_commit_oid)
  end
  if to_commit_oid ~= nil then
    table.insert(cmd, to_commit_oid)
  end
  table.insert(cmd, '--')

  return run_parsed(cmd, self.dir, parsers.parse_diff_output, false)
end

---@return GitResult, string[]|nil
function GitRepo:ls_files()
  local cmd = { 'git', 'ls-files', '--others', '--exclude-standard', '-z' }
  return run_parsed(cmd, self.dir, parsers.parse_ls_files_output, false)
end

---@return GitResult, GitRepoMeta|nil
function GitRepo:repo_meta()
  local root_result, root = run_parsed({ 'git', 'rev-parse', '--show-toplevel' }, self.dir, vim.trim, true)
  if not root_result.ok then
    return root_result, nil
  end

  local remotes_result, remotes = run_parsed({ 'git', 'remote', '-v' }, self.dir, parsers.parse_remote_output, true)
  if not remotes_result.ok then
    return remotes_result, nil
  end

  ---@type GitRepoMeta
  local meta = {
    root = root,
    remotes = remotes,
    branch = run_optional_trimmed({ 'git', 'symbolic-ref', '--quiet', '--short', 'HEAD' }, self.dir),
    upstream_branch = run_optional_trimmed(
      { 'git', 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}' },
      self.dir
    ),
    default_branch = run_optional_trimmed(
      { 'git', 'symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD' },
      self.dir
    ),
  }

  return { ok = true }, meta
end

---@param dir string|nil
---@return GitRepo
function M.get_repo(dir)
  return setmetatable({ dir = dir }, GitRepo)
end

return M
