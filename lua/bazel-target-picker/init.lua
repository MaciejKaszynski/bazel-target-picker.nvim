local config = require("bazel-target-picker.config")
local label = require("bazel-target-picker.label")
local repo_config = require("bazel-target-picker.repo_config")
local query = require("bazel-target-picker.query")
local ui = require("bazel-target-picker.ui")

local M = {}

--- The current config. Prefer `M.setup` to change it.
M.config = config.config

--- Configures the picker. Does not set any keymaps — call `require(...).pick`
--- from your own `vim.keymap.set` to bind it.
--- @param opts? Config
function M.setup(opts)
  config.setup(opts)
  M.config = config.config
end

--- Finds Bazel targets related to the current buffer's file and lets you
--- pick one to build or test.
function M.pick()
  local file_label, workspace_root = label.get_current_file_label()
  if not file_label then return end
  if not workspace_root then return end
  vim.notify("File label: " .. file_label)

  local repo = repo_config.read(workspace_root)
  --- @type string?
  local package_path = file_label:match("^//(.-):")
  if not package_path then return end
  local universe = repo.universe or ("//" .. package_path .. ":*")
  local depth = repo.depth or config.config.depth or 4
  -- Repo target_config wins wherever it sets a value; same merge M.setup uses.
  local target_config = vim.tbl_deep_extend("force", config.config.target_config or {}, repo.target_config or {})

  local targets = query.find(file_label, universe, depth)
  if not targets then return end
  if #targets == 0 then
    vim.notify("No targets found for " .. file_label, vim.log.levels.WARN)
    return
  end

  local items = query.expand(targets, target_config)

  ui.select(items, function(choice)
    local args = config.extra_args(target_config, choice.command)
    local cmd = "bazel " .. choice.command .. " " .. choice.label
    if #args > 0 then
      cmd = cmd .. " " .. table.concat(args, " ")
    end
    config.config.run(cmd)
  end)
end

return M
