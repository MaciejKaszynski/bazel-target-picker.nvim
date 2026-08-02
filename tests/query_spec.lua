local query = require("bazel-target-picker.query")

--- @return string
local function fixture_dir()
  local this_file = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(this_file, ":h") .. "/fixtures/minimal_bazel_project"
end

describe("query.expand", function()
  it("expands a recognized test kind to test, coverage, and build", function()
    local targets = { { kind = "cc_test", label = "//pkg:t" } }
    local items = query.expand(targets, {})
    assert.same({
      { kind = "cc_test", label = "//pkg:t", command = "test" },
      { kind = "cc_test", label = "//pkg:t", command = "coverage" },
      { kind = "cc_test", label = "//pkg:t", command = "build" },
    }, items)
  end)

  it("expands a recognized binary kind to run and build", function()
    local targets = { { kind = "cc_binary", label = "//pkg:b" } }
    local items = query.expand(targets, {})
    assert.same({
      { kind = "cc_binary", label = "//pkg:b", command = "run" },
      { kind = "cc_binary", label = "//pkg:b", command = "build" },
    }, items)
  end)

  it("falls back to just build for an unrecognized kind", function()
    local targets = { { kind = "custom_rule", label = "//pkg:c" } }
    local items = query.expand(targets, {})
    assert.same({
      { kind = "custom_rule", label = "//pkg:c", command = "build" },
    }, items)
  end)

  it("honors additional_bazel_rules on top of build (regression: _itf_test)", function()
    local targets = { { kind = "custom_rule", label = "//pkg:c" } }
    local target_config = { test = { additional_bazel_rules = { "custom_rule" } } }
    local items = query.expand(targets, target_config)
    assert.same({
      { kind = "custom_rule", label = "//pkg:c", command = "test" },
      { kind = "custom_rule", label = "//pkg:c", command = "build" },
    }, items)
  end)
end)

describe("query.find / query.find_all (against the fixture workspace)", function()
  local prev_cwd

  before_each(function()
    prev_cwd = vim.fn.getcwd()
    vim.fn.chdir(fixture_dir())
  end)

  after_each(function()
    vim.fn.chdir(prev_cwd)
  end)

  --- @param items BazelTarget[]
  --- @return string[]
  local function labels(items)
    local out = {}
    for _, t in ipairs(items) do
      table.insert(out, t.label)
    end
    table.sort(out)
    return out
  end

  it("find_all(//...) finds every target, including the unrecognized kind", function()
    local targets = query.find_all("//...")
    assert.same({
      "//:custom_target",
      "//:lib",
      "//:lib_test",
      "//:main",
      "//subpkg:consumer",
    }, labels(targets))
  end)

  it("find() scoped to the root package misses the cross-package dependent", function()
    local targets = query.find("//:lib.cpp", "//:*", 4)
    assert.same({ "//:lib", "//:lib_test", "//:main" }, labels(targets))
  end)

  it("find() scoped to the whole workspace includes the cross-package dependent", function()
    local targets = query.find("//:lib.cpp", "//...", 4)
    assert.same({ "//:lib", "//:lib_test", "//:main", "//subpkg:consumer" }, labels(targets))
  end)
end)
