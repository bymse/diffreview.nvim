local file_mode = require('diffreview.file_mode')
local file_utils = require('diffreview.file_utils')
local async_operation = require('diffreview.async_operation')
local git = require('diffreview.diffs.git')
local status = require('diffreview.diffs.status')

---@class DiffLoadOptions
---@field cwd string
---@field from string|nil
---@field to string|nil

---@class DiffLoadError
---@field kind 'repository'|'missing_default_branch'|'revision'|'git'|'filesystem'|'canceled'
---@field message string
---@field detail string|nil

---@alias DiffLoadErrorKind 'repository'|'missing_default_branch'|'revision'|'git'|'filesystem'|'canceled'

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

---@class ResolvedRevision
---@field oid string
---@field is_branch boolean

---@class ResolvedComparison
---@field from_oid string
---@field to_oid string|nil
---@field target_is_worktree boolean

---@param repo GitRepo
---@param expression string
---@return ResolvedRevision|nil, string|nil
local function resolve_revision(repo, expression)
  if expression:match('^refs/heads/') or expression:match('^refs/remotes/') then
    local result, oid = repo:rev_parse(expression)
    if not result.ok or oid == nil then
      return nil, result.error
    end
    return { oid = oid, is_branch = true }, nil
  elseif expression:match('^refs/') then
    return nil, 'Only local and remote branch refs are supported'
  elseif expression ~= 'HEAD' then
    for _, prefix in ipairs({ 'refs/heads/', 'refs/remotes/' }) do
      local result, oid = repo:rev_parse(prefix .. expression)
      if result.ok and oid ~= nil then
        return { oid = oid, is_branch = true }, nil
      end
    end
  end
  if expression ~= 'HEAD' and not expression:match('^%x+$') then
    return nil, 'Expected a branch, commit hash, or HEAD'
  end
  local result, oid = repo:rev_parse(expression)
  if not result.ok or oid == nil then
    return nil, result.error
  end
  return { oid = oid, is_branch = false }, nil
end

---@param repo GitRepo
---@param meta GitRepoMeta
---@param options DiffLoadOptions
---@return ResolvedComparison|nil, DiffLoadResult|nil
local function resolve_comparison(repo, meta, options)
  if options.from == nil then
    if meta.default_branch_ref == nil then
      return nil, (failure('missing_default_branch', nil))
    end
    local default_resolved, default_oid = repo:rev_parse(meta.default_branch_ref)
    if not default_resolved.ok or default_oid == nil then
      return nil, (failure('missing_default_branch', default_resolved.error))
    end
    local head_result, head_oid = repo:rev_parse('HEAD')
    if not head_result.ok or head_oid == nil then
      return nil, (failure('revision', head_result.error))
    end
    local merge_result, merge_oid = repo:merge_base(default_oid, head_oid)
    if not merge_result.ok or merge_oid == nil then
      return nil, (failure('revision', merge_result.error))
    end
    return { from_oid = merge_oid, to_oid = nil, target_is_worktree = true }, nil
  end

  local from, from_error = resolve_revision(repo, options.from)
  if from == nil then
    return nil, (failure('revision', from_error))
  end
  if options.to ~= nil then
    local to, to_error = resolve_revision(repo, options.to)
    if to == nil then
      return nil, (failure('revision', to_error))
    end
    return { from_oid = from.oid, to_oid = to.oid, target_is_worktree = false }, nil
  end
  if from.is_branch then
    local head_result, head_oid = repo:rev_parse('HEAD')
    if not head_result.ok or head_oid == nil then
      return nil, (failure('revision', head_result.error))
    end
    local merge_result, merge_oid = repo:merge_base(from.oid, head_oid)
    if not merge_result.ok or merge_oid == nil then
      return nil, (failure('revision', merge_result.error))
    end
    return { from_oid = merge_oid, to_oid = nil, target_is_worktree = true }, nil
  end
  return { from_oid = from.oid, to_oid = nil, target_is_worktree = true }, nil
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
function M.load_diffs(options, operation)
  if async_operation.is_canceled(operation) then
    return failure('canceled', nil)
  end
  local root_path, access_error = file_utils.ensure_accessible_directory(options.cwd)
  if root_path == nil then
    return failure('filesystem', access_error)
  end
  local repo = git.get_repo(root_path)
  local meta_result, meta = repo:repo_meta()
  if not meta_result.ok or meta == nil or meta.root == nil then
    return failure('repository', meta_result.error)
  end

  local comparison, comparison_failure = resolve_comparison(repo, meta, options)
  if comparison == nil then
    return assert(comparison_failure), nil
  end

  if async_operation.is_canceled(operation) then
    return failure('canceled', nil)
  end
  local diff_result, diffs = repo:diff(comparison.from_oid, comparison.to_oid)
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
  if comparison.target_is_worktree then
    if async_operation.is_canceled(operation) then
      return failure('canceled', nil)
    end
    local paths_result, paths = repo:ls_files()
    if not paths_result.ok or paths == nil then
      return failure('git', paths_result.error)
    end
    for _, path in ipairs(paths) do
      local inspect_result, added, removed, binary = repo:untracked_file_stats(path)
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
