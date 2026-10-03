local M = {}

---@param result DiffLoadResult
---@param kind DiffLoadErrorKind
function M.assert_failure(result, kind)
  assert(not result.ok, 'expected load to fail')
  assert(result.error ~= nil, 'expected structured error')
  assert(result.error.kind == kind, 'expected error kind ' .. kind)
  if result.error.detail ~= nil then
    assert(result.error.detail ~= '', 'expected nonempty diagnostic detail')
  end
end

---@param loaded LoadedDiffs
---@param id string
---@return ChangedFileViewModel
function M.file_by_id(loaded, id)
  for _, file in ipairs(loaded.files) do
    if file.id == id then
      return file
    end
  end
  error('missing file ' .. id)
end

return M
