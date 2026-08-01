local repo_config = require("bazel-target-picker.config.repo_config")
local label = require("bazel-target-picker.label")

local M = {}

--- The configuration for the plugin can be taken from multiple sources, these
--- settings are merged and the precedence is as follows:
--- 1. From the `.git/bazel-target-picker.json` file. - Repo specific settings.
--- 2. Given to the `setup(opts)` method. - "Global" settings.

--- The bazel subcommands the picker knows how to run.
--- @alias TargetType "build"|"test"|"run"|"coverage"

--- Per command config. `icon` under a specific command is shown for that
--- command's picker entries; `icon` under "default" is the fallback used
--- when a command has no icon of its own.
--- @class TargetCommandConfig
--- @field additional_bazel_rules? string[] Extra bazel rules that should also resolve to this command.
---                                         Note this is not valid for the `default` field.
--- @field extra_args? string[] Extra bazel arguments to pass when running this command.
--- @field icon? string Icon shown for this command in the picker.

--- Key for the `target_config` field. An additional "default" field is
--- added that is not a TargetType but allows the user to add default
--- values for some fields.
--- @alias TargetConfigKey TargetType|"default"

--- Configuration fields for each `TargetType` & default config.
--- @alias TargetConfig table<TargetConfigKey, TargetCommandConfig>

--- The default config used when no user configuration is given.
--- @type TargetConfig
local DEFAULT_TARGET_CONFIG = {
  test = { icon = "🧪" },
  coverage = { icon = "📊" },
  run = { icon = "▶️" },
  build = { icon = "⚙️" },
  default = { icon = "❔" },
}

--- All configuraitons, shared by both `M.setup(opts)` and the per-repo config.
--- @class Config
--- @field depth? integer Default rdeps search depth. Defaults to 4.
--- @field target_config? TargetConfig
M.config = {
  depth = 4,
  target_config = DEFAULT_TARGET_CONFIG,
}

--- Repo config, loaded once in `M.setup` (based on cwd) instead of being
--- re-read from disk/git on every `pick` call.
--- @type Config
local cached_repo = {}

--- Merges opts into the current config, and loads the repo config
--- (`.git/bazel-target-picker.json`) for the cwd's workspace, if any. Silent
--- if cwd isn't inside a Bazel workspace at all — plenty of Neovim sessions aren't.
--- @param opts? Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  local cwd = vim.fn.getcwd()
  local workspace_root = label.get_workspace_path(cwd, cwd, true)
  if workspace_root then
    cached_repo = repo_config.read(workspace_root)
  end
end

--- The fully merged config.
--- The different configs are merged with the following precedence:
--- 1. Repo config.
--- 2. `setup()` config.
--- 3. Default config.
--- @class EffectiveConfig
--- @field depth integer The depth for how releted the targets shall be.
--- @field target_config TargetConfig The config for each target type.

--- @return EffectiveConfig config The resolved config for this pick: repo
---         config overriding `setup()` config overriding defaults.
function M.get_config()
  return {
    depth = cached_repo.depth or M.config.depth or 4,
    target_config = vim.tbl_deep_extend("force", M.config.target_config or {}, cached_repo.target_config or {}),
  }
end

--- Computes the effective extra bazel args for a command: the "default"
--- bucket's args, followed by the command-specific bucket's args.
--- @param target_config TargetConfig The merged `target_config` for this pick.
--- @param command TargetType The resolved subcommand to compute args for.
--- @return string[] args The "default" bucket's args followed by `command`'s own.
function M.extra_args(target_config, command)
  --- @type string[]
  local args = {}
  vim.list_extend(args, (target_config.default or {}).extra_args or {})
  vim.list_extend(args, (target_config[command] or {}).extra_args or {})
  return args
end

--- The icon for a command: its own `icon`, falling back to "default"'s,
--- falling back to "❔" if neither is set.
--- @param target_config TargetConfig The merged `target_config` for this pick.
--- @param command TargetType The resolved subcommand to look up the icon for.
--- @return string icon The icon to show for `command` in the picker.
function M.icon(target_config, command)
  return (target_config[command] or {}).icon or (target_config.default or {}).icon or "❔"
end

return M
