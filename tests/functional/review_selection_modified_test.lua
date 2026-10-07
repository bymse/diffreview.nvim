local selection = require('helpers.functional_review')
local states = require('helpers.git_states')

local M = {}

M.should_show_two_sided_unstaged_file_when_enter_selects_modified_row = function()
  selection.ensure_setup()
  local path = 'unstaged.txt'
  selection.with_review(function(repo)
    local base = states.modify_file(repo, path, 'unstaged')
    assert(repo:run_git({ 'show', 'HEAD:' .. path }) == 'old ' .. path)
    assert(repo:run_git({ 'show', ':' .. path }) == 'old ' .. path)
    return { from = base }
  end, function(repo)
    selection.select_path(selection.wait_for_list(1), path)
    selection.wait_for_two_sided_current(repo, path, 'old ' .. path, 'current ' .. path)
  end)
end

M.should_show_two_sided_staged_file_when_enter_selects_modified_row = function()
  selection.ensure_setup()
  local path = 'staged.txt'
  selection.with_review(function(repo)
    local base = states.modify_file(repo, path, 'staged')
    assert(repo:run_git({ 'show', 'HEAD:' .. path }) == 'old ' .. path)
    assert(repo:run_git({ 'show', ':' .. path }) == 'staged ' .. path)
    return { from = base }
  end, function(repo)
    selection.select_path(selection.wait_for_list(1), path)
    selection.wait_for_two_sided_current(repo, path, 'old ' .. path, 'current ' .. path)
  end)
end

M.should_show_two_sided_committed_file_when_enter_selects_modified_row = function()
  selection.ensure_setup()
  local path = 'committed.txt'
  selection.with_review(function(repo)
    local base = states.modify_file(repo, path, 'committed')
    assert(repo:run_git({ 'show', 'HEAD:' .. path }) == 'current ' .. path)
    assert(repo:run_git({ 'show', base .. ':' .. path }) == 'old ' .. path)
    return { from = base }
  end, function(repo)
    selection.select_path(selection.wait_for_list(1), path)
    selection.wait_for_two_sided_current(repo, path, 'old ' .. path, 'current ' .. path)
  end)
end

return M
