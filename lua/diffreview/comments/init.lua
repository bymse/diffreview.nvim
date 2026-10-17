---@alias ReviewCommentSide 'old'|'current'
---@alias ReviewCommentState 'open'|'resolved'|'stale'

---@class ReviewCommentInput
---@field file_id string
---@field side ReviewCommentSide
---@field text string
---@field line_start integer|nil
---@field line_end integer|nil

---@class ReviewCommentTarget
---@field file_id string
---@field side ReviewCommentSide
---@field line_start integer|nil
---@field line_end integer|nil

---@class ReviewComment
---@field id string
---@field text string
---@field state ReviewCommentState
---@field target ReviewCommentTarget

local M = {}

---@class ReviewCommentCollection
---@field private records ReviewComment[]
local ReviewCommentCollection = {}
ReviewCommentCollection.__index = ReviewCommentCollection

---@param value any
---@return boolean
local function nonempty_string(value)
  return type(value) == 'string' and value ~= ''
end

---@param value any
---@return boolean
local function positive_integer(value)
  return type(value) == 'number' and value > 0 and value < math.huge and value == math.floor(value)
end

---@param value any
---@return boolean
local function valid_text(value)
  return type(value) == 'string' and value:find('%S') ~= nil
end

---@param content any
---@return boolean
local function valid_content(content)
  if type(content) ~= 'table' then
    return false
  end
  if content.kind == 'binary' then
    return true
  end
  if content.kind ~= 'text' then
    return false
  end
  if content.source == 'path' then
    return nonempty_string(content.absolute_path)
  end
  if content.source ~= 'snapshot' or type(content.lines) ~= 'table' then
    return false
  end
  local count, maximum = 0, 0
  for index, line in pairs(content.lines) do
    if not positive_integer(index) or type(line) ~= 'string' then
      return false
    end
    count = count + 1
    maximum = math.max(maximum, index)
  end
  return count == maximum
end

---@param diff DiffViewModel
---@param name ReviewCommentSide
---@return DiffFileVersion|nil, string|nil
local function validate_side(diff, name)
  if type(diff) ~= 'table' then
    return nil, 'Expected the commented diff'
  end
  local operation = diff.operation
  if
    operation ~= 'added'
    and operation ~= 'untracked'
    and operation ~= 'deleted'
    and operation ~= 'modified'
    and operation ~= 'renamed'
    and operation ~= 'copied'
    and operation ~= 'type_changed'
    and operation ~= 'unmerged'
  then
    return nil, 'Comment diff is unavailable'
  end
  if
    (name == 'old' and (operation == 'added' or operation == 'untracked' or operation == 'unmerged'))
    or (name == 'current' and operation == 'deleted')
  then
    return nil, 'Comment side is unavailable'
  end
  local side = diff[name]
  if type(side) ~= 'table' or not valid_content(side.content) then
    return nil, 'Comment side is unavailable'
  end
  return side, nil
end

---@return ReviewCommentCollection
function M.new()
  return setmetatable({ records = {} }, ReviewCommentCollection)
end

---The caller supplies the current diff for input.file_id; line ranges require snapshot text.
---@param input ReviewCommentInput
---@param diff DiffViewModel
---@return ReviewComment|nil, string|nil
function ReviewCommentCollection:add(input, diff)
  if type(input) ~= 'table' or not valid_text(input.text) then
    return nil, 'Expected nonblank comment text'
  end
  if not nonempty_string(input.file_id) or (input.side ~= 'old' and input.side ~= 'current') then
    return nil, 'Expected a file ID and old or current side'
  end
  local side, side_error = validate_side(diff, input.side)
  if side == nil then
    return nil, side_error
  end
  local first, last = input.line_start, input.line_end
  if first ~= nil or last ~= nil then
    if not positive_integer(first) or not positive_integer(last) then
      return nil, 'Expected both range endpoints as positive finite integers'
    end
    if
      first > last
      or side.content.kind ~= 'text'
      or side.content.source ~= 'snapshot'
      or last > #side.content.lines
    then
      return nil, 'Comment range is outside the text snapshot'
    end
  end
  local id = vim.fn.sha256(vim.json.encode({ input.file_id, input.side, first or 0, last or 0 }))
  if self:find_index(id) ~= nil then
    return nil, 'A comment already exists for this target'
  end
  ---@type ReviewComment
  local record = {
    id = id,
    text = input.text,
    state = 'open',
    target = { file_id = input.file_id, side = input.side, line_start = first, line_end = last },
  }
  self.records[#self.records + 1] = record
  return vim.deepcopy(record), nil
end

---@private
---@param comment_id string
---@return integer|nil
function ReviewCommentCollection:find_index(comment_id)
  if nonempty_string(comment_id) then
    for index, record in ipairs(self.records) do
      if record.id == comment_id then
        return index
      end
    end
  end
  return nil
end

---@param comment_id string
---@param text string
---@return ReviewComment|nil, string|nil
function ReviewCommentCollection:edit(comment_id, text)
  local index = self:find_index(comment_id)
  if index == nil then
    return nil, 'Unknown comment ID'
  end
  if not valid_text(text) then
    return nil, 'Expected nonblank comment text'
  end
  self.records[index].text = text
  return vim.deepcopy(self.records[index]), nil
end

---@param comment_id string
---@return ReviewComment|nil, string|nil
function ReviewCommentCollection:resolve(comment_id)
  local index = self:find_index(comment_id)
  if index == nil then
    return nil, 'Unknown comment ID'
  end
  self.records[index].state = 'resolved'
  return vim.deepcopy(self.records[index]), nil
end

---@param comment_id string
---@return ReviewComment|nil, string|nil
function ReviewCommentCollection:reopen(comment_id)
  local index = self:find_index(comment_id)
  if index == nil then
    return nil, 'Unknown comment ID'
  end
  self.records[index].state = 'open'
  return vim.deepcopy(self.records[index]), nil
end

---@param comment_id string
---@return boolean, string|nil
function ReviewCommentCollection:delete(comment_id)
  local index = self:find_index(comment_id)
  if index == nil then
    return false, 'Unknown comment ID'
  end
  table.remove(self.records, index)
  return true, nil
end

---@param file_id string|nil
---@return ReviewComment[]|nil, string|nil
function ReviewCommentCollection:list(file_id)
  if file_id ~= nil and type(file_id) ~= 'string' then
    return nil, 'Expected a string file filter'
  end
  local records = {}
  for _, record in ipairs(self.records) do
    if file_id == nil or record.target.file_id == file_id then
      records[#records + 1] = vim.deepcopy(record)
    end
  end
  return records, nil
end

return M
