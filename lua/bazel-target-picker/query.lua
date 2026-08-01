local config = require("bazel-target-picker.config")

local M = {}

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

--- Built-in rule kinds for each command. `target_config[command].additional_bazel_rules`
--- extends these; nothing in user config ever replaces them.
--- @type table<TargetType, string[]>
local DEFAULT_KINDS = {
  test = TEST_KINDS,
  coverage = vim.list_extend({}, TEST_KINDS),
  run = BINARY_KINDS,
  build = vim.list_extend(vim.list_extend(vim.list_extend({}, TEST_KINDS), BINARY_KINDS), LIBRARY_KINDS),
}

--- A Bazel target found by `M.find`.
--- @class BazelTarget
--- @field kind string The rule kind, e.g. "cc_library" or "cc_test".
--- @field label string The target's label, e.g. "//pkg:name".

--- One selectable entry in the picker: a target paired with one of the
--- subcommands that applies to it, e.g. a cc_test shows up once as "test"
--- and once as "coverage".
--- @class PickerItem : BazelTarget
--- @field command TargetType

--- Resolves every bazel subcommand that applies to a rule kind, in
--- COMMAND_PRIORITY order (falls back to just "build" if none match).
--- @param kind string
--- @param target_config TargetConfig
--- @return TargetType[]
local function resolve_commands(kind, target_config)
  --- @type TargetType[]
  local commands = {}
  for _, command in ipairs(config.COMMAND_PRIORITY) do
    local kinds = DEFAULT_KINDS[command] or {}
    local extra_kinds = (target_config[command] or {}).additional_bazel_rules or {}
    if vim.tbl_contains(kinds, kind) or vim.tbl_contains(extra_kinds, kind) then
      table.insert(commands, command)
    end
  end
  if #commands == 0 then
    table.insert(commands, "build")
  end
  return commands
end

--- Finds targets within `depth` dependency hops of file_label, within universe.
--- @param file_label string The label of the file to query for.
--- @param universe string The root where to search from.
--- @param depth number How far away the targets can be.
--- @return BazelTarget[]?
function M.find(file_label, universe, depth)
  local query = string.format("kind(rule, rdeps(%s, %s, %d))", universe, file_label, depth)
  local out = vim.fn.systemlist({ "bazel", "query", "--output=label_kind", query })
  if vim.v.shell_error ~= 0 then
    vim.notify("bazel query failed:\n" .. table.concat(out, "\n"), vim.log.levels.ERROR)
    return nil
  end

  --- @type BazelTarget[]
  local targets = {}
  for _, line in ipairs(out) do
    --- @type string?, string?
    local kind, label = line:match("^(%S+) rule (%S+)$")
    if kind and label then
      table.insert(targets, { kind = kind, label = label })
    end
  end
  return targets
end

--- Expands each target into one PickerItem per applicable command, in
--- COMMAND_PRIORITY order.
--- @param targets BazelTarget[]
--- @param target_config TargetConfig
--- @return PickerItem[]
function M.expand(targets, target_config)
  --- @type PickerItem[]
  local items = {}
  for _, target in ipairs(targets) do
    for _, command in ipairs(resolve_commands(target.kind, target_config)) do
      table.insert(items, { kind = target.kind, label = target.label, command = command })
    end
  end
  return items
end

return M
