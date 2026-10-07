local selection = require('helpers.functional_review')
local states = require('helpers.git_states')

local M = {}

for _, stage in ipairs({ 'unstaged', 'staged', 'committed' }) do
  M['should_show_old_only_' .. stage .. '_file_when_enter_selects_deleted_row'] = function()
    selection.ensure_setup()
    local path = stage .. '-deleted.txt'
    selection.with_review(function(repo)
      local base = states.delete_file(repo, path, stage)
      local raw = repo:run_git({ 'diff', '--raw', '-M', '-C', base, '--' })
      assert(raw:find('D\t' .. path, 1, true), raw)
      assert(repo:run_git({ 'show', base .. ':' .. path }) == 'old ' .. path)
      assert(repo:run_git({ 'ls-files', '--', path }) == (stage == 'unstaged' and path or ''))
      assert(repo:run_git({ 'ls-tree', '--name-only', 'HEAD', '--', path }) == (stage == 'committed' and '' or path))
      assert((base ~= repo:current_sha()) == (stage == 'committed'))
      return { from = base }
    end, function()
      selection.select_path(selection.wait_for_list(1), path)
      selection.wait_for_one_sided_old('old ' .. path)
    end)
  end
end

return M
