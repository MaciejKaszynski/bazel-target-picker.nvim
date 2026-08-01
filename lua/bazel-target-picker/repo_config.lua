local M = {}

--- Per-repo, untracked overrides read from `.git/nvim-bazel.json`. Same
--- `depth`/`target_config` shape as `Config` (see config.lua) — wherever
--- this sets a value, it wins over `setup(opts)`. `universe` has no
--- `Config` equivalent since a sensible default depends on the current
--- file's package, not something set once for the whole repo.
--- @class RepoConfig
--- @field depth? integer How close do the targets have to be.
--- @field universe? string Where to start searching.
--- @field target_config? TargetConfig

--- Resolves the shared .git dir (handles worktrees) for a given path.
--- @param workspace_root string The workspace to look in.
--- @return string?
local function get_git_common_dir(workspace_root)
  local out = vim.fn.systemlist({ "git", "-C", workspace_root, "rev-parse", "--git-common-dir" })
  if vim.v.shell_error ~= 0 or not out[1] then return nil end
  local git_dir = out[1]
  if not git_dir:match("^/") then
    git_dir = vim.fn.fnamemodify(workspace_root .. "/" .. git_dir, ":p")
  end
  return (git_dir:gsub("/$", ""))
end

--- Read the repo config.
--- @detials Some repos need extra args, these are specific to the repo so
---          store then in the `.git` directory.
--- @param workspace_root string The workspace path.
--- @return RepoConfig
function M.read(workspace_root)
  local git_dir = get_git_common_dir(workspace_root)
  if not git_dir then return {} end

  local config_path = git_dir .. "/nvim-bazel.json"
  local f = io.open(config_path, "r")
  if not f then return {} end

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
