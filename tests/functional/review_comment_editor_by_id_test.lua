local git_repo = require('helpers.git_repo')
local functional_review = require('helpers.functional_review')
local diffs = require('diffreview.diffs')
local review_progress = require('diffreview.review_progress')
local review = require('diffreview.review')
local storage = require('diffreview.storage')

local M = {}

local function with_records(run)
  git_repo.with_repo(function(repo)
    repo:write_file('file.txt', { 'base' })
    repo:add('file.txt')
    repo:commit('base')
    repo:write_file('file.txt', { 'changed' })
    local _, loaded = diffs.load_diffs({ cwd = repo.cwd, from = 'HEAD' })
    assert(loaded)
    local progress = review_progress.reconcile(nil, loaded)
    progress.comments = {
      {
        id = 'first',
        file_id = 'stored:file.txt',
        display_path = 'file.txt',
        body = 'first',
        resolved = false,
        stale = false,
      },
      {
        id = 'second',
        file_id = 'stored:file.txt',
        display_path = 'file.txt',
        body = 'second',
        resolved = false,
        stale = false,
      },
      {
        id = 'stale',
        file_id = 'stored:missing.txt',
        display_path = 'missing.txt',
        body = 'stale note',
        resolved = true,
        stale = true,
      },
    }
    assert(storage.save(loaded.storage_path, progress))
    local session = review.new({ layout = 'vertical', view = 'side_by_side' })
    session:start({ cwd = repo.cwd, from = 'HEAD' })
    functional_review.wait_for_list(1)
    local ok, err = xpcall(function()
      run(session, loaded)
    end, debug.traceback)
    session:stop()
    assert(ok, err)
  end)
end

local function save(body)
  local buffer = vim.api.nvim_get_current_buf()
  assert(vim.bo[buffer].buftype == 'acwrite')
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { body })
  vim.cmd('write')
  assert(vim.wait(2000, function()
    return not vim.bo[buffer].modified
  end))
end

M.edit_comment_by_id_should_focus_edit_and_delete_record_when_id_is_known = function()
  with_records(function(session, loaded)
    assert(session:edit_comment_by_id('first'))
    local buffer = vim.api.nvim_get_current_buf()
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'first' }))
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'unsaved first' })
    assert(session:edit_comment_by_id('first'))
    assert(vim.api.nvim_get_current_buf() == buffer)
    assert(not session:edit_comment_by_id('second'))
    assert(not session:edit_comment_by_id('unknown'))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), { 'unsaved first' }))
    save('first saved')
    local saved = assert(storage.load(loaded.storage_path, loaded.identity))
    assert(saved.comments[1].id == 'first' and saved.comments[1].body == 'first saved')
    assert(session:edit_comment_by_id('second'))
    assert(not vim.api.nvim_buf_is_valid(buffer))
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { 'second' }))
    save('')
    saved = assert(storage.load(loaded.storage_path, loaded.identity))
    assert(#saved.comments == 2 and saved.comments[1].id == 'first' and saved.comments[2].id == 'stale')
  end)
end

M.edit_comment_by_id_should_accept_stale_record_without_navigation_and_reject_obsolete_owner_when_stopped = function()
  with_records(function(session, loaded)
    local review_tab = vim.api.nvim_get_current_tabpage()
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if tab ~= review_tab then
        vim.api.nvim_set_current_tabpage(tab)
        break
      end
    end
    assert(session:edit_comment_by_id('stale'))
    assert(vim.api.nvim_get_current_tabpage() == review_tab)
    save('stale edited')
    local saved = assert(storage.load(loaded.storage_path, loaded.identity))
    assert(saved.comments[3].id == 'stale' and saved.comments[3].body == 'stale edited')
    assert(saved.comments[3].stale and saved.comments[3].resolved)
    session:stop()
    local buffers = vim.api.nvim_list_bufs()
    assert(not session:edit_comment_by_id('stale'))
    assert(vim.deep_equal(vim.api.nvim_list_bufs(), buffers))
    assert(vim.deep_equal(assert(storage.load(loaded.storage_path, loaded.identity)), saved))
  end)
end

return M
