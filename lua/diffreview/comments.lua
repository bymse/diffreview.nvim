local M = {}

---@class ReviewComment: CommentLocation
---@field id string
---@field body string
---@field status 'open'|'resolved'|'stale'
---@field anchor_lines string[]|nil
---@field context_before string|nil
---@field context_after string|nil

---@class CommentLocation
---@field file_id string
---@field start_line integer|nil
---@field end_line integer|nil

---@class Comments
---@field records ReviewComment[]
local Comments = {}
Comments.__index = Comments

local anchor_fields = { 'start_line', 'end_line', 'anchor_lines', 'context_before', 'context_after' }

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
        type(record.anchor_lines) ~= 'table'
        or not vim.islist(record.anchor_lines)
        or #record.anchor_lines ~= record.end_line - record.start_line + 1
        or (record.context_before ~= nil and type(record.context_before) ~= 'string')
        or (record.context_after ~= nil and type(record.context_after) ~= 'string')
      then
        return false, 'Invalid text comment anchor'
      end
      for _, line in ipairs(record.anchor_lines) do
        if type(line) ~= 'string' then
          return false, 'Invalid text comment line'
        end
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
    record.anchor_lines = {}
    for line = location.start_line, location.end_line do
      record.anchor_lines[#record.anchor_lines + 1] = lines[line]
    end
    record.context_before = lines[location.start_line - 1]
    record.context_after = lines[location.end_line + 1]
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
---@return ReviewComment|nil, string|nil
function Comments:edit(id, body)
  local record = find(self, id)
  if not record then
    return nil, 'Unknown comment ID'
  end
  if not nonblank(body) then
    return nil, 'Comment body must not be blank'
  end
  record.body = body
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
  local entry = loaded.entries_by_id[record.file_id]
  local attached = entry ~= nil and record.start_line == nil
  if entry and record.start_line then
    local view = views[record.file_id]
    local version = view and view.current
    if version and version.content.kind == 'text' and version.content.source == 'snapshot' then
      local lines, anchors = version.content.lines, assert(record.anchor_lines)
      local match
      for first = 1, #lines - #anchors + 1 do
        local last = first + #anchors - 1
        local exact = (record.context_before == nil or lines[first - 1] == record.context_before)
          and (record.context_after == nil or lines[last + 1] == record.context_after)
        for offset, line in ipairs(anchors) do
          if lines[first + offset - 1] ~= line then
            exact = false
            break
          end
        end
        if exact then
          if match then
            match = nil
            break
          end
          match = first
        end
      end
      if match then
        attached = true
        record.start_line, record.end_line = match, match + #anchors - 1
        record.context_before = lines[record.start_line - 1]
        record.context_after = lines[record.end_line + 1]
      end
    end
  end
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

---@param id string
---@param location CommentLocation
---@param lines string[]|nil
---@return ReviewComment|nil, string|nil
function Comments:reattach(id, location, lines)
  local record = find(self, id)
  if not record then
    return nil, 'Unknown comment ID'
  end
  return capture(record, location, lines)
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
