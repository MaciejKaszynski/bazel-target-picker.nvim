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

--- Shared impl for picking from buffer.
--- get label -> bazel query -> pick -> build command.
--- Calls `on_result(result)` once a target is chosen.
--- @param dispatch fun(result: PickResult)
--- @return boolean success Whether a target was resolved and handed off to
---         `on_result`; false if resolution, the query, or selection was
---         aborted (most failure paths already show a notification
---         explaining why).
local function pick_from_buffer_impl(dispatch)
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
  local cfg = config.get_config()
  local universe = "//" .. package_path .. ":*"

  local targets = query.find(file_label, universe, cfg.depth)
  if not targets then
    return false
  end
  if #targets == 0 then
    vim.notify("No targets found for " .. file_label, vim.log.levels.WARN)
    return false
  end

  local items = query.expand(targets, cfg.target_config)

  ui.select(items, cfg.target_config, function(choices)
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

    local args = config.extra_args(cfg.target_config, target_type)
    local cmd = "bazel " .. target_type .. " " .. table.concat(labels, " ")
    if #args > 0 then
      cmd = cmd .. " " .. table.concat(args, " ")
    end
    dispatch({ cmd = cmd, targets = matching_targets, target_type = target_type })
  end)
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

return M
