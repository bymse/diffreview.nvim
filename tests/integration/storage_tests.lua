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
      version = 2,
      comments = {},
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
        value.version = 1
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

M.save_should_preserve_valid_checkpoint_when_comment_schema_is_invalid = function()
  git_repo.with_repo(function(repo)
    local directory = repo.cwd .. '/.git/diffreview-nvim'
    local identity =
      { repository_root = repo.cwd, source = 'branch:main', baseline = 'head:HEAD', target = 'worktree:current' }
    local state = {
      version = 2,
      identity = identity,
      from_oid = string.rep('a', 40),
      files = {},
      comments = {
        { id = 'one', file_id = 'stored:f', display_path = 'f', body = 'note', resolved = false, stale = false },
        {
          id = 'two',
          file_id = 'stored:f',
          display_path = 'f',
          body = 'text',
          resolved = true,
          stale = true,
          side = 'old',
          start_line = 1,
          end_line = 2,
          anchor_lines = { 'a', 'b' },
          context_after = 'c',
        },
      },
    }
    assert(storage.save(directory, state))
    local path = storage.path(directory, identity)
    local original = vim.fn.readfile(path)[1]
    local cases = {
      function(value)
        value.comments = nil
      end,
      function(value)
        value.comments = { bad = true }
      end,
      function(value)
        value.comments[2].id = 'one'
      end,
      function(value)
        value.comments[1].id = ''
      end,
      function(value)
        value.comments[1].id = 1
      end,
      function(value)
        value.comments[1].file_id = ''
      end,
      function(value)
        value.comments[1].display_path = false
      end,
      function(value)
        value.comments[1].body = ' \t\n'
      end,
      function(value)
        value.comments[1].resolved = 1
      end,
      function(value)
        value.comments[1].stale = nil
      end,
      function(value)
        value.comments[1].context_before = 'bad'
      end,
      function(value)
        value.comments[1].anchor_lines = {}
      end,
      function(value)
        value.comments[1].start_line = 1
      end,
      function(value)
        value.comments[2].side = 'bad'
      end,
      function(value)
        value.comments[2].start_line = 0
      end,
      function(value)
        value.comments[2].end_line = 1.5
      end,
      function(value)
        value.comments[2].start_line = 3
      end,
      function(value)
        value.comments[2].anchor_lines = { 'a' }
      end,
      function(value)
        value.comments[2].anchor_lines = { 'a', false }
      end,
      function(value)
        value.comments[2].context_after = {}
      end,
      function(value)
        value.comments[2].context_before = false
      end,
    }
    for _, corrupt in ipairs(cases) do
      local value = vim.deepcopy(state)
      corrupt(value)
      local saved, save_error = storage.save(directory, value)
      assert(not saved and save_error ~= nil and vim.fn.readfile(path)[1] == original)
      local raw = vim.json.encode(value)
      assert(vim.fn.writefile({ raw }, path) == 0)
      local loaded, load_error = storage.load(directory, identity)
      assert(loaded == nil and load_error ~= nil and vim.fn.readfile(path)[1] == raw)
      assert(vim.fn.writefile({ original }, path) == 0)
    end
    assert(vim.deep_equal(assert(storage.load(directory, identity)).comments, state.comments))
  end)
end

return M
