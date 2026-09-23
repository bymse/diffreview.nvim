local file_mode = require('diffreview.file_mode')
local async = require('diffreview.async')
local git = require('diffreview.diffs.git')
local status = require('diffreview.diffs.status')

---@class DiffLoadOptions
---@field cwd string|nil
---@field from string|nil
---@field to string|nil

---@class DiffLoadError
---@field kind 'invalid_options'|'repository'|'missing_default_branch'|'revision'|'git'|'filesystem'|'canceled'
---@field message string
---@field detail string|nil

---@alias DiffLoadErrorKind 'invalid_options'|'repository'|'missing_default_branch'|'revision'|'git'|'filesystem'|'canceled'

---@class DiffLoadResult
---@field ok boolean
---@field error DiffLoadError|nil

---@class LoadedDiffEntry
---@field summary ChangedFileViewModel
---@field git_diff GitDiff|nil
---@field untracked_path string|nil
---@field binary boolean
---@field root string
---@field absolute_path string|nil

---@class LoadedDiffs
---@field files ChangedFileViewModel[]
---@field repo GitRepo
---@field entries_by_id table<string, LoadedDiffEntry>

local M = {}

local messages = {
  invalid_options = 'Invalid diff load options',
  repository = 'Not inside a Git worktree',
  missing_default_branch = 'Default branch is unavailable',
  revision = 'Unable to resolve revision',
  git = 'Git operation failed',
  filesystem = 'Unable to inspect repository files',
  canceled = 'Review loading canceled',
}

---@param kind DiffLoadErrorKind
---@param detail string|nil
---@return DiffLoadResult, nil
local function failure(kind, detail)
  if detail == '' then
    detail = nil
  end
  return { ok = false, error = { kind = kind, message = messages[kind], detail = detail } }, nil
end

---@param options any
---@return DiffLoadOptions|nil, DiffLoadResult|nil
local function validate_options(options)
  if type(options) ~= 'table' then
    return nil, failure('invalid_options', nil)
  end
  for key, value in pairs(options) do
    if (key ~= 'cwd' and key ~= 'from' and key ~= 'to') or type(value) ~= 'string' or value == '' then
      return nil, failure('invalid_options', nil)
    end
  end
  if options.to ~= nil and options.from == nil then
    return nil, failure('invalid_options', nil)
  end
  return options, nil
end

---@param path string
---@return boolean, string|nil
local function can_access_directory(path)
  local readable, read_error = vim.uv.fs_access(path, 'R')
  if not readable then
    return false, read_error or 'unable to read cwd'
  end
  local traversable, traverse_error = vim.uv.fs_access(path, 'X')
  if not traversable then
    return false, traverse_error or 'unable to traverse cwd'
  end
  return true, nil
end

---@param repo GitRepo
---@param expression string
---@param exact boolean
---@return string|nil, boolean|nil, string|nil
local function resolve_revision(repo, expression, exact)
  local candidates = {}
  if expression:match('^refs/heads/') or expression:match('^refs/remotes/') or expression:match('^refs/tags/') then
    local result, oid = repo:named_ref(expression)
    if not result.ok then
      return nil, nil, result.error
    end
    table.insert(
      candidates,
      { oid = oid, branch = expression:match('^refs/heads/') ~= nil or expression:match('^refs/remotes/') ~= nil }
    )
  elseif expression:match('^refs/') then
    return nil, nil, nil
  elseif not expression:match('^refs/') then
    for _, prefix in ipairs({ 'refs/heads/', 'refs/remotes/', 'refs/tags/' }) do
      local result, oid = repo:named_ref(prefix .. expression)
      if result.ok then
        table.insert(candidates, { oid = oid, branch = prefix ~= 'refs/tags/' })
      end
    end
  end
  if #candidates > 1 then
    return nil, nil, nil
  end
  if #candidates == 1 then
    return candidates[1].oid, exact and false or candidates[1].branch, nil
  end
  local result, oid = repo:rev_parse(expression)
  if not result.ok then
    return nil, nil, result.error
  end
  return oid, false, nil
end

