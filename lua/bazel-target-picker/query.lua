local config = require("bazel-target-picker.config")

local M = {}

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
--- @return TargetType[]
local function resolve_commands(kind)
  --- @type TargetType[]
  local commands = {}
  for _, command in ipairs(config.COMMAND_PRIORITY) do
    local kinds = config.config.target_types[command]
    if kinds and vim.tbl_contains(kinds, kind) then
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
--- @return PickerItem[]
function M.expand(targets)
  --- @type PickerItem[]
  local items = {}
  for _, target in ipairs(targets) do
    for _, command in ipairs(resolve_commands(target.kind)) do
      table.insert(items, { kind = target.kind, label = target.label, command = command })
    end
  end
  return items
end

return M
