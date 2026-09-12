local git = require('diffreview.diffs.git')
local git_repo = require('helpers.git_repo')
local M = {}

---@param repo GitRepo
---@param oid string
---@return string[]
local function load_text(repo, oid)
  local result, lines = repo:load_text(oid)

  assert(result.ok, 'expected text loading to succeed: ' .. (result.error or 'unknown error'))
  assert(lines ~= nil, 'expected text lines')
  return lines
end

M.load_text_should_return_lines_when_oid_identifies_text_blob = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('file.txt', { 'first', '', 'third' })
    local oid = test_repo:run_git({ 'hash-object', '-w', '--', 'file.txt' })

    local lines = load_text(git.get_repo(test_repo.cwd), oid)

    assert(vim.deep_equal(lines, { 'first', '', 'third' }), 'expected blob content as lines')
  end)
end

M.load_text_should_return_empty_array_when_blob_is_empty = function()
  git_repo.with_repo(function(test_repo)
    test_repo:write_file('empty.txt', {})
    local oid = test_repo:run_git({ 'hash-object', '-w', '--', 'empty.txt' })

    local lines = load_text(git.get_repo(test_repo.cwd), oid)

    assert(#lines == 0, 'expected no lines')
  end)
end

M.load_text_should_return_error_when_oid_does_not_exist = function()
  git_repo.with_repo(function(test_repo)
    local result, lines = git.get_repo(test_repo.cwd):load_text(string.rep('f', 40))

    assert(not result.ok, 'expected text loading to fail')
    assert(result.error ~= nil, 'expected text loading error details')
    assert(lines == nil, 'expected no text lines')
  end)
end

M.load_text_should_error_when_oid_has_invalid_form = function()
  local repo = git.get_repo(nil)

  for _, oid in ipairs({ 'HEAD', '', 'not-an-oid', '123xyz' }) do
    local success = pcall(function()
      repo:load_text(oid)
    end)
    assert(not success, 'expected invalid OID to raise an error: ' .. oid)
  end
end

return M
