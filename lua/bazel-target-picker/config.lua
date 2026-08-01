local M = {}

--- Default `run`: sends cmd to a toggleterm floating terminal.
--- @param cmd string
local function default_run(cmd)
  require("toggleterm").exec(cmd, nil, nil, nil, "float")
end

--- The bazel subcommands the picker knows how to run.
--- @alias TargetType "build"|"test"|"run"|"coverage"

--- Maps a bazel subcommand to the icon shown for it in the picker.
--- Commands with no entry use `default_icon`.
--- @alias Icons table<TargetType, string>

--- @type Icons
local DEFAULT_ICONS = {
  test = "🧪",
  coverage = "📊",
  run = "🏃",
  build = "⚙️",
}

--- Priority when a kind matches more than one command's list, e.g. a test
--- kind is in both "test" and "coverage"; a binary kind is in both "run"
--- and "build". Checked in this order so command resolution is deterministic.
--- @type TargetType[]
M.COMMAND_PRIORITY = { "test", "run", "coverage", "build" }

--- Per-command config. `additional_bazel_rules` extends (never replaces)
--- the picker's built-in rule kinds for that command. `extra_args` is
--- appended to the "default" bucket's `extra_args` (see TargetConfig).
--- @class TargetCommandConfig
--- @field additional_bazel_rules? string[] Extra rule kinds that should also resolve to this command.
--- @field extra_args? string[] Extra bazel flags to pass when running this command.

--- "default" applies to every command; a specific command's `extra_args`
--- is appended on top of (not instead of) "default"'s. `additional_bazel_rules`
--- is only meaningful under a real command, not "default", since a rule
--- kind has to resolve to exactly one command.
--- @alias TargetConfigKey TargetType|"default"

--- @alias TargetConfig table<TargetConfigKey, TargetCommandConfig>

--- Shared by both `M.setup(opts)` and the per-repo `.git/nvim-bazel.json`
--- (see repo_config.lua) — the repo file wins wherever it sets a value.
--- @class Config
--- @field depth? integer Default rdeps search depth. Defaults to 4.
--- @field run? fun(cmd: string) How to execute the bazel command. Defaults to a toggleterm floating terminal.
--- @field icons? Icons Maps a bazel subcommand to the icon shown for it.
--- @field default_icon? string Icon used for commands not listed in `icons`.
--- @field target_config? TargetConfig
M.config = {
  depth = 4,
  run = default_run,
  icons = DEFAULT_ICONS,
  default_icon = "❔",
  target_config = {},
}

--- Merges opts into the current config.
--- @param opts? Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

--- Computes the effective extra bazel args for a command: the "default"
--- bucket's args, followed by the command-specific bucket's args.
--- @param target_config TargetConfig
--- @param command TargetType
--- @return string[]
function M.extra_args(target_config, command)
  local args = {}
  vim.list_extend(args, (target_config.default or {}).extra_args or {})
  vim.list_extend(args, (target_config[command] or {}).extra_args or {})
  return args
end

return M
