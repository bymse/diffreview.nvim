local M = {}

---@alias GitFileMode '000000'|'100644'|'100755'|'120000'|'160000'
---@alias DiffFileMode '100644'|'100755'|'120000'|'160000'
---@alias DiffFileType 'regular'|'symlink'|'submodule'

local valid_modes = {
  ['000000'] = true,
  ['100644'] = true,
  ['100755'] = true,
  ['120000'] = true,
  ['160000'] = true,
}

---@param mode any
---@return boolean
function M.is_valid_mode(mode)
  return valid_modes[mode] == true
end

---@param mode any
---@return boolean
function M.is_present_mode(mode)
  return mode == '100644' or mode == '100755' or mode == '120000' or mode == '160000'
end

---@param mode DiffFileMode
---@return DiffFileType
function M.classify_file_type(mode)
  if mode == '100644' or mode == '100755' then
    return 'regular'
  end

  if mode == '120000' then
    return 'symlink'
  end

  return 'submodule'
end

---@param mode DiffFileMode
---@return string
function M.display_label(mode)
  if mode == '100644' then
    return 'file'
  end

  if mode == '100755' then
    return 'executable file'
  end

  if mode == '120000' then
    return 'symbolic link'
  end

  return 'submodule'
end

return M