---@param diff GitDiff
---@return ChangedFileViewModel, string
local function tracked_summary(diff)
  local has_baseline = file_mode.is_present_mode(diff.old_mode) or diff.old_oid ~= string.rep('0', #diff.old_oid)
  local old_path = diff.old_path or diff.current_path
  if diff.status == status.added or diff.status == status.copied then
    has_baseline = false
  end
  local display_path = diff.status == status.deleted and old_path or diff.current_path
  local id = has_baseline and 'stored:' .. old_path or 'new:' .. diff.current_path
  return {
    id = id,
    display_path = display_path,
    added_lines = diff.binary and 0 or assert(diff.added_lines),
    removed_lines = diff.binary and 0 or assert(diff.removed_lines),
    viewed = false,
  },
    id
end

---@param options DiffLoadOptions
---@param operation AsyncOperation|nil
---@return DiffLoadResult, LoadedDiffs|nil
function M.load_review(options, operation)
  if async.is_canceled(operation) then
    return failure('canceled', nil)
  end
  local valid_options, validation_failure = validate_options(options)
  if valid_options == nil then
    assert(validation_failure ~= nil)
    return validation_failure, nil
  end
  local cwd = valid_options.cwd or vim.fn.getcwd()
  local stat = vim.uv.fs_stat(cwd)
  if stat == nil or stat.type ~= 'directory' then
    return failure('filesystem', 'unable to access cwd: ' .. cwd)
  end
  local accessible, access_error = can_access_directory(cwd)
  if not accessible then
    return failure('filesystem', access_error)
  end
  local root_path = vim.uv.fs_realpath(cwd)
  if root_path == nil then
    return failure('filesystem', 'unable to access cwd: ' .. cwd)
  end
  local repo = git.get_repo(root_path, operation)
  local meta_result, meta = repo:repo_meta()
  if meta_result.canceled or async.is_canceled(operation) then
    return failure('canceled', nil)
  end
  if not meta_result.ok or meta == nil or meta.root == nil then
    return failure('repository', meta_result.error)
  end

  local from_oid
  local to_oid
  local working_state = valid_options.to == nil
  if valid_options.from == nil then
    local default_result, default_ref = repo:symbolic_ref('refs/remotes/origin/HEAD')
    if default_result.canceled or async.is_canceled(operation) then
      return failure('canceled', nil)
    end
    if not default_result.ok or default_ref == nil then
      return failure('missing_default_branch', default_result.error)
    end
    if not default_ref:match('^refs/remotes/origin/.+$') then
      return failure('missing_default_branch', 'origin/HEAD does not target an origin remote ref')
    end
    local default_oid, _, default_error = resolve_revision(repo, default_ref, false)
    if async.is_canceled(operation) then
      return failure('canceled', nil)
    end
    if default_oid == nil then
      return failure('missing_default_branch', default_error)
    end
    local head_result, head_oid = repo:rev_parse('HEAD')
    if head_result.canceled or async.is_canceled(operation) then
      return failure('canceled', nil)
    end
    if not head_result.ok or head_oid == nil then
      return failure('revision', head_result.error)
    end
    local merge_result, merge_oid = repo:merge_base(default_oid, head_oid)
    if merge_result.canceled or async.is_canceled(operation) then
      return failure('canceled', nil)
    end
    if not merge_result.ok or merge_oid == nil then
      return failure('revision', merge_result.error)
    end
    from_oid = merge_oid
  else
    local resolved_from, from_is_branch, from_error =
      resolve_revision(repo, valid_options.from, valid_options.to ~= nil)
    if async.is_canceled(operation) then
      return failure('canceled', nil)
    end
    if resolved_from == nil then
      return failure('revision', from_error)
    end
    if valid_options.to ~= nil then
      local resolved_to, _, to_error = resolve_revision(repo, valid_options.to, true)
      if async.is_canceled(operation) then
        return failure('canceled', nil)
      end
      if resolved_to == nil then
        return failure('revision', to_error)
      end
      from_oid = resolved_from
      to_oid = resolved_to
    elseif from_is_branch then
      local head_result, head_oid = repo:rev_parse('HEAD')
      if head_result.canceled or async.is_canceled(operation) then
        return failure('canceled', nil)
      end
      if not head_result.ok or head_oid == nil then
        return failure('revision', head_result.error)
      end
      local merge_result, merge_oid = repo:merge_base(resolved_from, head_oid)
      if merge_result.canceled or async.is_canceled(operation) then
        return failure('canceled', nil)
      end
      if not merge_result.ok or merge_oid == nil then
        return failure('revision', merge_result.error)
      end
      from_oid = merge_oid
    else
      from_oid = resolved_from
    end
  end

  local diff_result, diffs = repo:diff(from_oid, to_oid)
  if diff_result.canceled or async.is_canceled(operation) then
    return failure('canceled', nil)
  end
  if not diff_result.ok or diffs == nil then
    return failure('git', diff_result.error)
  end
  ---@type LoadedDiffs
  local loaded = { files = {}, repo = repo, entries_by_id = {} }
  for _, diff in ipairs(diffs) do
    local summary, id = tracked_summary(diff)
    table.insert(loaded.files, summary)
    loaded.entries_by_id[id] = {
      summary = summary,
      git_diff = diff,
      untracked_path = nil,
      binary = diff.binary,
      root = meta.root,
      absolute_path = diff.status == status.deleted and nil or meta.root .. '/' .. diff.current_path,
    }
  end
  if working_state then
    local paths_result, paths = repo:ls_files()
    if paths_result.canceled or async.is_canceled(operation) then
      return failure('canceled', nil)
    end
    if not paths_result.ok or paths == nil then
      return failure('git', paths_result.error)
    end
    for _, path in ipairs(paths) do
      local inspect_result, added, removed, binary = repo:empty_source_numstat(path)
      if inspect_result.canceled or async.is_canceled(operation) then
        return failure('canceled', nil)
      end
      if not inspect_result.ok or added == nil or removed == nil or binary == nil then
        return failure('filesystem', inspect_result.error)
      end
      local id = 'new:' .. path
      ---@type ChangedFileViewModel
      local summary = { id = id, display_path = path, added_lines = added, removed_lines = removed, viewed = false }
      table.insert(loaded.files, summary)
      loaded.entries_by_id[id] = {
        summary = summary,
        git_diff = nil,
        untracked_path = path,
        binary = binary,
        root = meta.root,
        absolute_path = meta.root .. '/' .. path,
      }
    end
  end
  return { ok = true, error = nil }, loaded
end

return M
