local config = require("bazel-target-picker.config")

local M = {}

--- Right-pads s with spaces to reach the given display width. Uses display
--- width rather than byte length so multi-byte icons (emoji) still align.
--- @param s string
--- @param width integer
--- @return string
local function pad(s, width)
  return s .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(s)))
end

--- Shows a `vim.ui.select` picker over items and calls on_choice with the
--- selected one. Does nothing if the picker is cancelled.
--- @param items PickerItem[]
--- @param on_choice fun(choice: PickerItem)
function M.select(items, on_choice)
  local icon_width, command_width = 0, 0
  for _, t in ipairs(items) do
    local icon = config.config.icons[t.command] or config.config.default_icon
    icon_width = math.max(icon_width, vim.fn.strdisplaywidth(icon))
    command_width = math.max(command_width, #t.command)
  end

  vim.ui.select(items, {
    prompt = "Bazel target:",
    --- @param t PickerItem
    --- @return string
    format_item = function(t)
      local short_name = t.label:match(":([^:]+)$") or t.label
      local icon = config.config.icons[t.command] or config.config.default_icon
      return string.format("%s %s %s", pad(icon, icon_width), pad(t.command, command_width), short_name)
    end,
  }, function(choice)
    if choice then on_choice(choice) end
  end)
end

return M
