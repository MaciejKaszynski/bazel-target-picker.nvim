"""A trivial custom rule, mirroring a repo-specific test rule (like the real
`_itf_test` this plugin was debugged against): a rule kind the plugin has no
built-in knowledge of, so it should only resolve to "build" unless a user
adds it to `target_config.<command>.additional_bazel_rules`.
"""

def _custom_rule_impl(ctx):
    return [DefaultInfo(files = depset(ctx.files.srcs))]

custom_rule = rule(
    implementation = _custom_rule_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
    },
)
