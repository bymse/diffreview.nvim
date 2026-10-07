local selection = require('helpers.functional_review')
local states = require('helpers.git_states')

local M = {}

M.should_show_one_sided_untracked_file_when_enter_selects_nonfirst_row = function()
  selection.ensure_setup()
  selection.with_review(function(repo)
    local base = states.add_file(repo, 'z-target.txt', 'untracked')
    assert(repo:run_git({ 'ls-files', '--', 'z-target.txt' }) == '', 'expected path absent from index')
    repo:write_file('a-other.txt', { 'other' })
    return { from = base }
  end, function(repo)
    local row = selection.select_path(selection.wait_for_list(2), 'z-target.txt')
    assert(row ~= 1, 'expected selected path on a nonfirst row')
    selection.wait_for_one_sided_current(repo, 'z-target.txt', 'current z-target.txt')
  end)
end

M.should_show_one_sided_staged_file_when_enter_selects_added_row = function()
  selection.ensure_setup()
  selection.with_review(function(repo)
    local base = states.add_file(repo, 'staged.txt', 'staged')
    assert(repo:run_git({ 'ls-files', '--', 'staged.txt' }) == 'staged.txt', 'expected path in index')
    assert(
      repo:run_git({ 'ls-tree', '--name-only', 'HEAD', '--', 'staged.txt' }) == '',
      'expected path absent from HEAD'
    )
    return { from = base }
  end, function(repo)
    selection.select_path(selection.wait_for_list(1), 'staged.txt')
    selection.wait_for_one_sided_current(repo, 'staged.txt', 'current staged.txt')
  end)
end

M.should_show_one_sided_committed_file_when_enter_selects_added_row = function()
  selection.ensure_setup()
  selection.with_review(function(repo)
    local base = states.add_file(repo, 'committed.txt', 'committed')
    assert(
      repo:run_git({ 'ls-tree', '--name-only', 'HEAD', '--', 'committed.txt' }) == 'committed.txt',
      'expected path in HEAD'
    )
    assert(
      repo:run_git({ 'ls-tree', '--name-only', base, '--', 'committed.txt' }) == '',
      'expected base before addition'
    )
    assert(base ~= repo:current_sha(), 'expected earlier comparison base')
    return { from = base }
  end, function(repo)
    selection.select_path(selection.wait_for_list(1), 'committed.txt')
    selection.wait_for_one_sided_current(repo, 'committed.txt', 'current committed.txt')
  end)
end

return M
