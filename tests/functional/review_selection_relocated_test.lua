local selection = require('helpers.functional_review')
local states = require('helpers.git_states')

local M = {}

for _, operation in ipairs({ 'rename', 'copy' }) do
  for _, stage in ipairs({ 'staged', 'committed' }) do
    M['should_show_two_sided_' .. stage .. '_file_when_enter_selects_' .. operation .. '_row'] = function()
      selection.ensure_setup()
      local source = operation .. '-source.txt'
      local destination = operation .. '-destination.txt'
      local old = { 'old ' .. source }
      local current = { 'current ' .. destination }
      for index = 1, 12 do
        table.insert(old, 'shared line ' .. index)
        table.insert(current, 'shared line ' .. index)
      end
      selection.with_review(function(repo)
        local base = states[operation .. '_file'](repo, source, destination, stage)
        local status = operation == 'rename' and 'R' or 'C'
        local raw = repo:run_git({ 'diff', '--raw', '-M', '-C', base, '--' })
        assert(raw:match(status .. '%d+') and raw:find('\t' .. source .. '\t' .. destination, 1, true), raw)
        assert(repo:run_git({ 'ls-files', '--', destination }) == destination)
        assert(
          repo:run_git({ 'ls-tree', '--name-only', 'HEAD', '--', destination })
            == (stage == 'staged' and '' or destination)
        )
        assert((base ~= repo:current_sha()) == (stage == 'committed'))
        assert(repo:run_git({ 'show', base .. ':' .. source }):find('old ' .. source .. '\n', 1, true) == 1)
        if operation == 'copy' then
          assert(repo:run_git({ 'show', ':' .. source }):find('updated ' .. source .. '\n', 1, true) == 1)
          assert(repo:run_git({ 'ls-files', '--', source }) == source)
        else
          assert(repo:run_git({ 'ls-files', '--', source }) == '')
        end
        return { from = base }
      end, function(repo)
        selection.select_path(selection.wait_for_list(operation == 'copy' and 2 or 1), destination)
        selection.wait_for_two_sided_current(
          repo,
          destination,
          old,
          current,
          source,
          operation == 'rename' and 'Moved from' or 'Copied from'
        )
      end)
    end
  end
end

return M
