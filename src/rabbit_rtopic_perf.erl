-module(rabbit_rtopic_perf).

-compile(export_all).

-include_lib("amqp_client/include/amqp_client.hrl").

-define(QUEUE_FILE, "/tmp/queues").
-define(RKEYS_FILE, "/tmp/rkeys").
-define(RAND_KEYS_FILE, "/tmp/rand_rkeys").

prepare_test() ->
    dump_queues(10000, 10),
    dump_rand_rkeys(10000, 15).

test() ->
    Runs = [
        {1, 1, 100},
        {10, 10, 100},
        {100, 10, 100},
        {1000, 10, 100}
    ],
    test(Runs).

test(Runs) ->
    [begin
        Res = run(NQs, NRKs, Reps),
        {Res, R}
     end || R = {NQs, NRKs, Reps}  <- Runs].

run(NQs, NRKs, Reps) ->
    X = <<"rtopic">>,
    {ok, [Queues]} = file:consult(?QUEUE_FILE),
    {ok, [RKeys]} = file:consult(?RAND_KEYS_FILE),
    {Qs, _} = lists:split(NQs, Queues),
    {Rs, _} = lists:split(NRKs, RKeys),
    prepare_bindings0(X, Qs),
    F = fun (Routes) -> route0(X, Routes) end,
    Res = tcn(F, Rs, Reps),
    delete_exchange(X),
    Res.

prepare_bindings(XBin, N, Length) ->
    Queues = queues(N, Length),
    prepare_bindings0(XBin, Queues).

prepare_bindings0(XBin, Queues) ->
    [add_binding(XBin, Q, Q) || Q <- Queues],
    ok.

route(XBin, N, Length) ->
    RKeys = rkeys(N, Length),
    route0(XBin, RKeys).

route0(XBin, RKeys) ->
    Props = rabbit_basic:properties(#'P_basic'{content_type = <<"text/plain">>}),
    X = exchange(XBin),
    [begin
        Msg = rabbit_basic:message(XBin, RKey, Props, <<>>),
        Delivery = rabbit_basic:delivery(false, false, Msg, undefined),
        rabbit_exchange_type_rtopic:route(X, Delivery)
     end || RKey <- RKeys].

delete_exchange(XBin) ->
    X = exchange(XBin),
    F = fun () ->
            rabbit_exchange_type_rtopic:delete(transaction, X, [])
        end,
    rabbit_misc:execute_mnesia_transaction(F).

add_binding(XBin, QBin, BKey) ->
    F = fun () ->
            rabbit_exchange_type_rtopic:add_binding(transaction, exchange(XBin), binding(XBin, QBin, BKey))
        end,
    rabbit_misc:execute_mnesia_transaction(F).

dump_queues(N, Length) ->
    dump_to_file(N, Length, queues).

dump_rkeys(N, Length) ->
    dump_to_file(N, Length, rkeys).

dump_rand_rkeys(N, Length) ->
    dump_to_file(N, Length, rand_rkeys).

dump_to_file(N, Length, queues) ->
    Queues = queues(N, Length),
    dump_to_file(?QUEUE_FILE, Queues);

dump_to_file(N, Length, rkeys) ->
    RKeys = rkeys(N, Length),
    dump_to_file(?RKEYS_FILE, RKeys);

dump_to_file(N, Length, rand_rkeys) ->
    RKeys = rkeys_rand_len(N, Length),
    dump_to_file(?RAND_KEYS_FILE, RKeys).

dump_to_file(F, Data) ->
    file:write_file(F, io_lib:fwrite("~p.\n", [Data])).

tcn(F, Arg, N) ->
    {Time, _Val} = timer:tc(fun tcn2/3, [F, Arg, N]),
    Time/N.

tcn2(_F, _Arg, 0) -> ok;
tcn2(F, Arg, N) ->
    F(Arg),
    tcn2(F, Arg, N-1).

queues(N, L) ->
    do_n(fun queue_name/1, L, N).

rand_queues(N, L) ->
    do_n(fun random_length_queue_name/1, L, N).

rkeys(N, L) ->
    do_n(fun routing_key/1, L, N).

rkeys_rand_len(N, L) ->
    do_n(fun rand_routing_key/1, L, N).

queue_name(L) ->
    list_to_binary(random_string(L, false)).

random_length_queue_name(L) ->
    L1 = rand_compat:uniform(L),
    list_to_binary(random_string(L1, false)).

routing_key(L) ->
    list_to_binary(random_string(L, true)).

rand_routing_key(L) ->
    L1 = rand_compat:uniform(L),
    list_to_binary(random_string(L1, true)).

do_n(Fun, Arg, N) ->
    do_n(Fun, Arg, 0, N, []).

do_n(_Fun, _Arg, N, N, Acc) ->
    Acc;
do_n(Fun, Arg, Count, N, Acc) ->
    do_n(Fun, Arg, Count+1, N, [Fun(Arg) | Acc]).

random_string(0, _Wild) -> [];
random_string(1 = Length, Wild) -> [random_char(rand_compat:uniform(30), Wild) | random_string(Length-1, Wild)];
random_string(Length, Wild) -> [random_char(rand_compat:uniform(30), Wild), 46 | random_string(Length-1, Wild)].
random_char(1, true) -> 42;
random_char(2, true) -> 35;
random_char(_N, _) -> rand_compat:uniform(25) + 97.

exchange(XBin) ->
    #exchange{name        = #resource{virtual_host = <<"/">>, kind = exchange, name = XBin},
              type        = 'x-rtopic',
              durable     = true,
              auto_delete = false,
              arguments   = []}.

binding(XBin, QBin, BKey) ->
    #binding{source      = #resource{virtual_host = <<"/">>, kind = exchange, name = XBin},
             destination = #resource{virtual_host = <<"/">>, kind = queue, name = QBin},
             key         = BKey,
             args        = []}.
