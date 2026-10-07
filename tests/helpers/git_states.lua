local M = {}

---@param repo TestGitRepo
---@param path string
---@param stage 'untracked'|'staged'|'committed'
---@return string
function M.add_file(repo, path, stage)
  assert(stage == 'untracked' or stage == 'staged' or stage == 'committed', 'unsupported addition stage')
  assert(path ~= 'fixture-seed.txt', 'selected path must differ from seed')
  repo:write_file('fixture-seed.txt', { 'seed' })
  repo:add('fixture-seed.txt')
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  repo:write_file(path, { 'current ' .. path })
  if stage ~= 'untracked' then
    repo:add(path)
  end
  if stage == 'committed' then
    repo:commit('add ' .. path)
  end
  return base
end

---@param repo TestGitRepo
---@param path string
---@param stage 'unstaged'|'staged'|'committed'
---@return string
function M.modify_file(repo, path, stage)
  assert(stage == 'unstaged' or stage == 'staged' or stage == 'committed', 'unsupported modification stage')
  repo:write_file(path, { 'old ' .. path })
  repo:add(path)
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  if stage == 'staged' then
    repo:write_file(path, { 'staged ' .. path })
    repo:add(path)
  end
  repo:write_file(path, { 'current ' .. path })
  if stage == 'committed' then
    repo:add(path)
    repo:commit('modify ' .. path)
  end
  return base
end

---@param repo TestGitRepo
---@param path string
---@param stage 'unstaged'|'staged'|'committed'
---@return string
function M.delete_file(repo, path, stage)
  assert(stage == 'unstaged' or stage == 'staged' or stage == 'committed', 'unsupported deletion stage')
  repo:write_file(path, { 'old ' .. path })
  repo:add(path)
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  assert(vim.fn.delete(repo.cwd .. '/' .. path) == 0, 'failed to delete fixture')
  if stage ~= 'unstaged' then
    repo:run_git({ 'add', '-u', '--', path })
  end
  if stage == 'committed' then
    repo:commit('delete ' .. path)
  end
  return base
end

---@param repo TestGitRepo
---@param source string
---@param destination string
---@param stage 'staged'|'committed'
---@param operation 'rename'|'copy'
---@return string
local function relocate_file(repo, source, destination, stage, operation)
  assert(stage == 'staged' or stage == 'committed', 'unsupported relocation stage')
  assert(source ~= destination, 'source and destination must differ')
  local lines = { 'old ' .. source }
  for index = 1, 12 do
    table.insert(lines, 'shared line ' .. index)
  end
  repo:write_file(source, lines)
  repo:add(source)
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  if operation == 'rename' then
    repo:run_git({ 'mv', '--', source, destination })
  else
    repo:write_file(destination, lines)
    local updated = vim.deepcopy(lines)
    updated[1] = 'updated ' .. source
    repo:write_file(source, updated)
    repo:add(source)
  end
  local changed = vim.deepcopy(lines)
  changed[1] = 'current ' .. destination
  repo:write_file(destination, changed)
  repo:add(destination)
  if stage == 'committed' then
    repo:commit(operation .. ' ' .. source)
  end
  return base
end

---@param repo TestGitRepo
---@param source string
---@param destination string
---@param stage 'staged'|'committed'
---@return string
function M.rename_file(repo, source, destination, stage)
  return relocate_file(repo, source, destination, stage, 'rename')
end

---@param repo TestGitRepo
---@param source string
---@param destination string
---@param stage 'staged'|'committed'
---@return string
function M.copy_file(repo, source, destination, stage)
  return relocate_file(repo, source, destination, stage, 'copy')
end

