local git = require('diffreview.diffs.git')
local git_repo = require('helpers.git_repo')
local M = {}

---@param repo GitRepo
---@param oid string
---@return string
local function load_blob(repo, oid)
  local result, bytes = repo:load_blob(oid)

  assert(result.ok, 'expected blob loading to succeed: ' .. (result.error or 'unknown error'))
  assert(bytes ~= nil, 'expected blob bytes')
  return bytes
end

---@param path string
---@param bytes string
local function write_raw(path, bytes)
  local descriptor = assert(vim.uv.fs_open(path, 'w', 420))
  local written, write_error = vim.uv.fs_write(descriptor, bytes, 0)
  vim.uv.fs_close(descriptor)
  assert(written == #bytes, write_error or 'failed to write fixture bytes')
end

M.load_blob_should_return_exact_bytes_when_oid_identifies_text_blob = function()
  git_repo.with_repo(function(test_repo)
    write_raw(test_repo.cwd .. '/file.txt', 'first\n\nthird\n')
    local oid = test_repo:run_git({ 'hash-object', '-w', '--', 'file.txt' })

    local bytes = load_blob(git.get_repo(test_repo.cwd), oid)

    assert(bytes == 'first\n\nthird\n', 'expected blob bytes including trailing newline')
  end)
end

M.load_blob_should_return_empty_string_when_blob_is_empty = function()
  git_repo.with_repo(function(test_repo)
    write_raw(test_repo.cwd .. '/empty.txt', '')
    local oid = test_repo:run_git({ 'hash-object', '-w', '--', 'empty.txt' })

    local bytes = load_blob(git.get_repo(test_repo.cwd), oid)

    assert(bytes == '', 'expected an empty blob')
  end)
end

M.load_blob_should_return_binary_bytes_when_blob_contains_nul_and_crlf = function()
  git_repo.with_repo(function(test_repo)
    write_raw(test_repo.cwd .. '/binary.dat', '\0first\r\nsecond\0')
    local oid = test_repo:run_git({ 'hash-object', '-w', '--', 'binary.dat' })

    local bytes = load_blob(git.get_repo(test_repo.cwd), oid)

    assert(bytes == '\0first\r\nsecond\0', 'expected unchanged binary bytes and line endings')
  end)
end

M.load_blob_should_return_error_when_oid_does_not_exist = function()
  git_repo.with_repo(function(test_repo)
    local result, bytes = git.get_repo(test_repo.cwd):load_blob(string.rep('f', 40))

    assert(not result.ok, 'expected blob loading to fail')
    assert(result.error ~= nil, 'expected blob loading error details')
    assert(bytes == nil, 'expected no blob bytes')
  end)
end

M.load_blob_should_error_when_oid_has_invalid_form = function()
  local repo = git.get_repo(nil)

  for _, oid in ipairs({ 'HEAD', '', 'not-an-oid', '123xyz' }) do
    local success = pcall(function()
      repo:load_blob(oid)
    end)
    assert(not success, 'expected invalid OID to raise an error: ' .. oid)
  end
end

return M
