%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ Reverse Topic Exchange.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2011-2013 GoPivotal, Inc.  All rights reserved.
%%

-module(rabbit_exchange_type_rtopic_test).

-export([test/0]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

test() ->
    ok = eunit:test(tests(?MODULE, 60), [verbose]).

routing_test() ->
    ok = test0(t1()),
    ok = test0(t2()),
    ok = test0(t3()),
    ok = test0(t4()),
    ok = test0(t5()),
    ok = test0(t6()),
    ok = test0(t7()),
    ok = test0(t8()),
    ok = test0(t9()),
    ok = test0(t10()),
    ok = test0(t11()),
    ok = test0(t12()).

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

test0({Queues, Publishes, Count}) ->
    Msg = #amqp_msg{props = #'P_basic'{}, payload = <<>>},
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Chan} = amqp_connection:open_channel(Conn),
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
    amqp_channel:close(Chan),
    amqp_connection:close(Conn),
    ok.

unbind_test() ->
    ok = test1(u1()),
    ok = test1(u2()),
    ok = test1(u3()).

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

test1({Queues, Publishes, Unbinds, Count}) ->
    Msg = #amqp_msg{props = #'P_basic'{}, payload = <<>>},
    {ok, Conn} = amqp_connection:start(#amqp_params_network{}),
    {ok, Chan} = amqp_connection:open_channel(Conn),
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
    amqp_channel:close(Chan),
    amqp_connection:close(Conn),
    ok.


tests(Module, Timeout) ->
    {foreach, fun() -> ok end,
     [{timeout, Timeout, fun Module:F/0} ||
         {F, _Arity} <- proplists:get_value(exports, Module:module_info()),
         string:right(atom_to_list(F), 5) =:= "_test"]}.
