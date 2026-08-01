--- Reads per-repo config overrides from `.git/bazel-target-picker.json`.

local M = {}

--- Resolves the shared .git dir (handles worktrees) for a given path.
--- @param workspace_root string The workspace to look in.
--- @return string? git_common_dir The resolved common git dir, or nil if
---         `workspace_root` isn't inside a git repo.
local function get_git_common_dir(workspace_root)
  local out = vim.fn.systemlist({ "git", "-C", workspace_root, "rev-parse", "--git-common-dir" })
  if vim.v.shell_error ~= 0 or not out[1] then
    return nil
  end
  local git_dir = out[1]
  if not git_dir:match("^/") then
    git_dir = vim.fn.fnamemodify(workspace_root .. "/" .. git_dir, ":p")
  end
  return (git_dir:gsub("/$", ""))
end

--- Read the repo config (`.git/bazel-target-picker.json`), untracked and
--- specific to this checkout. Same shape as `Config` (see init.lua) —
--- wherever this sets a value, it wins over `setup(opts)`.
--- @param workspace_root string The workspace path.
--- @return Config config The decoded repo config, or `{}` if there's no git
---         dir, no config file, or it fails to parse.
function M.read(workspace_root)
  local git_dir = get_git_common_dir(workspace_root)
  if not git_dir then
    return {}
  end

  local config_path = git_dir .. "/bazel-target-picker.json"
  local f = io.open(config_path, "r")
  if not f then
    return {}
  end

  local content = f:read("*a")
  f:close()

  --- @type boolean, any
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    vim.notify("Failed to parse " .. config_path, vim.log.levels.WARN)
    return {}
  end
  return decoded
end

return M
