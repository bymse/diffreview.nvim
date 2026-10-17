local comments = require('diffreview.comments')
local diffs = require('diffreview.diffs')
local git_repo = require('helpers.git_repo')
local M = {}

M.add_should_support_sideless_lifecycle_when_a_real_git_diff_is_loaded = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'before' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'after' })
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded)
    local id = 'stored:tracked.txt'
    local diff = assert(diffs.load_selected_view(loaded, id))
    local review = comments.new()
    local whole = assert(review:add({ file_id = id, text = 'whole file' }, diff))
    assert(vim.deep_equal(whole.target, { file_id = id }))
    local old = assert(review:add({ file_id = id, side = 'old', text = 'old' }, diff))
    local current = assert(review:add({ file_id = id, side = 'current', text = 'current' }, diff))
    assert(whole.id ~= old.id and whole.id ~= current.id and old.id ~= current.id)
    local edited = assert(review:edit(whole.id, 'edited'))
    assert(edited.id == whole.id and edited.text == 'edited' and vim.deep_equal(edited.target, whole.target))
    local resolved = assert(review:resolve(whole.id))
    assert(resolved.id == whole.id and resolved.state == 'resolved' and vim.deep_equal(resolved.target, whole.target))
    local reopened = assert(review:reopen(whole.id))
    assert(reopened.id == whole.id and reopened.state == 'open' and vim.deep_equal(reopened.target, whole.target))
    assert(vim.deep_equal(assert(review:list(id)), { reopened, old, current }))
    assert(review:delete(whole.id))
    assert(vim.deep_equal(assert(review:list()), { old, current }))
  end)
end

M.add_should_accept_sideless_files_without_relaxing_line_targets_when_worktree_views_are_path_backed = function()
  git_repo.with_repo(function(repo)
    repo:write_file('tracked.txt', { 'before' })
    repo:add('tracked.txt')
    repo:commit('base')
    repo:write_file('tracked.txt', { 'after', 'second' })
    local result, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(result.ok and loaded)
    local id = 'stored:tracked.txt'
    local diff = assert(diffs.load_selected_view(loaded, id))
    assert(diff.current and diff.current.content.kind == 'text' and diff.current.content.source == 'path')
    local review = comments.new()
    local whole = assert(review:add({ file_id = id, text = 'whole' }, diff))
    for _, input in ipairs({
      { file_id = id, text = 'line', line_start = 1, line_end = 1 },
      { file_id = id, side = 'current', text = 'line', line_start = 1, line_end = 1 },
    }) do
      local rejected, err = review:add(input, diff)
      assert(rejected == nil and type(err) == 'string' and err ~= '')
      assert(vim.deep_equal(assert(review:list()), { whole }))
    end
    local snapshot = assert(diffs.load_selected_view(loaded, id, nil, true))
    assert(review:add({ file_id = id, side = 'current', text = 'line', line_start = 1, line_end = 1 }, snapshot))
  end)
end

return M
