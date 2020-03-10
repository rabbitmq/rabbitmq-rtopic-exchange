%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at https://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ Reverse Topic Exchange.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2011-2020 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(rabbit_exchange_type_rtopic_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

all() ->
    [
      {group, non_parallel_tests}
    ].

groups() ->
    [
      {non_parallel_tests, [], [
                                routing_test,
                                unbind_test
                               ]}
    ].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodename_suffix, ?MODULE}
      ]),
    rabbit_ct_helpers:run_setup_steps(Config1,
      rabbit_ct_broker_helpers:setup_steps() ++
      rabbit_ct_client_helpers:setup_steps()).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).

%% -------------------------------------------------------------------
%% Testcases.
%% -------------------------------------------------------------------

routing_test(Config) ->
    ok = routing_test0(Config, t1()),
    ok = routing_test0(Config, t2()),
    ok = routing_test0(Config, t3()),
    ok = routing_test0(Config, t4()),
    ok = routing_test0(Config, t5()),
    ok = routing_test0(Config, t6()),
    ok = routing_test0(Config, t7()),
    ok = routing_test0(Config, t8()),
    ok = routing_test0(Config, t9()),
    ok = routing_test0(Config, t10()),
    ok = routing_test0(Config, t11()),
    ok = routing_test0(Config, t12()),

    passed.

t1() ->
    {[<<"a0.b0.c0.d0">>, <<"a1.b1.c1.d1">>], %% binding keys
    [<<"a0.b0.c0.d0">>], %% routing key
    1}. %% expected matches

t2() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b0.c0.d2">>],
    [<<"a0.b0.c0.*">>],
    3}.


t3() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b0.c0.d2">>],
    [<<"#">>],
    3}.

t4() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b1.c0.d0">>],
    [<<"#.d0">>],
    2}.

t5() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b1.c0.d0">>, <<"a3.b2.c0.d0">>],
    [<<"#.c0.d0">>],
    3}.

t6() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b1.c0.d0">>, <<"a3.b2.c0.d0">>],
    [<<"#.c0.*">>],
    4}.

t7() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b0.c0.d2">>, <<"a0.b0.c0">>],
    [<<"#">>],
    4}.

t8() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b0.c0.d2">>, <<"a0.b0.c0">>],
    [<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d0.e0">>],
    1}.

t9() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b1.c0.d0">>],
    [<<"#.c0.d0">>],
    2}.

t10() ->
    {[<<"a0.b1.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b1.c1.d0">>],
    [<<"a0.b1.#">>],
    2}.

t11() ->
    {[<<"a0.b1.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b1.c1.d0">>],
    [<<"a0.b1.c0.d0.#">>],
    1}.

%% test based on a user bug report.
t12() ->
    {[<<"PDFConstructor.PDFEnhancer.PDFSpy.PSrip.-.-">>],
    [<<"*.*.*.*.*.pdfToolbox">>],
    0}.

