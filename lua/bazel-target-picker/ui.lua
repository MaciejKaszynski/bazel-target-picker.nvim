--- Shows the picker (Telescope if installed, otherwise `vim.ui.select`) and
--- formats its entries.

local config = require("bazel-target-picker.config")

local M = {}

--- Right-pads s with spaces to reach the given display width. Uses display
--- width rather than byte length so multi-byte icons (emoji) still align.
--- @param s string The string to pad.
--- @param width integer The display width to pad `s` up to.
--- @return string padded `s` followed by enough spaces to reach `width`.
local function pad(s, width)
  return s .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(s)))
end

--- Builds a display-formatting function for items, with columns aligned
--- across the whole list.
--- @param items PickerItem[] The full set of entries to be displayed, scanned
---        upfront to compute column widths.
--- @param target_config TargetConfig Used to look up each item's icon.
--- @return fun(t: PickerItem): string format_item Formats a single item as
---         "<icon> <command> <short target name>", padded to align columns.
local function make_formatter(items, target_config)
  local icon_width, command_width = 0, 0
  for _, t in ipairs(items) do
    local icon = config.icon(target_config, t.command)
    icon_width = math.max(icon_width, vim.fn.strdisplaywidth(icon))
    command_width = math.max(command_width, #t.command)
  end

  return function(t)
    local short_name = t.label:match(":([^:]+)$") or t.label
    local icon = config.icon(target_config, t.command)
    return string.format("%s %s %s", pad(icon, icon_width), pad(t.command, command_width), short_name)
  end
end

--- Telescope supports real multi-select (<Tab> to toggle, <CR> to confirm).
--- If nothing was tab-selected, falls back to the entry under the cursor.
--- @param items PickerItem[] The entries to show in the picker.
--- @param format_item fun(t: PickerItem): string Formats an item for display.
--- @param on_choice fun(choices: PickerItem[]) Called with every selected
---        item once the picker is confirmed. Never called if cancelled.
local function select_telescope(items, format_item, on_choice)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = "Bazel target",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return { value = item, display = format_item(item), ordinal = item.command .. " " .. item.label }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local multi = picker:get_multi_selection()
          actions.close(prompt_bufnr)

          --- @type PickerItem[]
          local chosen = {}
          if #multi > 0 then
            for _, entry in ipairs(multi) do
              table.insert(chosen, entry.value)
            end
          else
            local entry = action_state.get_selected_entry()
            if entry then
              table.insert(chosen, entry.value)
            end
          end

          if #chosen > 0 then
            on_choice(chosen)
          end
        end)
        return true
      end,
    })
    :find()
end

--- Plain `vim.ui.select` fallback: single-select only, wrapped in a
--- 1-element array so callers have one uniform shape regardless of backend.
--- @param items PickerItem[] The entries to show in the picker.
--- @param format_item fun(t: PickerItem): string Formats an item for display.
--- @param on_choice fun(choices: PickerItem[]) Called with the one chosen
---        item, wrapped in a single-element array. Never called if cancelled.
local function select_native(items, format_item, on_choice)
  vim.ui.select(items, {
    prompt = "Bazel target:",
    format_item = format_item,
  }, function(choice)
    if choice then
      on_choice({ choice })
    end
  end)
end

--- Shows a picker over items and calls on_choice with everything selected
--- (always at least 1 item). Uses Telescope's native picker (with real
--- multi-select) if Telescope is loaded, otherwise falls back to plain
--- `vim.ui.select` (single-select only). Does nothing if cancelled.
--- @param items PickerItem[] The entries to show in the picker.
--- @param target_config TargetConfig Used to look up each item's icon.
--- @param on_choice fun(choices: PickerItem[]) Called with every selected item.
function M.select(items, target_config, on_choice)
  local format_item = make_formatter(items, target_config)

  if pcall(require, "telescope.pickers") then
    select_telescope(items, format_item, on_choice)
  else
    select_native(items, format_item, on_choice)
  end
end

return M
