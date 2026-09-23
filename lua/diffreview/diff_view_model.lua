---@class ChangedFileViewModel
---@field id string
---@field display_path string
---@field added_lines integer
---@field removed_lines integer
---@field viewed boolean

local M = {}

---@class DiffPathTextContent
---@field kind 'text'
---@field source 'path'
---@field absolute_path string

---@class DiffSnapshotTextContent
---@field kind 'text'
---@field source 'snapshot'
---@field lines string[]
---@field endofline boolean
---@field fileformat 'unix'|'dos'|'mac'
---@field filetype_path string

---@class DiffBinaryContent
---@field kind 'binary'
---@field oid string|nil
---@field size integer|nil

---@alias DiffFileContent DiffPathTextContent|DiffSnapshotTextContent|DiffBinaryContent

---@class DiffFileVersion
---@field display_path string
---@field mode DiffFileMode
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

---@class RenamedDiff
---@field operation 'renamed'
---@field old DiffFileVersion
---@field current DiffFileVersion
---@field content_changed boolean

---@class CopiedDiff
---@field operation 'copied'
---@field old DiffFileVersion
---@field current DiffFileVersion
---@field content_changed boolean

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

return M