---@param repo TestGitRepo
---@param path string
---@return string
function M.conflict_file(repo, path)
  repo:write_file(path, { 'base ' .. path })
  repo:add(path)
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  local default_branch = repo:run_git({ 'symbolic-ref', '--short', 'HEAD' })
  repo:branch('side')
  repo:write_file(path, { 'ours ' .. path })
  repo:add(path)
  repo:commit('ours')
  repo:run_git({ 'checkout', '--quiet', 'side' })
  repo:write_file(path, { 'theirs ' .. path })
  repo:add(path)
  repo:commit('theirs')
  repo:run_git({ 'checkout', '--quiet', default_branch })
  local merge = vim
    .system({
      'git',
      '-c',
      'user.name=Diff Review Tests',
      '-c',
      'user.email=diffreview@example.com',
      'merge',
      'side',
    }, { cwd = repo.cwd, text = true })
    :wait()
  assert(merge.code == 1, 'expected conflicting merge:\n' .. merge.stderr)
  return base
end

---@param repo TestGitRepo
---@param path string
---@param bytes string
---@return nil
local function write_raw_bytes(repo, path, bytes)
  local descriptor = assert(vim.uv.fs_open(repo.cwd .. '/' .. path, 'w', 438))
  local written, write_error = vim.uv.fs_write(descriptor, bytes)
  assert(written == #bytes, write_error or 'failed to write fixture bytes')
  vim.uv.fs_close(descriptor)
end

---@param repo TestGitRepo
---@param path string
---@param target string
---@return nil
local function make_symlink(repo, path, target)
  assert(vim.uv.fs_symlink(target, repo.cwd .. '/' .. path), 'failed to create fixture symlink')
end

---@param repo TestGitRepo
---@param path string
---@param stage 'unstaged'|'committed'
---@return string
function M.type_change_file(repo, path, stage)
  assert(stage == 'unstaged' or stage == 'committed', 'unsupported type-change stage')
  repo:write_file(path, { 'old ' .. path })
  repo:add(path)
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  assert(vim.fn.delete(repo.cwd .. '/' .. path) == 0, 'failed to remove fixture file')
  make_symlink(repo, path, 'dangling-current-' .. path)
  if stage == 'committed' then
    repo:add(path)
    repo:commit('type change ' .. path)
  end
  return base
end

---@param repo TestGitRepo
---@param path string
---@param stage 'staged'|'committed'
---@return string
function M.mode_change_file(repo, path, stage)
  assert(stage == 'staged' or stage == 'committed', 'unsupported mode-change stage')
  repo:write_file(path, { 'old ' .. path })
  repo:add(path)
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  assert(vim.uv.fs_chmod(repo.cwd .. '/' .. path, 493), 'failed to make fixture executable')
  repo:add(path)
  if stage == 'committed' then
    repo:commit('change mode ' .. path)
  end
  return base
end

---@param repo TestGitRepo
---@param path string
---@param stage 'unstaged'|'committed'
---@return string
function M.modify_binary_file(repo, path, stage)
  assert(stage == 'unstaged' or stage == 'committed', 'unsupported binary modification stage')
  write_raw_bytes(repo, path, '\0old binary ' .. path .. '\0\1')
  repo:add(path)
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  write_raw_bytes(repo, path, '\0current binary ' .. path .. ' content\0\2\3')
  if stage == 'committed' then
    repo:add(path)
    repo:commit('modify binary ' .. path)
  end
  return base
end

---@param repo TestGitRepo
---@param path string
---@return string
function M.add_symlink(repo, path)
  assert(path ~= 'fixture-seed.txt', 'selected path must differ from seed')
  repo:write_file('fixture-seed.txt', { 'seed' })
  repo:add('fixture-seed.txt')
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  make_symlink(repo, path, 'dangling-new-' .. path)
  return base
end

---@param repo TestGitRepo
---@param path string
---@return string
function M.modify_symlink(repo, path)
  make_symlink(repo, path, 'dangling-old-' .. path)
  repo:add(path)
  repo:commit('base')
  repo:set_default_branch()
  local base = repo:current_sha()
  assert(vim.fn.delete(repo.cwd .. '/' .. path) == 0, 'failed to remove fixture symlink')
  make_symlink(repo, path, 'dangling-current-' .. path)
  repo:add(path)
  repo:commit('retarget ' .. path)
  return base
end

return M
