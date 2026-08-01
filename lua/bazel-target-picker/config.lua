local M = {}

--- Default `run`: sends cmd to a toggleterm floating terminal.
--- @param cmd string
local function default_run(cmd)
  require("toggleterm").exec(cmd, nil, nil, nil, "float")
end

--- The bazel subcommands the picker knows how to run.
--- @alias TargetType "build"|"test"|"run"|"coverage"

--- Maps a bazel subcommand to the rule kinds that should run under it.
--- A kind not listed anywhere falls back to "build".
--- @alias TargetTypes table<TargetType, string[]>

local TEST_KINDS = {
  "cc_test",
  "py_test",
  "rust_test",
  "java_test",
  "go_test",
  "sh_test",
}
local BINARY_KINDS = {
  "cc_binary",
  "py_binary",
  "rust_binary",
  "java_binary",
  "go_binary",
  "sh_binary",
}
local LIBRARY_KINDS = {
  "cc_library",
  "cc_shared_library",
  "py_library",
  "rust_library",
  "java_library",
  "go_library",
  "sh_library",
}

--- @type TargetTypes
local DEFAULT_TARGET_TYPES = {
  test = TEST_KINDS,
  coverage = vim.list_extend({}, TEST_KINDS),
  run = BINARY_KINDS,
  build = vim.list_extend(vim.list_extend(vim.list_extend({}, TEST_KINDS), BINARY_KINDS), LIBRARY_KINDS),
}

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

--- @class Config
--- @field depth? integer Default rdeps search depth. Defaults to 4.
--- @field run? fun(cmd: string) How to execute the bazel command. Defaults to a toggleterm floating terminal.
--- @field target_types? TargetTypes Maps a bazel subcommand to the rule kinds that use it.
--- @field icons? Icons Maps a bazel subcommand to the icon shown for it.
--- @field default_icon? string Icon used for commands not listed in `icons`.
M.config = {
  depth = 4,
  run = default_run,
  target_types = DEFAULT_TARGET_TYPES,
  icons = DEFAULT_ICONS,
  default_icon = "❔",
}

--- Merges opts into the current config.
--- @param opts? Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
