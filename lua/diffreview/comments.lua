local M = {}

---@class ReviewComment: CommentLocation
---@field id string
---@field file_id string
---@field display_path string
---@field body string
---@field resolved boolean
---@field stale boolean
---@field side 'current'|nil
---@field start_line integer|nil
---@field end_line integer|nil
---@field anchor_lines string[]|nil
---@field context_before string|nil
---@field context_after string|nil

---@class CommentLocation
---@field file_id string
---@field side 'current'|nil
---@field start_line integer|nil
---@field end_line integer|nil

---@alias CommentAction 'add'|'edit'|'delete'|'resolve'|'reopen'|'reattach'

local location_fields = { 'side', 'start_line', 'end_line', 'anchor_lines', 'context_before', 'context_after' }

---@param value any
---@return boolean
local function nonblank(value)
  return type(value) == 'string' and value:find('%S') ~= nil
end

---@param value any
---@return boolean
local function positive_integer(value)
  return type(value) == 'number' and value > 0 and value < math.huge and value % 1 == 0
end

---@param location CommentLocation
---@return boolean
function M.valid_location(location)
  if type(location) ~= 'table' or not nonblank(location.file_id) then
    return false
  end
  if location.side == nil then
    return location.start_line == nil and location.end_line == nil
  end
  return location.side == 'current'
    and positive_integer(location.start_line)
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
      or type(record.display_path) ~= 'string'
      or not nonblank(record.body)
      or type(record.resolved) ~= 'boolean'
      or type(record.stale) ~= 'boolean'
    then
      return false, 'Invalid review comment record'
    end
    seen[record.id] = true
    if record.side == nil then
      for _, field in ipairs(location_fields) do
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
---@param action CommentAction
---@param id string|nil
---@param body string|nil
---@param location CommentLocation|nil
---@param display_path string|nil
---@param lines string[]|nil
---@return ReviewComment[]|nil, ReviewComment|boolean|nil, string|nil
function M.apply(records, action, id, body, location, display_path, lines)
  local candidate = vim.deepcopy(records)
  local record, index
  for position, item in ipairs(candidate) do
    if item.id == id then
      record, index = item, position
      break
    end
  end
  if action ~= 'add' and record == nil then
    return nil, nil, 'Unknown comment ID'
  end
  if (action == 'add' or action == 'edit') and not nonblank(body) then
    return nil, nil, 'Comment body must not be blank'
  end
  if action == 'add' then
    record = {
      id = vim.fn.sha256(vim.fn.tempname() .. tostring(vim.uv.hrtime())),
      body = assert(body),
      resolved = false,
      stale = false,
    }
    candidate[#candidate + 1] = record
  end
  if action == 'add' or action == 'reattach' then
    if location == nil or not M.valid_location(location) or display_path == nil then
      return nil, nil, 'Invalid comment location'
    end
    record = assert(record)
    for _, field in ipairs(location_fields) do
      record[field] = nil
    end
    record.file_id, record.display_path = location.file_id, display_path
    record.stale = false
    if location.side ~= nil then
      if lines == nil or assert(location.end_line) > #lines then
        return nil, nil, 'Comment line range is outside comparison text'
      end
      record.side, record.start_line, record.end_line = location.side, location.start_line, location.end_line
      record.anchor_lines = {}
      for line = assert(location.start_line), assert(location.end_line) do
        record.anchor_lines[#record.anchor_lines + 1] = lines[line]
      end
      record.context_before = lines[location.start_line - 1]
      record.context_after = lines[location.end_line + 1]
    end
  elseif action == 'edit' then
    assert(record).body = assert(body)
  elseif action == 'delete' then
    table.remove(candidate, assert(index))
  elseif action == 'resolve' or action == 'reopen' then
    assert(record).resolved = action == 'resolve'
  end
  local valid, err = M.validate(candidate)
  if not valid then
    return nil, nil, err
  end
  return candidate, action == 'delete' and true or vim.deepcopy(record), nil
end

---@param records ReviewComment[]
---@param loaded LoadedDiffs
---@param views table<string, DiffViewModel>
---@return ReviewComment[]
function M.reconcile(records, loaded, views)
  local candidate = vim.deepcopy(records)
  for _, record in ipairs(candidate) do
    local entry = loaded.entries_by_id[record.file_id]
    record.stale = true
    if entry ~= nil and record.side == nil then
      record.display_path = entry.summary.display_path
      record.stale = false
    elseif entry ~= nil then
      local view = views[record.file_id]
      local version = view and view[record.side]
      if version and version.content.kind == 'text' and version.content.source == 'snapshot' then
        local lines = version.content.lines
        local anchors = assert(record.anchor_lines)
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
            if match ~= nil then
              match = nil
              break
            end
            match = first
          end
        end
        if match ~= nil then
          record.start_line, record.end_line = match, match + #anchors - 1
          record.context_before = lines[record.start_line - 1]
          record.context_after = lines[record.end_line + 1]
          record.display_path = entry.summary.display_path
          record.stale = false
        end
      end
    end
  end
  return candidate
end

return M
