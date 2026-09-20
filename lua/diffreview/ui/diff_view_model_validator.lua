local file_mode = require('diffreview.file_mode')

local M = {}

---@param message string
local function validation_error(message)
  error('Invalid diff view model: ' .. message, 3)
end

---@param content DiffFileContent
---@param version_name string
---@param operation DiffOperation
---@param is_current boolean
---@param mode DiffFileMode
local function validate_content(content, version_name, operation, is_current, mode)
  if content.kind == 'binary' then
    if content.oid ~= nil and (content.oid == '' or not content.oid:match('^[%da-fA-F]+$')) then
      validation_error(version_name .. ' binary oid must be nonempty hexadecimal text')
    end
    if content.size ~= nil and content.size < 0 then
      validation_error(version_name .. ' binary size must be nonnegative')
    end
    return
  end

  if content.source == 'path' then
    if not is_current or operation == 'deleted' or file_mode.classify_file_type(mode) ~= 'regular' then
      validation_error(version_name .. ' path text is only allowed for current regular versions')
    end
    if
      operation ~= 'added'
      and operation ~= 'untracked'
      and operation ~= 'modified'
      and operation ~= 'renamed'
      and operation ~= 'copied'
      and operation ~= 'unmerged'
    then
      validation_error(version_name .. ' path text has unsupported operation provenance')
    end
    if content.absolute_path == '' or content.absolute_path:sub(1, 1) ~= '/' then
      validation_error(version_name .. ' path text requires a nonempty absolute_path')
    end
    return
  end

  if content.filetype_path == '' then
    validation_error(version_name .. ' snapshot filetype_path must be nonempty')
  end
end

---@param version DiffFileVersion
---@param version_name string
---@param operation DiffOperation
---@param is_current boolean
local function validate_version(version, version_name, operation, is_current)
  if version.display_path == '' then
    validation_error(version_name .. ' display_path must be nonempty')
  end
  if not file_mode.is_present_mode(version.mode) then
    validation_error(version_name .. ' mode must be a present diff mode')
  end
  validate_content(version.content, version_name, operation, is_current, version.mode)
end

---@param diff DiffViewModel
---@return nil
function M.validate(diff)
  local operation = diff.operation
  if operation == 'error' then
    if diff.path == '' or diff.message == '' then
      validation_error('error path and message must be nonempty')
    end
    return
  end
  ---@cast operation DiffOperation

  if operation == 'added' or operation == 'untracked' or operation == 'unmerged' then
    validate_version(diff.current, 'current', operation, true)
    if operation == 'unmerged' and (diff.current.content.kind ~= 'text' or diff.current.content.source ~= 'path') then
      validation_error('unmerged current version requires path-backed regular text')
    end
    return
  end

  if operation == 'deleted' then
    validate_version(diff.old, 'old', operation, false)
    return
  end

  validate_version(diff.old, 'old', operation, false)
  validate_version(diff.current, 'current', operation, true)

  if operation == 'modified' or operation == 'renamed' or operation == 'copied' then
    if (operation == 'renamed' or operation == 'copied') and diff.old.display_path == diff.current.display_path then
      validation_error(operation .. ' old and current display paths must differ')
    end
    if operation == 'modified' and not diff.content_changed and diff.old.mode == diff.current.mode then
      validation_error('modified diffs cannot have unchanged content and mode')
    end
    return
  end

  if file_mode.classify_file_type(diff.old.mode) == file_mode.classify_file_type(diff.current.mode) then
    validation_error('type_changed versions must have different file types')
  end
end

return M
