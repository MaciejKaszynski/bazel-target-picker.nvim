load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library", "cc_test")
load(":custom.bzl", "custom_rule")

cc_library(
    name = "lib",
    srcs = ["lib.cpp"],
    hdrs = ["lib.hpp"],
    visibility = ["//visibility:public"],
)

cc_test(
    name = "lib_test",
    srcs = ["lib_test.cpp"],
    deps = [":lib"],
)

cc_binary(
    name = "main",
    srcs = ["main.cpp"],
    deps = [":lib"],
)

# Unrecognized rule kind (kind = "custom_rule"), to exercise the
# falls-back-to-"build" path in query.resolve_commands.
custom_rule(
    name = "custom_target",
    srcs = ["custom.txt"],
)
