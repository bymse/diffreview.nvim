---@class ChangedFileViewModel
---@field id string
---@field display_path string
---@field added_lines integer
---@field removed_lines integer
---@field viewed boolean

---@class DiffTextContent
---@field kind 'text'
---@field path string
---@field content string|nil

---@class DiffBinaryContent
---@field kind 'binary'
---@field oid string|nil
---@field size integer|nil

---@alias DiffFileContent DiffTextContent|DiffBinaryContent

---@class DiffFileVersion
---@field path string
---@field mode string
---@field content DiffFileContent

---@class AddedDiff
---@field operation 'added'|'untracked'
---@field current DiffFileVersion

---@class DeletedDiff
---@field operation 'deleted'
---@field old DiffFileVersion

---@class ModifiedDiff
---@field operation 'modified'
---@field old DiffFileVersion
---@field current DiffFileVersion
---@field content_changed boolean
---@field mode_changed boolean

---@class RenamedDiff
---@field operation 'renamed'
---@field old DiffFileVersion
---@field current DiffFileVersion
---@field content_changed boolean
---@field mode_changed boolean

---@class CopiedDiff
---@field operation 'copied'
---@field old DiffFileVersion
---@field current DiffFileVersion
---@field content_changed boolean
---@field mode_changed boolean

---@class TypeChangedDiff
---@field operation 'type_changed'
---@field old DiffFileVersion
---@field current DiffFileVersion

---@class UnmergedDiff
---@field operation 'unmerged'
---@field current DiffFileVersion

---@alias DiffOperation 'added'|'untracked'|'deleted'|'modified'|'renamed'|'copied'|'type_changed'|'unmerged'

---@class ErrorDiff
---@field operation 'error'
---@field attempted_operation DiffOperation
---@field path string
---@field message string

---@alias DiffViewModel AddedDiff|DeletedDiff|ModifiedDiff|RenamedDiff|CopiedDiff|TypeChangedDiff|UnmergedDiff|ErrorDiff
