local selection = require('helpers.functional_review')
local states = require('helpers.git_states')

local M = {}

for _, stage in ipairs({ 'unstaged', 'committed' }) do
  M['should_show_information_when_enter_selects_' .. stage .. '_type_changed_row'] = function()
    selection.ensure_setup()
    local path = stage .. '-type-change.txt'
    local target = 'dangling-current-' .. path
    selection.with_review(function(repo)
      local base = states.type_change_file(repo, path, stage)
      local raw = repo:run_git({ 'diff', '--raw', '-M', '-C', base, '--' })
      assert(raw:find(':100644 120000 ', 1, true), raw)
      assert(raw:find('T\t' .. path, 1, true), raw)
      local mode = stage == 'unstaged' and '100644' or '120000'
      assert(repo:run_git({ 'ls-files', '--stage', '--', path }):match('^' .. mode .. ' ') ~= nil)
      assert(repo:run_git({ 'ls-tree', 'HEAD', '--', path }):match('^' .. mode .. ' blob ') ~= nil)
      assert(repo:run_git({ 'ls-tree', base, '--', path }):match('^100644 blob ') ~= nil)
      assert((base ~= repo:current_sha()) == (stage == 'committed'))
      assert(repo:run_git({ 'show', base .. ':' .. path }) == 'old ' .. path)
      assert(vim.uv.fs_readlink(repo.cwd .. '/' .. path) == target)
      return { from = base }
    end, function()
      selection.select_path(selection.wait_for_list(1), path)
      selection.wait_for_information({
        'Path: ' .. path,
        'Old type: regular',
        'Current type: symlink',
      })
    end)
  end
end

for _, stage in ipairs({ 'staged', 'committed' }) do
  M['should_show_information_when_enter_selects_' .. stage .. '_mode_changed_row'] = function()
    selection.ensure_setup()
    local path = stage .. '-mode-change.txt'
    selection.with_review(function(repo)
      local base = states.mode_change_file(repo, path, stage)
      local raw = repo:run_git({ 'diff', '--raw', '-M', '-C', base, '--' })
      assert(raw:find(':100644 100755 ', 1, true), raw)
      assert(raw:find('M\t' .. path, 1, true), raw)
      assert(repo:run_git({ 'diff', '--numstat', base, '--', path }) == '0\t0\t' .. path)
      assert(repo:run_git({ 'ls-files', '--stage', '--', path }):match('^100755 ') ~= nil)
      local mode = stage == 'staged' and '100644' or '100755'
      assert(repo:run_git({ 'ls-tree', 'HEAD', '--', path }):match('^' .. mode .. ' blob ') ~= nil)
      assert(repo:run_git({ 'ls-tree', base, '--', path }):match('^100644 blob ') ~= nil)
      assert((base ~= repo:current_sha()) == (stage == 'committed'))
      assert(repo:run_git({ 'show', base .. ':' .. path }) == 'old ' .. path)
      return { from = base }
    end, function()
      selection.select_path(selection.wait_for_list(1), path)
      selection.wait_for_information({
        'Path: ' .. path,
        'Old mode: file (100644)',
        'Current mode: executable file (100755)',
      })
    end)
  end
end

for _, stage in ipairs({ 'unstaged', 'committed' }) do
  M['should_show_information_when_enter_selects_' .. stage .. '_binary_row'] = function()
    selection.ensure_setup()
    local path = stage .. '-binary.dat'
    local sizes = {}
    selection.with_review(function(repo)
      local base = states.modify_binary_file(repo, path, stage)
      assert(repo:run_git({ 'diff', '--numstat', base, '--', path }) == '-\t-\t' .. path)
      local base_blob = repo:run_git({ 'rev-parse', base .. ':' .. path })
      local head_blob = repo:run_git({ 'rev-parse', 'HEAD:' .. path })
      assert((head_blob ~= base_blob) == (stage == 'committed'))
      assert(
        repo
          :run_git({ 'ls-files', '--stage', '--', path })
          :match('^100644 ' .. (stage == 'unstaged' and base_blob or head_blob)) ~= nil
      )
      local old_size = tonumber(repo:run_git({ 'cat-file', '-s', base .. ':' .. path }))
      local stat = assert(vim.uv.fs_stat(repo.cwd .. '/' .. path))
      assert(old_size ~= stat.size, 'expected distinct binary lengths')
      sizes.old = old_size
      sizes.current = stat.size
      return { from = base }
    end, function()
      selection.select_path(selection.wait_for_list(1), path)
      selection.wait_for_information({
        'Path: ' .. path,
        'Old size: ' .. sizes.old .. ' bytes',
        'Current size: ' .. sizes.current .. ' bytes',
      })
    end)
  end
end

M.should_show_one_sided_snapshot_when_enter_selects_untracked_symlink_row = function()
  selection.ensure_setup()
  local path = 'untracked-link.txt'
  local target = 'dangling-new-' .. path
  selection.with_review(function(repo)
    local base = states.add_symlink(repo, path)
    assert(repo:run_git({ 'ls-files', '--', path }) == '', 'expected symlink absent from index')
    assert(vim.uv.fs_readlink(repo.cwd .. '/' .. path) == target)
    return { from = base }
  end, function(repo)
    selection.select_path(selection.wait_for_list(1), path)
    selection.wait_for_one_sided_snapshot(repo, path, target)
  end)
end

M.should_show_two_sided_snapshot_when_enter_selects_committed_symlink_row = function()
  selection.ensure_setup()
  local path = 'committed-link.txt'
  local old_target = 'dangling-old-' .. path
  local current_target = 'dangling-current-' .. path
  selection.with_review(function(repo)
    local base = states.modify_symlink(repo, path)
    local raw = repo:run_git({ 'diff', '--raw', '-M', '-C', base, '--' })
    assert(raw:find(':120000 120000 ', 1, true), raw)
    assert(raw:find('M\t' .. path, 1, true), raw)
    assert(repo:run_git({ 'show', base .. ':' .. path }) == old_target)
    assert(repo:run_git({ 'show', 'HEAD:' .. path }) == current_target)
    assert(repo:run_git({ 'ls-files', '--stage', '--', path }):match('^120000 ') ~= nil)
    assert(vim.uv.fs_readlink(repo.cwd .. '/' .. path) == current_target)
    assert(base ~= repo:current_sha(), 'expected earlier comparison base')
    return { from = base }
  end, function(repo)
    selection.select_path(selection.wait_for_list(1), path)
    selection.wait_for_two_sided_snapshot(repo, path, old_target, current_target)
  end)
end

return M
