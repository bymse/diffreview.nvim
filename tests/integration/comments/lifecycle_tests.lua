local comments = require('diffreview.comments')
local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local M = {}

M.add_should_support_comment_lifecycle_when_current_diff_views_are_supplied = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'unchanged', 'before', 'last' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'unchanged', 'after', 'last' })
    repo:write_file('untracked.txt', { 'new' })
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded)
    local tracked = assert(diffs.load_selected_view(loaded, 'stored:tracked.txt', nil, true))
    local untracked = assert(diffs.load_selected_view(loaded, 'new:untracked.txt', nil, true))
    local review, other = comments.new(), comments.new()
    local old = assert(
      review:add(
        { file_id = 'stored:tracked.txt', side = 'old', text = 'baseline', line_start = 1, line_end = 1 },
        tracked
      )
    )
    local current = assert(
      review:add(
        { file_id = 'stored:tracked.txt', side = 'current', text = 'current', line_start = 1, line_end = 3 },
        tracked
      )
    )
    local new = assert(review:add({ file_id = 'new:untracked.txt', side = 'current', text = 'whole file' }, untracked))
    assert(vim.deep_equal(old.target, { file_id = 'stored:tracked.txt', side = 'old', line_start = 1, line_end = 1 }))
    assert(
      vim.deep_equal(current.target, { file_id = 'stored:tracked.txt', side = 'current', line_start = 1, line_end = 3 })
    )
    local edited = assert(review:edit(old.id, ' \n revised '))
    assert(edited.id == old.id and edited.text == ' \n revised ' and vim.deep_equal(edited.target, old.target))
    assert(vim.deep_equal(assert(review:list('stored:tracked.txt')), { edited, current }))
    assert(vim.deep_equal(assert(review:list()), { edited, current, new }))
    repo:write_file('tracked.txt', {})
    local shorter = assert(diffs.load_selected_view(loaded, 'stored:tracked.txt', nil, true))
    local rejected, err = review:add({
      file_id = 'stored:tracked.txt',
      side = 'current',
      text = 'current bounds',
      line_start = 3,
      line_end = 3,
    }, shorter)
    assert(rejected == nil and type(err) == 'string' and err ~= '')
    assert(vim.deep_equal(assert(review:list()), { edited, current, new }))
    local whole =
      assert(review:add({ file_id = 'stored:tracked.txt', side = 'current', text = 'whole empty file' }, shorter))
    assert(review:delete(current.id))
    assert(review:edit(current.id, 'gone') == nil)
    assert(#assert(review:list('stored:tracked.txt')) == 2)
    assert(vim.deep_equal(assert(other:list()), {}))
    local independent =
      assert(other:add({ file_id = 'stored:tracked.txt', side = 'old', text = 'independent' }, shorter))
    assert(review:delete(old.id))
    assert(vim.deep_equal(assert(other:list()), { independent }))
    assert(vim.deep_equal(assert(review:list('stored:tracked.txt')), { whole }))
  end)
end

return M
