local M = {}

---@class ReviewComment: CommentLocation
---@field id string
---@field body string
---@field status 'open'|'resolved'|'stale'
---@field anchor_hash string|nil

---@class CommentLocation
---@field file_id string
---@field start_line integer|nil
---@field end_line integer|nil

---@class Comments
---@field records ReviewComment[]
local Comments = {}
Comments.__index = Comments

local anchor_fields = { 'start_line', 'end_line', 'anchor_hash' }

local function nonblank(value)
  return type(value) == 'string' and value:find('%S') ~= nil
end

local function positive_integer(value)
  return type(value) == 'number' and value > 0 and value < math.huge and value % 1 == 0
end

---@param location CommentLocation
---@return boolean
function M.valid_location(location)
  if type(location) ~= 'table' or not nonblank(location.file_id) or rawget(location, 'side') ~= nil then
    return false
  end
  if location.start_line == nil then
    return location.end_line == nil
  end
  return positive_integer(location.start_line)
    and positive_integer(location.end_line)
    and location.start_line <= location.end_line
end

---@param records ReviewComment[]
---@return boolean, string|nil
function M.validate(records)
  if type(records) ~= 'table' or not vim.islist(records) then
    return false, 'Invalid review comment list'
  end
  local seen = {}
  for _, record in ipairs(records) do
    if
      type(record) ~= 'table'
      or not nonblank(record.id)
      or seen[record.id]
      or not M.valid_location(record)
      or not nonblank(record.body)
      or (record.status ~= 'open' and record.status ~= 'resolved' and record.status ~= 'stale')
      or rawget(record, 'resolved') ~= nil
      or rawget(record, 'stale') ~= nil
      or rawget(record, 'display_path') ~= nil
      or rawget(record, 'anchor_lines') ~= nil
      or rawget(record, 'context_before') ~= nil
      or rawget(record, 'context_after') ~= nil
    then
      return false, 'Invalid review comment record'
    end
    seen[record.id] = true
    if record.start_line == nil then
      for _, field in ipairs(anchor_fields) do
        if record[field] ~= nil then
          return false, 'Invalid file comment anchor'
        end
      end
    else
      if
        type(record.anchor_hash) ~= 'string'
        or #record.anchor_hash ~= 64
        or record.anchor_hash:match('^%x+$') == nil
      then
        return false, 'Invalid text comment anchor'
      end
    end
  end
  return true, nil
end

---@param records ReviewComment[]
---@return Comments
function M.new(records)
  return setmetatable({ records = records }, Comments)
end

---@return Comments
function Comments:fork()
  return M.new(vim.deepcopy(self.records))
end

local function find(self, id)
  for index, record in ipairs(self.records) do
    if record.id == id then
      return record, index
    end
  end
end

local function range_hash(record, lines)
  if lines == nil or record.end_line > #lines then
    return nil
  end
  return vim.fn.sha256(table.concat(lines, '\n', record.start_line, record.end_line))
end

local function current_hash(record, loaded, views)
  if loaded.entries_by_id[record.file_id] == nil then
    return nil
  end
  local view = views[record.file_id]
  local version = view and view.current
  if version and version.content.kind == 'text' and version.content.source == 'snapshot' then
    return range_hash(record, version.content.lines)
  end
end

local function capture(record, location, lines)
  if not M.valid_location(location) then
    return nil, 'Invalid comment location'
  end
  if location.start_line and (lines == nil or location.end_line > #lines) then
    return nil, 'Comment line range is outside comparison text'
  end
  for _, field in ipairs(anchor_fields) do
    record[field] = nil
  end
  record.file_id = location.file_id
  if location.start_line then
    record.start_line, record.end_line = location.start_line, location.end_line
    record.anchor_hash = range_hash(record, lines)
  end
  if record.status ~= 'resolved' then
    record.status = 'open'
  end
  return vim.deepcopy(record), nil
end

---@param location CommentLocation
---@param body string
---@param lines string[]|nil
---@return ReviewComment|nil, string|nil
function Comments:add(location, body, lines)
  if not nonblank(body) then
    return nil, 'Comment body must not be blank'
  end
  local record = { id = vim.fn.sha256(vim.fn.tempname() .. tostring(vim.uv.hrtime())), body = body, status = 'open' }
  local result, err = capture(record, location, lines)
  if result then
    self.records[#self.records + 1] = record
  end
  return result, err
end

---@param id string
---@param body string
---@param loaded LoadedDiffs|nil
---@param views table<string, DiffViewModel>|nil
---@return ReviewComment|nil, string|nil
function Comments:edit(id, body, loaded, views)
  local record = find(self, id)
  if not record then
    return nil, 'Unknown comment ID'
  end
  if not nonblank(body) then
    return nil, 'Comment body must not be blank'
  end
  record.body = body
  if record.status == 'stale' and loaded then
    if record.start_line then
      local hash = current_hash(record, loaded, views or {})
      if hash then
        record.anchor_hash = hash
        record.status = 'open'
      end
    elseif loaded.entries_by_id[record.file_id] then
      record.status = 'open'
    end
  end
  return vim.deepcopy(record), nil
end

---@param id string
---@return boolean|nil, string|nil
function Comments:delete(id)
  local record, index = find(self, id)
  if not record then
    return nil, 'Unknown comment ID'
  end
  table.remove(self.records, index)
  return true, nil
end

---@param id string
---@return ReviewComment|nil, string|nil
function Comments:resolve(id)
  local record = find(self, id)
  if not record then
    return nil, 'Unknown comment ID'
  end
  record.status = 'resolved'
  return vim.deepcopy(record), nil
end

local function reconcile_record(record, loaded, views)
  local attached = loaded.entries_by_id[record.file_id] ~= nil
    and (record.start_line == nil or current_hash(record, loaded, views) == record.anchor_hash)
  if record.status ~= 'resolved' then
    record.status = attached and 'open' or 'stale'
  end
end

---@param id string
---@param loaded LoadedDiffs
---@param views table<string, DiffViewModel>
---@return ReviewComment|nil, string|nil
function Comments:reopen(id, loaded, views)
  local record = find(self, id)
  if not record then
    return nil, 'Unknown comment ID'
  end
  record.status = 'open'
  reconcile_record(record, loaded, views)
  return vim.deepcopy(record), nil
end

---@param loaded LoadedDiffs
---@param views table<string, DiffViewModel>
---@return nil
function Comments:reconcile(loaded, views)
  for _, record in ipairs(self.records) do
    reconcile_record(record, loaded, views)
  end
end

return M
