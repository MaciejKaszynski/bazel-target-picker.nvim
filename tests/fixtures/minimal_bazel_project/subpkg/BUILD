load("@rules_cc//cc:defs.bzl", "cc_binary")

# Depends on //:lib from a sibling package, so a universe scoped to just
# //:* (the root package) won't find this, while //... will.
cc_binary(
    name = "consumer",
    srcs = ["consumer.cpp"],
    deps = ["//:lib"],
)
