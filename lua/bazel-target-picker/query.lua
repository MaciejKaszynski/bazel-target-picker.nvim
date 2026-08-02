--- Finds Bazel targets related to a file and expands them into picker entries.

local M = {}

--- Commands checked against a kind's rule lists in `resolve_commands`,
--- excluding "build" which always applies unconditionally. Order has no
--- meaning beyond iteration — the picker is meant to be typed through, not
--- read top-to-bottom.
--- @type TargetType[]
local COMMANDS = { "test", "run", "coverage" }

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

--- Rule kinds for each command, except "build" — every kind is buildable
--- (see resolve_commands), so it has no kind list of its own to match against.
--- @type table<TargetType, string[]>
local DEFAULT_KINDS = {
  test = TEST_KINDS,
  coverage = vim.list_extend({}, TEST_KINDS),
  run = BINARY_KINDS,
}

--- A Bazel target found by `M.find`.
--- @class BazelTarget
--- @field kind string The rule kind, e.g. "cc_library" or "cc_test".
--- @field label string The target's label, e.g. "//pkg:name".

--- One selectable entry in the picker: a target paired with one of the
--- subcommands that applies to it, e.g. a cc_test shows up as "test",
--- "coverage", and "build" — every kind is also buildable, known or not.
--- @class PickerItem : BazelTarget
--- @field command TargetType The subcommand this entry resolves to.

--- Resolves every bazel subcommand that applies to a rule kind. "build"
--- always applies, in addition to whatever else matches — virtually every
--- Bazel rule (including unrecognized/custom ones) is buildable.
-- TODO handle multiple selected pairs
--- @param kind string The rule kind, e.g. "cc_test".
--- @param target_config TargetConfig The merged config, used to look up
---        `additional_bazel_rules` for each command.
--- @return TargetType[] commands Every subcommand `kind` resolves to; always
---         includes "build".
local function resolve_commands(kind, target_config)
  --- @type TargetType[]
  local commands = {}

  for _, command in ipairs(COMMANDS) do
    local kinds = DEFAULT_KINDS[command] or {}
    local extra_kinds = (target_config[command] or {}).additional_bazel_rules or {}
    if vim.tbl_contains(kinds, kind) or vim.tbl_contains(extra_kinds, kind) then
      table.insert(commands, command)
    end
  end
  table.insert(commands, "build")
  return commands
end

--- Runs a `bazel query` expression and parses its `--output=label_kind`
--- lines into BazelTargets.
--- @param query_expr string A full `bazel query` expression.
--- @return BazelTarget[]? targets The targets found, or nil if the
---         underlying `bazel query` failed.
local function run_query(query_expr)
  local out = vim.fn.systemlist({ "bazel", "query", "--output=label_kind", query_expr })
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

--- Finds targets within `depth` dependency hops of file_label, within universe.
--- @param file_label string The label of the file to query for.
--- @param universe string The root where to search from.
--- @param depth number How far away the targets can be.
--- @return BazelTarget[]? targets The targets found, or nil if the
---         underlying `bazel query` failed.
function M.find(file_label, universe, depth)
  return run_query(string.format("kind(rule, rdeps(%s, %s, %d))", universe, file_label, depth))
end

--- Finds every rule target within universe, with no rdeps traversal —
--- unlike `M.find`, this isn't scoped to any particular file.
--- @param universe string The scope to search, e.g. "//..." for everything.
--- @return BazelTarget[]? targets The targets found, or nil if the
---         underlying `bazel query` failed.
function M.find_all(universe)
  return run_query(string.format("kind(rule, %s)", universe))
end

--- Expands each target into one PickerItem per applicable command.
--- @param targets BazelTarget[] The targets to expand, e.g. from `M.find`.
--- @param target_config TargetConfig The merged config, used to resolve
---        each target's applicable commands.
--- @return PickerItem[] items One entry per target per applicable command.
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
