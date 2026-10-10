local async = require('diffreview.async')
local parsers = require('diffreview.diffs.parsers')

---@class GitResult
---@field ok boolean
---@field error string|nil
---@field code integer|nil

---@class GitRemote
---@field name string
---@field url string

---@class GitRepoMeta
---@field root string|nil
---@field remotes GitRemote[]
---@field branch string|nil
---@field source_branch_ref string|nil
---@field upstream_branch string|nil
---@field default_branch_ref string|nil
---@field storage_path string|nil

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
    return { ok = false, error = result.stderr, code = result.code }
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
---@return GitResult
---@return string|nil
local function run_optional_trimmed(cmd, cwd)
  local result, output = run_parsed(cmd, cwd, vim.trim, true)
  if not result.ok then
    return result, nil
  end

  return result, output
end

---@param raw_out string
---@return integer, integer, boolean
local function parse_untracked_file_stats(raw_out)
  if raw_out:sub(-1) ~= '\0' then
    error('git untracked-file numstat output expected to end with NUL')
  end
  local added, removed = raw_out:match('^([^\t]+)\t([^\t]+)\t')
  if added == '-' and removed == '-' then
    return 0, 0, true
  end
  if added == nil or removed == nil or not added:match('^%d+$') or removed ~= '0' then
    error('invalid git untracked-file numstat output')
  end
  return assert(tonumber(added)), 0, false
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

---@param ref string
---@return GitResult, string|nil
function GitRepo:symbolic_ref(ref)
  return run_parsed({ 'git', 'symbolic-ref', '--quiet', '--', ref }, self.dir, vim.trim, true)
end

---@param first_oid string
---@param second_oid string
---@return GitResult, string|nil
function GitRepo:merge_base(first_oid, second_oid)
  if not first_oid:match('^%x+$') then
    error('invalid first commit object ID: ' .. first_oid)
  end
  if not second_oid:match('^%x+$') then
    error('invalid second commit object ID: ' .. second_oid)
  end

  return run_parsed({ 'git', 'merge-base', '--', first_oid, second_oid }, self.dir, vim.trim, true)
end

---@param path string
---@return GitResult, integer|nil, integer|nil, boolean|nil
function GitRepo:untracked_file_stats(path)
  local started, result = pcall(
    async.system,
    { 'git', 'diff', '--no-index', '--numstat', '-z', '--', '/dev/null', path },
    { cwd = self.dir, text = false }
  )
  if not started then
    return { ok = false, error = tostring(result) }, nil, nil, nil
  end
  if result.code ~= 1 then
    return { ok = false, error = result.stderr, code = result.code }, nil, nil, nil
  end
  local success, added, removed, binary = pcall(parse_untracked_file_stats, result.stdout)
  if not success then
    return { ok = false, error = tostring(added) }, nil, nil, nil
  end
  return { ok = true }, added, removed, binary
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

---@param oid string
---@return GitResult, string|nil
function GitRepo:load_blob(oid)
  if not oid:match('^%x+$') then
    error('invalid object ID: ' .. oid)
  end

  return run_parsed({ 'git', 'cat-file', 'blob', oid }, self.dir, function(raw_out)
    return raw_out
  end, false)
end

---@return GitResult, string[]|nil
function GitRepo:ls_files()
  local cmd = { 'git', 'ls-files', '--others', '--exclude-standard', '-z' }
  return run_parsed(cmd, self.dir, parsers.parse_ls_files_output, false)
end

---@param path string
---@return GitResult, string|nil
function GitRepo:unmerged_stages(path)
  return run_parsed({ 'git', 'ls-files', '--unmerged', '-z', '--', ':(literal)' .. path }, self.dir, function(raw)
    if raw == '' then
      return ''
    end
    if raw:sub(-1) ~= '\0' then
      error('invalid index stages')
    end
    local stages = {}
    for record in raw:gmatch('([^%z]+)%z') do
      local mode, oid, stage, name = record:match('^(%d+) (%x+) ([123])\t(.*)$')
      if mode == nil or name ~= path or stages[stage] then
        error('invalid index stages')
      end
      stages[stage] = mode .. ':' .. oid
    end
    return table.concat({ stages['1'] or '', stages['2'] or '', stages['3'] or '' }, '|')
  end, false)
end

---@return GitResult, GitRepoMeta|nil
function GitRepo:repo_meta()
  local root_result, root = run_parsed({ 'git', 'rev-parse', '--show-toplevel' }, self.dir, vim.trim, true)
  if not root_result.ok then
    return root_result, nil
  end

  local path_result, storage_path = run_parsed(
    { 'git', 'rev-parse', '--path-format=absolute', '--git-path', 'diffreview-nvim' },
    self.dir,
    vim.trim,
    true
  )
  if not path_result.ok or storage_path == nil or storage_path:sub(1, 1) ~= '/' then
    return { ok = false, error = path_result.error or 'Invalid Git storage path' }, nil
  end

  local remotes_result, remotes = run_parsed({ 'git', 'remote', '-v' }, self.dir, parsers.parse_remote_output, true)
  if not remotes_result.ok then
    return remotes_result, nil
  end

  local _, branch = run_optional_trimmed({ 'git', 'symbolic-ref', '--quiet', '--short', 'HEAD' }, self.dir)
  local _, source_branch_ref = self:symbolic_ref('HEAD')
  if source_branch_ref ~= nil and not source_branch_ref:match('^refs/heads/.+$') then
    source_branch_ref = nil
  end
  local _, upstream_branch =
    run_optional_trimmed({ 'git', 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}' }, self.dir)
  local _, default_branch_ref = self:symbolic_ref('refs/remotes/origin/HEAD')
  if default_branch_ref ~= nil and not default_branch_ref:match('^refs/remotes/origin/.+$') then
    default_branch_ref = nil
  end

  ---@type GitRepoMeta
  local meta = {
    root = root,
    storage_path = storage_path,
    remotes = remotes,
    branch = branch,
    source_branch_ref = source_branch_ref,
    upstream_branch = upstream_branch,
    default_branch_ref = default_branch_ref,
  }

  return { ok = true }, meta
end

---@param dir string|nil
---@return GitRepo
function M.get_repo(dir)
  return setmetatable({ dir = dir }, GitRepo)
end

return M
