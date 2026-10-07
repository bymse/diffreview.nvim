local selection = require('helpers.functional_review')
local states = require('helpers.git_states')

local M = {}

M.should_show_error_information_when_selected_file_disappears_after_listing = function()
  selection.ensure_setup()
  local path = 'removed-after-listing.txt'
  selection.with_review(function(repo)
    local base = states.modify_file(repo, path, 'unstaged')
    return { from = base }
  end, function(repo)
    local review_id = selection.wait_for_list(1)
    assert(vim.fn.delete(repo.cwd .. '/' .. path) == 0, 'failed to remove listed file')
    selection.select_path(review_id, path)
    selection.wait_for_information({
      'Content load error',
      'Path: ' .. path,
    })
    assert(
      vim.fn.getqflist({ id = review_id, items = 1 }).items[1].text:match('^%[ %]') ~= nil,
      'expected failed selection not to mark file viewed'
    )
  end)
end

return M
