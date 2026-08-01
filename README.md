# Bazel Target Picker

Small plugin to pick bazel targets.
This plugin only builds the bazel command, it does not run the command or bind
any keys, this is for better extendability.

The plugin looks for targets that are related to the currently open file.
These targets are piped into the picker.
After a target is choosen a bazel command is constructed that can then be piped
to a terminal.

Uses [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) for
the picker if it's installed, which enables multi-select. Neither is a hard
dependency — falls back to plain `vim.ui.select` (single-select only)
otherwise.

## Quick Start

```lua
vim.pack.add({{src="https://github.com/MaciejKaszynski/bazel-target-picker.nvim"}})

local bazel_picker = require("bazel-target-picker")
bazel_picker.setup()

vim.keymap.set("n", "<leader>bb", function()
  bazel_picker.pick_from_buffer(function(cmd)
    vim.cmd("botright split | terminal " .. cmd)
  end)
end)
```

## Configuration

```lua
local bazel_picker = require("bazel-target-picker")
bazel_picker.setup{
    -- How close the shown targets shall be from the open file internally this
    -- uses the following command to find the targets:
    -- `bazel query kind(rule, rdeps(..., ..., depth))`
    depth = 4,
    -- Each target's picker entry shows the icon of the command it resolved
    -- to. Note that some rules like `cc_test` can be built or tested and so
    -- these targets will apear multiple times in the picker with just this
    -- icon (and command) changed.
    target_config = {
        -- "default"'s icon is the fallback used by any command below that
        -- doesn't set its own `icon` (e.g. a user defined command added via
        -- `additional_bazel_rules`). extra_args here is combined with every
        -- command's own extra_args.
        default = {
            icon = "❔",
            extra_args = {} -- a list of additional args to append to the command.
        },
        build = {
            icon = "⚙️",
            additional_bazel_rules = {}, -- any new bazel rules that support `bazel build`.
            extra_args = {} -- a list of additional args to append to the command. Note this is combined with the default config.
        },
        run = {
            icon = "▶️",
            additional_bazel_rules = {},
            extra_args = {}
        },
        coverage = {
            icon = "📊",
            additional_bazel_rules = {},
            extra_args = {}
        },
        test = {
            icon = "🧪",
            additional_bazel_rules = {},
            extra_args = {}
        }
    }
}
```


### Repository Configuration

Some of the configurable fields only make sense for a partiular repository
and so these setting can be stored in `.git/bazel-target-picker.json`.
This is purposefully not tracked.
The schema is exactly the same as the setup table.

This path is resolved via `git rev-parse --git-common-dir`, so in a git
worktree the file lives in the main checkout's `.git`, not the worktree's.


## API

### `setup(opts?)`

Merges `opts` into the global config and loads any repo-specific config
(`.git/bazel-target-picker.json`) for the current working directory's
workspace.

### `pick_from_buffer(dispatch)`

Resolves the current buffer's file to a Bazel label, finds related targets,
lets you pick one via `vim.ui.select`, builds the resulting bazel command,
then calls `dispatch(cmd)` with it as a string. Returns `true` if a target
was picked and dispatched, `false` otherwise.

This requires the current buffer's file to be:
- Inside a Bazel workspace.
- Underneath a `BUILD` or `BUILD.bazel` file.

If either isn't the case, or no related targets are found, or the underlying
`bazel query` fails `dispatch` is not called.

#### Example

```lua
vim.keymap.set("n", "<leader>bb", function()
  bazel_picker.pick_from_buffer(function(cmd)
    vim.cmd("botright split | terminal " .. cmd)
  end)
end)
```

You can use different terminals like [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)

```lua
vim.keymap.set("n", "<leader>bb", function()
  bazel_picker.pick_from_buffer(function(cmd)
    require("toggleterm").exec(cmd, nil, nil, nil, "float")
  end)
end)
```

### `pick_verbose_from_buffer(dispatch)`

Same requirements and behavior as `pick_from_buffer`, but `dispatch` receives
a `PickResult` table instead of just the command string.

#### `PickResult`

```lua
--- @class PickedTarget
--- @field label string The target's label, e.g. "//pkg:a".
--- @field rule string The Bazel rule kind, e.g. "cc_test".

--- @class PickResult
--- @field cmd string The full bazel command that would be run, e.g. "bazel
---        test //pkg:a //pkg:b --config=x86_64-linux".
--- @field targets PickedTarget[] The targets that made it into `cmd`, e.g.
---        { { label = "//pkg:a", rule = "cc_test" } }.
--- @field target_type TargetType The resolved bazel subcommand shared by every
---        entry in `targets`, e.g. "test".
```

#### Example

```lua
vim.keymap.set("n", "<leader>bb", function()
  bazel_picker.pick_verbose_from_buffer(function(result)
    local cmd = result.cmd
    if result.target_type == "coverage" then
        cmd = cmd .. " && genhtml bazel-out/_coverage/_coverage_report.dat --output-directory _build/coverage"
    end
    require("toggleterm").exec(cmd, nil, nil, nil, "float")
  end)
end)
```
