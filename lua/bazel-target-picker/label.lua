local M = {}

--- Searches for the given file names going down desceding the file tree from
--- the given start path.
--- @nodiscard
--- @param start_dir string The path to start the search at, must be a dir.
--- @param filenames string[] List of file names to look for.
--- @return string?
local function find_upwards(start_dir, filenames)
  local dir = start_dir
  while true do
    for _, name in ipairs(filenames) do
      if vim.fn.filereadable(dir .. "/" .. name) == 1 then
        return dir
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then return nil end
    dir = parent
  end
end

--- Returns the Bazel label for the current buffer's file
--- @details This is using the `//a/b/c` format to the nearest BUILD file,
---          then `:` and the rest of the path.
--- @return string?, string?
function M.get_current_file_label()
  local filepath = vim.fn.expand("%:p")
  if filepath == "" then
    vim.notify("No file in current buffer", vim.log.levels.ERROR)
    return nil
  end

  -- find root
  local file_dir = vim.fn.fnamemodify(filepath, ":h")
  local workspace_root = find_upwards(file_dir, { "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel" })
  if not workspace_root then
    vim.notify("Not inside a Bazel workspace: " .. filepath, vim.log.levels.ERROR)
    return nil
  end

  -- find nearest BUILD
  local package_dir = find_upwards(file_dir, { "BUILD", "BUILD.bazel" })
  if not package_dir then
    vim.notify("No BUILD file found above " .. filepath, vim.log.levels.ERROR)
    return nil
  end

  local package_path = package_dir:sub(#workspace_root + 2)
  local file_rel = filepath:sub(#package_dir + 2)
  return string.format("//%s:%s", package_path, file_rel), workspace_root
end

return M
