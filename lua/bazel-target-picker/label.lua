--- Resolves the Bazel workspace root and target label for a given file path.

local M = {}

--- Searches for the given file names going down, desceding the file tree from
--- the given start path.
--- @param start_dir string The path to start the search at, must be a dir.
--- @param filenames string[] List of file names to look for.
--- @return string? dir The nearest ancestor directory (including `start_dir`)
---         containing one of `filenames`, or nil if none was found before
---         reaching the filesystem root.
local function find_upwards(start_dir, filenames)
  local dir = start_dir
  while true do
    for _, name in ipairs(filenames) do
      if vim.fn.filereadable(dir .. "/" .. name) == 1 then
        return dir
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      return nil
    end
    dir = parent
  end
end

--- Cached workspace root, reused as long as the current file is still
--- inside it, so we don't re-walk the filesystem on every pick.
--- @type string?
local cached_workspace_root = nil

--- Returns the workspace path.
--- @param filepath string The file path to start looking from.
--- @param file_dir string The directory of filepath.
--- @param silent? boolean If true, don't notify when not inside a Bazel workspace.
--- @return string? workspace_root The directory containing `MODULE.bazel`,
---         `WORKSPACE`, or `WORKSPACE.bazel`, or nil if `filepath` isn't
---         inside a Bazel workspace.
function M.get_workspace_path(filepath, file_dir, silent)
  if cached_workspace_root then
    local inside_cached_root = file_dir == cached_workspace_root
      or file_dir:sub(1, #cached_workspace_root + 1) == cached_workspace_root .. "/"
    if inside_cached_root then
      return cached_workspace_root
    end
  end

  -- find root
  local workspace_root = find_upwards(file_dir, { "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel" })
  if not workspace_root then
    if not silent then
      vim.notify("Not inside a Bazel workspace: " .. filepath, vim.log.levels.ERROR)
    end
    return nil
  end

  cached_workspace_root = workspace_root
  return workspace_root
end

--- Returns the Bazel label for the given file, using the `//a/b/c` format to
--- the nearest BUILD file, then `:` and the rest of the path.
--- @param filepath string The absolute path of the file to label.
--- @param file_dir string The directory of `filepath`.
--- @param workspace_root string The Bazel workspace root, from `get_workspace_path`.
--- @return string? label The bazel label of the given file.
function M.get_current_file_label(filepath, file_dir, workspace_root)
  -- find nearest BUILD
  local package_dir = find_upwards(file_dir, { "BUILD", "BUILD.bazel" })
  if not package_dir then
    vim.notify("No BUILD file found above " .. filepath, vim.log.levels.ERROR)
    return nil
  end

  local package_path = package_dir:sub(#workspace_root + 2)
  local file_rel = filepath:sub(#package_dir + 2)
  return string.format("//%s:%s", package_path, file_rel)
end

return M