routing_test0(Config, {Queues, Publishes, Count}) ->
    Msg = #amqp_msg{props = #'P_basic'{}, payload = <<>>},
    Chan = rabbit_ct_client_helpers:open_channel(Config, 0),
    #'exchange.declare_ok'{} =
        amqp_channel:call(Chan,
                          #'exchange.declare' {
                            exchange = <<"rtopic">>,
                            type = <<"x-rtopic">>,
                            auto_delete = true
                           }),
    [#'queue.declare_ok'{} =
         amqp_channel:call(Chan, #'queue.declare' {
                             queue = Q, exclusive = true }) || Q <- Queues],
    [#'queue.bind_ok'{} =
         amqp_channel:call(Chan, #'queue.bind' { queue = Q,
                                                 exchange = <<"rtopic">>,
                                                 routing_key = Q })
     || Q <- Queues],

    #'tx.select_ok'{} = amqp_channel:call(Chan, #'tx.select'{}),
    [amqp_channel:call(Chan, #'basic.publish'{
                        exchange = <<"rtopic">>, routing_key = RK},
                       Msg) || RK <- Publishes],
    amqp_channel:call(Chan, #'tx.commit'{}),

    Counts =
        [begin
            #'queue.declare_ok'{message_count = M} =
                 amqp_channel:call(Chan, #'queue.declare' {queue     = Q,
                                                           exclusive = true }),
             M
         end || Q <- Queues],
    Count = lists:sum(Counts),
    amqp_channel:call(Chan, #'exchange.delete' { exchange = <<"rtopic">> }),
    [amqp_channel:call(Chan, #'queue.delete' { queue = Q }) || Q <- Queues],

    rabbit_ct_client_helpers:close_channel(Chan),

    ok.

unbind_test(Config) ->
    ok = unbind_test0(Config, u1()),
    ok = unbind_test0(Config, u2()),
    ok = unbind_test0(Config, u3()).

u1() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b0.c0.d2">>, <<"a0.b0.c0">>],
    [<<"#">>],
    [<<"a0.b0.c0.d2">>],
    3}.

u2() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b0.c0.d2">>, <<"a0.b0.c0">>,
      <<"a0.b1.c0.d0">>, <<"a0.b1.c0.d1">>, <<"a0.b1.c1.d2">>, <<"a0.b1.c1.d0">>
     ],
    [<<"#.d0">>],
    [<<"a0.b1.c1.d0">>],
    2}.

u3() ->
    {[<<"a0.b0.c0.d0">>, <<"a0.b0.c0.d1">>, <<"a0.b0.c0.d2">>, <<"a0.b0.c0">>,
      <<"a0.b1.c0.d0">>, <<"a0.b1.c0.d1">>, <<"a0.b1.c1.d2">>, <<"a0.b1.c1.d0">>
     ],
    [<<"#.c1.*">>],
    [<<"a0.b1.c1.d0">>],
    1}.

unbind_test0(Config, {Queues, Publishes, Unbinds, Count}) ->
    Msg = #amqp_msg{props = #'P_basic'{}, payload = <<>>},
    Chan = rabbit_ct_client_helpers:open_channel(Config, 0),
    #'exchange.declare_ok'{} =
        amqp_channel:call(Chan,
                          #'exchange.declare' {
                            exchange = <<"rtopic">>,
                            type = <<"x-rtopic">>,
                            auto_delete = true
                           }),
    [#'queue.declare_ok'{} =
         amqp_channel:call(Chan, #'queue.declare' {
                             queue = Q, exclusive = true }) || Q <- Queues],
    [#'queue.bind_ok'{} =
         amqp_channel:call(Chan, #'queue.bind' { queue = Q,
                                                 exchange = <<"rtopic">>,
                                                 routing_key = Q })
     || Q <- Queues],

    [#'queue.unbind_ok'{} =
         amqp_channel:call(Chan, #'queue.unbind' { queue = U,
                                                 exchange = <<"rtopic">>,
                                                 routing_key = U })
     || U <- Unbinds],

    #'tx.select_ok'{} = amqp_channel:call(Chan, #'tx.select'{}),
    [amqp_channel:call(Chan, #'basic.publish'{
                        exchange = <<"rtopic">>, routing_key = RK},
                       Msg) || RK <- Publishes],
    amqp_channel:call(Chan, #'tx.commit'{}),

    Counts =
        [begin
            #'queue.declare_ok'{message_count = M} =
                 amqp_channel:call(Chan, #'queue.declare' {queue     = Q,
                                                           exclusive = true }),
             M
         end || Q <- Queues],
    Count = lists:sum(Counts),
    amqp_channel:call(Chan, #'exchange.delete' { exchange = <<"rtopic">> }),
    [amqp_channel:call(Chan, #'queue.delete' { queue = Q }) || Q <- Queues],

    rabbit_ct_client_helpers:close_channel(Chan),
    ok.
