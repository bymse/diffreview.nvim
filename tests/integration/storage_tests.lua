local git_repo = require('helpers.git_repo')
local storage = require('diffreview.storage')

local M = {}

M.load_should_reject_corrupt_state_without_overwriting_it = function()
  git_repo.with_repo(function(repo)
    local directory = repo.cwd .. '/.git/diffreview-nvim'
    local identity =
      { repository_root = repo.cwd, source = 'branch:a/b', baseline = 'head:HEAD', target = 'worktree:current' }
    assert(vim.fn.mkdir(directory, 'p') == 1)
    local path = storage.path(directory, identity)
    assert(vim.fn.writefile({ '{bad' }, path) == 0)
    local state, err = storage.load(directory, identity)
    assert(state == nil and err ~= nil)
    assert(vim.fn.readfile(path)[1] == '{bad')
  end)
end

M.load_should_reject_incompatible_identity_and_invalid_checkpoint_without_overwriting = function()
  git_repo.with_repo(function(repo)
    local directory = repo:run_git({ 'rev-parse', '--path-format=absolute', '--git-path', 'diffreview-nvim' })
    local identity = {
      repository_root = repo.cwd,
      source = 'branch:refs/heads/a/b',
      baseline = 'head:HEAD',
      target = 'worktree:current',
    }
    local state = {
      version = 1,
      identity = identity,
      from_oid = string.rep('a', 40),
      files = {
        {
          id = 'new:f',
          display_path = 'f',
          added_lines = 1,
          removed_lines = 0,
          fingerprint = string.rep('b', 64),
          viewed_fingerprint = string.rep('b', 64),
        },
      },
    }
    assert(storage.save(directory, state))
    local path = storage.path(directory, identity)
    local cases = {
      function(value)
        value.version = 2
      end,
      function(value)
        value.identity.source = 'branch:refs/heads/different'
      end,
      function(value)
        value.files[1].viewed_fingerprint = 'not-a-hash'
      end,
      function(value)
        value.files[1].viewed_fingerprint = {}
      end,
      function(value)
        value.files[1].fingerprint = 'a'
      end,
      function(value)
        value.from_oid = 'a'
      end,
      function(value)
        value.to_oid = 'not-an-oid'
      end,
      function(value)
        value.head_oid = 'abcd'
      end,
    }
    for _, corrupt in ipairs(cases) do
      local value = vim.deepcopy(state)
      corrupt(value)
      local raw = vim.json.encode(value)
      assert(vim.fn.writefile({ raw }, path) == 0)
      local loaded, err = storage.load(directory, identity)
      assert(loaded == nil and err ~= nil)
      assert(vim.fn.readfile(path)[1] == raw)
    end
  end)
end

M.load_should_reject_state_symlink_even_when_target_exists = function()
  git_repo.with_repo(function(repo)
    local directory = repo:run_git({ 'rev-parse', '--path-format=absolute', '--git-path', 'diffreview-nvim' })
    local identity = {
      repository_root = repo.cwd,
      source = 'branch:refs/heads/main',
      baseline = 'head:HEAD',
      target = 'worktree:current',
    }
    assert(vim.fn.mkdir(directory, 'p') == 1)
    local path = storage.path(directory, identity)
    local target = directory .. '/existing.json'
    assert(vim.fn.writefile({ '{}' }, target) == 0)
    assert(vim.uv.fs_symlink(target, path))
    local state, err = storage.load(directory, identity)
    assert(state == nil and err ~= nil)
    assert(vim.uv.fs_lstat(path).type == 'link')
    assert(vim.uv.fs_readlink(path) == target)
    assert(vim.fn.readfile(target)[1] == '{}')
  end)
end

return M
