local selection = require('helpers.functional_review')
local states = require('helpers.git_states')

local M = {}

M.should_show_two_sided_conflict_when_enter_selects_unmerged_row = function()
  selection.ensure_setup()
  local path = 'conflicted.txt'
  selection.with_review(function(repo)
    local base = states.conflict_file(repo, path)
    local unmerged = repo:run_git({ 'ls-files', '--unmerged', '--', path })
    assert(#vim.split(unmerged, '\n') == 3, unmerged)
    assert(
      unmerged:find(' 1\t' .. path, 1, true)
        and unmerged:find(' 2\t' .. path, 1, true)
        and unmerged:find(' 3\t' .. path, 1, true),
      unmerged
    )
    local raw = repo:run_git({ 'diff', '--raw', '-M', '-C', base, '--' })
    assert(raw:match('^:100644 100644 %x+ 0+ M\t' .. path .. '$') ~= nil, raw)
    assert(repo:run_git({ 'show', base .. ':' .. path }) == 'base ' .. path)
    return { from = base }
  end, function(repo)
    selection.select_path(selection.wait_for_list(1), path)
    selection.wait_for_two_sided_current(repo, path, 'base ' .. path, {
      '<<<<<<< HEAD',
      'ours ' .. path,
      '=======',
      'theirs ' .. path,
      '>>>>>>> side',
    })
  end)
end

return M
