load("@rules_erlang//:erlang_bytecode2.bzl", "erlang_bytecode")
load("@rules_erlang//:filegroup.bzl", "filegroup")

def all_srcs(name = "all_srcs"):
    filegroup(
        name = "srcs",
        srcs = ["src/rabbit_exchange_type_rtopic.erl"],
    )
    filegroup(name = "private_hdrs")
    filegroup(
        name = "public_hdrs",
    )
    filegroup(name = "priv")
    filegroup(
        name = "license_files",
        srcs = [
            "LICENSE",
            "LICENSE-MPL-RabbitMQ",
        ],
    )
    filegroup(
        name = "public_and_private_hdrs",
        srcs = [":private_hdrs", ":public_hdrs"],
    )
    filegroup(
        name = "all_srcs",
        srcs = [":public_and_private_hdrs", ":srcs"],
    )

def all_beam_files(name = "all_beam_files"):
    erlang_bytecode(
        name = "other_beam",
        srcs = ["src/rabbit_exchange_type_rtopic.erl"],
        hdrs = [":public_and_private_hdrs"],
        app_name = "rabbitmq-rtopic-exchange",
        dest = "ebin",
        erlc_opts = "//:erlc_opts",
        deps = ["@rabbitmq-server//deps/rabbit_common:erlang_app"],
    )
    filegroup(
        name = "beam_files",
        srcs = [":other_beam"],
    )

def all_test_beam_files(name = "all_test_beam_files"):
    erlang_bytecode(
        name = "test_other_beam",
        testonly = True,
        srcs = ["src/rabbit_exchange_type_rtopic.erl"],
        hdrs = [":public_and_private_hdrs"],
        app_name = "rabbitmq-rtopic-exchange",
        dest = "test",
        erlc_opts = "//:test_erlc_opts",
        deps = ["@rabbitmq-server//deps/rabbit_common:erlang_app"],
    )
    filegroup(
        name = "test_beam_files",
        testonly = True,
        srcs = [":test_other_beam"],
    )

def test_suite_beam_files(name = "test_suite_beam_files"):
    erlang_bytecode(
        name = "rabbit_exchange_type_rtopic_SUITE_beam_files",
        testonly = True,
        srcs = ["test/rabbit_exchange_type_rtopic_SUITE.erl"],
        outs = ["test/rabbit_exchange_type_rtopic_SUITE.beam"],
        app_name = "rabbitmq-rtopic-exchange",
        erlc_opts = "//:test_erlc_opts",
        deps = ["@rabbitmq-server//deps/amqp_client:erlang_app"],
    )
    erlang_bytecode(
        name = "test_rabbit_rtopic_perf_beam",
        testonly = True,
        srcs = ["test/rabbit_rtopic_perf.erl"],
        outs = ["test/rabbit_rtopic_perf.beam"],
        app_name = "rabbitmq-rtopic-exchange",
        erlc_opts = "//:test_erlc_opts",
        deps = ["@rabbitmq-server//deps/rabbit_common:erlang_app"],
    )
