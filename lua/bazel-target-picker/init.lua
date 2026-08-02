--- Public API for bazel-target-picker

local config = require("bazel-target-picker.config")
local label = require("bazel-target-picker.label")
local query = require("bazel-target-picker.query")
local ui = require("bazel-target-picker.ui")

local M = {}

--- @type Config The resolved global configuration, set by `setup()`.
M.config = config.config

--- Setup the plugin.
--- @param opts? Config Optional configuration.
function M.setup(opts)
  config.setup(opts)
  M.config = config.config
end

--- One target that made it into a `PickResult`'s `cmd`.
--- @class PickedTarget
--- @field label string The target's label, e.g. "//pkg:a".
--- @field rule string The Bazel rule kind, e.g. "cc_test".

--- Result of a pick, passed to `pick_verbose_from_buffer`'s dispatch. Multiple targets
--- can be selected (Telescope's <Tab>); they're all folded into one `cmd`.
--- Any selected item whose `target_type` doesn't match the first
--- selection's is dropped, since a single bazel invocation can only run
--- one subcommand — e.g. picking a test and a build together keeps only
--- whichever type was picked first.
--- @class PickResult
--- @field cmd string The full bazel command that would be run, e.g. "bazel test //pkg:a //pkg:b --config=x86_64-linux".
--- @field targets PickedTarget[] The targets that made it into `cmd`, e.g. { { label = "//pkg:a", rule = "cc_test" } }.
--- @field target_type TargetType The resolved bazel subcommand shared by every entry in `targets`, e.g. "test".

--- Shared tail: expands targets into picker entries, lets you pick one,
--- builds the resulting bazel command, then calls `on_result(result)`.
--- @param targets BazelTarget[] The candidate targets, e.g. from `query.find`/`query.find_all`.
--- @param target_config TargetConfig The merged config to resolve commands/args with.
--- @param on_result fun(result: PickResult)
local function pick_from_targets(targets, target_config, on_result)
  local items = query.expand(targets, target_config)

  ui.select(items, target_config, function(choices)
    local target_type = choices[1].command

    --- @type PickedTarget[]
    local matching_targets = {}
    for _, choice in ipairs(choices) do
      if choice.command == target_type then
        table.insert(matching_targets, { label = choice.label, rule = choice.kind })
      end
    end

    --- @type string[]
    local labels = {}
    for _, t in ipairs(matching_targets) do
      table.insert(labels, t.label)
    end

    local args = config.extra_args(target_config, target_type)
    local cmd = "bazel " .. target_type .. " " .. table.concat(labels, " ")
    if #args > 0 then
      cmd = cmd .. " " .. table.concat(args, " ")
    end
    on_result({ cmd = cmd, targets = matching_targets, target_type = target_type })
  end)
end

--- Finds every target defined in the package at dir (i.e. by its BUILD/
--- BUILD.bazel file), rather than resolving rdeps for a specific file.
--- @param dir string The package directory (containing the BUILD file).
--- @param workspace_root string The Bazel workspace root.
--- @return BazelTarget[]? targets The targets found, or nil if the
---         underlying `bazel query` failed.
local function find_targets_in_package(dir, workspace_root)
  local package_path = dir:sub(#workspace_root + 2)
  return query.find_all("//" .. package_path .. ":*")
end

--- Resolve → query → pick → build-command pipeline scoped to the current
--- buffer's file. If the buffer is itself a BUILD/BUILD.bazel file, lists
--- every target that file defines instead of resolving rdeps (a BUILD file
--- isn't a source of any target, so rdeps doesn't apply to it). Calls
--- `on_result(result)` once a target is chosen.
--- @param on_result fun(result: PickResult)
--- @return boolean success Whether a target was resolved and handed off to
---         `on_result`; false if resolution, the query, or selection was
---         aborted (most failure paths already show a notification
---         explaining why).
local function pick_from_buffer_impl(on_result)
  local filepath = vim.fn.expand("%:p")
  if filepath == "" then
    vim.notify("No file in current buffer", vim.log.levels.ERROR)
    return false
  end
  local file_dir = vim.fn.fnamemodify(filepath, ":h")

  local workspace_root = label.get_workspace_path(filepath, file_dir)
  if not workspace_root then
    return false
  end

  local cfg = config.get_config()
  local filename = vim.fn.fnamemodify(filepath, ":t")

  --- @type BazelTarget[]?
  local targets
  if filename == "BUILD" or filename == "BUILD.bazel" then
    targets = find_targets_in_package(file_dir, workspace_root)
  else
    local file_label = label.get_current_file_label(filepath, file_dir, workspace_root)
    if not file_label then
      return false
    end

    vim.notify("File label: " .. file_label)

    --- @type string?
    local package_path = file_label:match("^//(.-):")
    if not package_path then
      return false
    end
    local universe = "//" .. package_path .. ":*"
    targets = query.find(file_label, universe, cfg.depth)
  end

  if not targets then
    return false
  end
  if #targets == 0 then
    vim.notify("No targets found", vim.log.levels.WARN)
    return false
  end

  pick_from_targets(targets, cfg.target_config, on_result)
  return true
end

--- Resolve → query → pick → build-command pipeline over every target in the
--- workspace, regardless of the current buffer. Calls `on_result(result)`
--- once a target is chosen.
--- @param on_result fun(result: PickResult)
--- @return boolean success Whether a target was resolved and handed off to
---         `on_result`; false if resolution, the query, or selection was
---         aborted (most failure paths already show a notification
---         explaining why).
local function pick_all_impl(on_result)
  local cwd = vim.fn.getcwd()
  local workspace_root = label.get_workspace_path(cwd, cwd)
  if not workspace_root then
    return false
  end

  local cfg = config.get_config()

  local targets = query.find_all("//...")
  if not targets then
    return false
  end
  if #targets == 0 then
    vim.notify("No targets found", vim.log.levels.WARN)
    return false
  end

  pick_from_targets(targets, cfg.target_config, on_result)
  return true
end

--- Resolves the current buffer's file, finds related targets, lets you pick
--- which ones to build, builds the bazel command, then calls `dispatch(cmd)`
--- with it.
--- Bind this directly to a keymap with your own inline `dispatch` for one-off
--- behavior (copy to clipboard, log it, etc.).
--- @param dispatch fun(cmd: string)
--- @return boolean success Whether a target was picked and `dispatch` was
---         called; false otherwise.
function M.pick_from_buffer(dispatch)
  return pick_from_buffer_impl(function(result)
    dispatch(result.cmd)
  end)
end

--- Same as `pick_from_buffer`, but `dispatch` receives the full
--- `PickResult` (cmd, targets, target_type) instead of just the command
--- string.
--- @param dispatch fun(result: PickResult)
--- @return boolean success Whether a target was picked and `dispatch` was
---         called; false if the pick was aborted before a selection was made.
function M.pick_verbose_from_buffer(dispatch)
  return pick_from_buffer_impl(dispatch)
end

--- Finds every Bazel rule target in the current workspace (`//...`),
--- regardless of the current buffer, lets you pick one, builds the bazel
--- command, then calls `dispatch(cmd)` with it.
--- @param dispatch fun(cmd: string)
--- @return boolean success Whether a target was picked and `dispatch` was
---         called; false if the pick was aborted before a selection was made.
function M.pick_all(dispatch)
  return pick_all_impl(function(result)
    dispatch(result.cmd)
  end)
end

return M
