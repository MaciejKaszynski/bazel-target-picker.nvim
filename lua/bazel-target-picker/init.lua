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

-- Priority when a kind matches more than one command's list, e.g. a test
-- kind is in both "test" and "coverage"; a binary kind is in both "run"
-- and "build". Checked in this order so the result is deterministic.
--- @type TargetType[]
local COMMAND_PRIORITY = { "test", "run", "coverage", "build" }

--- Resolves every bazel subcommand that applies to a rule kind, in
--- COMMAND_PRIORITY order (falls back to just "build" if none match).
--- @param kind string
--- @return TargetType[]
local function resolve_commands(kind)
  --- @type TargetType[]
  local commands = {}
  for _, command in ipairs(COMMAND_PRIORITY) do
    local kinds = M.config.target_types[command]
    if kinds and vim.tbl_contains(kinds, kind) then
      table.insert(commands, command)
    end
  end
  if #commands == 0 then
    table.insert(commands, "build")
  end
  return commands
end

--- A Bazel target found by `query_targets`.
--- @class BazelTarget
--- @field kind string The rule kind, e.g. "cc_library" or "cc_test".
--- @field label string The target's label, e.g. "//pkg:name".

--- One selectable entry in the picker: a target paired with one of the
--- subcommands that applies to it, e.g. a cc_test shows up once as "test"
--- and once as "coverage".
--- @class PickerItem : BazelTarget
--- @field command TargetType

--- Expands each target into one PickerItem per applicable command, in
--- COMMAND_PRIORITY order.
--- @param targets BazelTarget[]
--- @return PickerItem[]
local function expand_targets(targets)
  --- @type PickerItem[]
  local items = {}
  for _, target in ipairs(targets) do
    for _, command in ipairs(resolve_commands(target.kind)) do
      table.insert(items, { kind = target.kind, label = target.label, command = command })
    end
  end
  return items
end

--- The Repo specific Config
--- @class RepoConfig
--- @field depth number? How close do the targets have to be.
--- @field extra_args string? Additional args to add to the command.
--- @field universe string? Where to start searching.

--- Searches for the given file names going down desceding the file tree from
--- the given start path.
--- @nodiscard
--- @param start_dir string The path to start the search at, must be a dir.
--- @param filenames string[] List of file names to look for.
--- @return string?
local function find_upwards(start_dir, filenames)
  local dir = start_dir
  while true do
    for _, name in ipairs(filenames) do
      if vim.fn.filereadable(dir .. "/" .. name) == 1 then
        return dir
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then return nil end
    dir = parent
  end
end

--- Returns the Bazel label for the current buffer's file
--- @details This is using the `//a/b/c` format to the nearest BUILD file,
---          then `:` and the rest of the path.
--- @return string?, string?
local function get_current_file_label()
  local filepath = vim.fn.expand("%:p")
  if filepath == "" then
    vim.notify("No file in current buffer", vim.log.levels.ERROR)
    return nil
  end

  -- find root
  local file_dir = vim.fn.fnamemodify(filepath, ":h")
  local workspace_root = find_upwards(file_dir, { "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel" })
  if not workspace_root then
    vim.notify("Not inside a Bazel workspace: " .. filepath, vim.log.levels.ERROR)
    return nil
  end

  -- find nearest BUILD
  local package_dir = find_upwards(file_dir, { "BUILD", "BUILD.bazel" })
  if not package_dir then
    vim.notify("No BUILD file found above " .. filepath, vim.log.levels.ERROR)
    return nil
  end

  local package_path = package_dir:sub(#workspace_root + 2)
  local file_rel = filepath:sub(#package_dir + 2)
  return string.format("//%s:%s", package_path, file_rel), workspace_root
end

--- Resolves the shared .git dir (handles worktrees) for a given path.
--- @param workspace_root string The workspace to look in.
--- @return string?
local function get_git_common_dir(workspace_root)
  local out = vim.fn.systemlist({ "git", "-C", workspace_root, "rev-parse", "--git-common-dir" })
  if vim.v.shell_error ~= 0 or not out[1] then return nil end
  local git_dir = out[1]
  if not git_dir:match("^/") then
    git_dir = vim.fn.fnamemodify(workspace_root .. "/" .. git_dir, ":p")
  end
  return (git_dir:gsub("/$", ""))
end

--- Read the repo config.
--- @detials Some repos need extra args, these are specific to the repo so
---          store then in the `.git` directory.
--- @param workspace_root string The workspace path.
--- @return RepoConfig
local function read_repo_config(workspace_root)
  local git_dir = get_git_common_dir(workspace_root)
  if not git_dir then return {} end

  local config_path = git_dir .. "/nvim-bazel.json"
  local f = io.open(config_path, "r")
  if not f then return {} end

  local content = f:read("*a")
  f:close()

  --- @type boolean, any
  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" then
    vim.notify("Failed to parse " .. config_path, vim.log.levels.WARN)
    return {}
  end
  return decoded
end

--- Finds targets within `depth` dependency hops of file_label, within universe.
--- Returns a list of { kind, label }, or nil on query failure.
--- @param file_label string The label of the file to query for.
--- @param universe string The root where to search from.
--- @param depth number How far away the targets can be.
--- @return BazelTarget[]?
local function query_targets(file_label, universe, depth)
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

--- Right-pads s with spaces to reach the given display width. Uses display
--- width rather than byte length so multi-byte icons (emoji) still align.
--- @param s string
--- @param width integer
--- @return string
local function pad(s, width)
  return s .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(s)))
end

--- Gives the registered picker the items
--- @param items PickerItem[]
--- @param on_choice fun(choice: PickerItem)
local function pick_bazel_target(items, on_choice)
  local icon_width, command_width = 0, 0
  for _, t in ipairs(items) do
    local icon = M.config.icons[t.command] or M.config.default_icon
    icon_width = math.max(icon_width, vim.fn.strdisplaywidth(icon))
    command_width = math.max(command_width, #t.command)
  end

  vim.ui.select(items, {
    prompt = "Bazel target:",
    --- @param t PickerItem
    --- @return string
    format_item = function(t)
      local short_name = t.label:match(":([^:]+)$") or t.label
      local icon = M.config.icons[t.command] or M.config.default_icon
      return string.format("%s %s %s", pad(icon, icon_width), pad(t.command, command_width), short_name)
    end,
  }, function(choice)
    if choice then on_choice(choice) end
  end)
end

--- Finds Bazel targets related to the current buffer's file and lets you
--- pick one to build or test.
function M.pick()
  local file_label, workspace_root = get_current_file_label()
  if not file_label then return end
  if not workspace_root then return end
  vim.notify("File label: " .. file_label)

  local repo_config = read_repo_config(workspace_root)
  local extra_args = repo_config.extra_args or ""
  --- @type string?
  local package_path = file_label:match("^//(.-):")
  if not package_path then return end
  local universe = repo_config.universe or ("//" .. package_path .. ":*")
  local depth = repo_config.depth or M.config.depth or 4

  local targets = query_targets(file_label, universe, depth)
  if not targets then return end
  if #targets == 0 then
    vim.notify("No targets found for " .. file_label, vim.log.levels.WARN)
    return
  end

  local items = expand_targets(targets)

  pick_bazel_target(items, function(choice)
    local cmd = "bazel " .. choice.command .. " " .. choice.label
    if extra_args ~= "" then
      cmd = cmd .. " " .. extra_args
    end
    M.config.run(cmd)
  end)
end

--- Configures the picker. Does not set any keymaps — call `require(...).pick`
--- from your own `vim.keymap.set` to bind it.
--- @param opts? Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
