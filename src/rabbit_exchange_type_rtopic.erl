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
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

%% NOTE: This plugin is compltetely based on the rabbitmq topic exchange
%% what changes is the routing algorithm.
%% That means there's a lot of duplicated code. Perhaps trie creation could 
%% be extracted into its own module to prevent.

-include_lib("rabbit_common/include/rabbit.hrl").

-behaviour(rabbit_exchange_type).

-export([description/0, serialise_events/0, route/2]).
-export([validate/1, validate_binding/2,
         create/2, delete/3, policy_changed/2, add_binding/3,
         remove_bindings/3, assert_args_equivalence/2]).
-export([init/0]).
-export([info/1, info/2]).

-rabbit_boot_step({?MODULE,
                   [{description, "exchange type rtopic"},
                    {mfa,         {rabbit_registry, register,
                                   [exchange, <<"x-rtopic">>, ?MODULE]}},
                    {requires,    rabbit_registry},
                    {enables,     kernel_ready}]}).

-rabbit_boot_step(
   {rabbit_exchange_type_rtopic_mnesia,
    [{description, "exchange type x-rtopic: mnesia"},
     {mfa,         {?MODULE, init, []}},
     {requires,    database},
     {enables,     external_infrastructure}]}).

-record(rtopic_trie_node, {trie_node, edge_count, binding_count}).
-record(rtopic_trie_edge, {trie_edge, node_id}).
-record(rtopic_trie_binding, {trie_binding, value = const}).

-record(rtrie_node, {exchange_name, node_id}).
-record(rtrie_edge, {exchange_name, node_id, word}).
-record(rtrie_binding, {exchange_name, node_id, destination}).

-define(DEFAULT_SIZE, 0).

%%----------------------------------------------------------------------------

info(_X) -> [].
info(_X, _) -> [].

description() ->
    [{description, <<"AMQP reverse topic exchange">>}].

serialise_events() -> false.

%% NB: This may return duplicate results in some situations (that's ok)
route(#exchange{name = X},
      #delivery{message = #basic_message{routing_keys = Routes}}) ->
    lists:append([begin
                      Words = split_topic_key(RKey),
                      mnesia:async_dirty(fun trie_match/2, [X, Words])
                  end || RKey <- Routes]).

validate(_X) -> ok.
validate_binding(_X, _B) -> ok.
create(_Tx, _X) -> ok.

delete(transaction, #exchange{name = X}, _Bs) ->
    trie_remove_all_nodes(X),
    trie_remove_all_edges(X),
    trie_remove_all_bindings(X),
    ok;
delete(none, _Exchange, _Bs) ->
    ok.

policy_changed(_X1, _X2) -> ok.

add_binding(transaction, _Exchange, Binding) ->
    internal_add_binding(Binding);
add_binding(none, _Exchange, _Binding) ->
    ok.

remove_bindings(transaction, _X, Bs) ->
    %% See rabbit_binding:lock_route_tables for the rationale for
    %% taking table locks.
    case Bs of
        [_] -> ok;
        _   -> [mnesia:lock({table, T}, write) ||
                   T <- [rabbit_rtopic_trie_node,
                         rabbit_rtopic_trie_edge,
                         rabbit_rtopic_trie_binding]]
    end,
    [begin
         Path = [{FinalNode, _} | _] =
             follow_down_get_path(X, split_topic_key(K)),
         trie_remove_binding(X, FinalNode, D),
         remove_path_if_empty(X, Path)
     end ||  #binding{source = X, key = K, destination = D} <- Bs],
    ok;
remove_bindings(none, _X, _Bs) ->
    ok.

assert_args_equivalence(X, Args) ->
    rabbit_exchange:assert_args_equivalence(X, Args).

%%----------------------------------------------------------------------------

internal_add_binding(#binding{source = X, key = K, destination = D}) ->
    FinalNode = follow_down_create(X, split_topic_key(K)),
    trie_add_binding(X, FinalNode, D),
    ok.

trie_match(X, Words) ->
    trie_match(X, root, Words, []).

trie_match(X, Node, [], ResAcc) ->
    trie_bindings(X, Node) ++ ResAcc;
trie_match(X, Node, ["#"], ResAcc) ->
    %% "#" is the last word in the pattern. 
    %% Get current node and all "down nodes" bindings.
    collect_down_bindings(X, Node, trie_bindings(X, Node) ++ ResAcc);
trie_match(X, Node, ["#" | RestW], ResAcc) ->
    collect_with_hash(X, Node, RestW, ResAcc);
trie_match(X, Node, ["*"], ResAcc) ->
    lists:foldl(fun (Child, Acc) ->
                    trie_bindings(X, Child) ++ Acc
                end, ResAcc, trie_children(X, Node));
trie_match(X, Node, ["*" | RestW], ResAcc) ->
    %% find all node children, and call trie_match on each of them
    lists:foldl(fun (Child, Acc) ->
                       trie_match(X, Child, RestW, Acc)
                end, ResAcc, trie_children(X, Node));
trie_match(X, Node, [W | RestW], ResAcc) ->
    %% go down just one word: W
    case trie_child(X, Node, W) of
        {ok, NextNode} -> trie_match(X, NextNode, RestW, ResAcc);
        error          -> ResAcc
    end.

collect_down_bindings(X, Node, ResAcc) ->
    case trie_children(X, Node) of
        [] ->
            ResAcc;
        Children ->
            lists:foldl(
              fun (Child, Acc) ->
                      collect_down_bindings(X, Child, trie_bindings(X, Child) ++ Acc)
              end, ResAcc, Children)
    end.

collect_with_hash(X, Node, [W|_Tail] = RestW, ResAcc) ->
    lists:foldl(fun ({Word, Child}, Acc) ->
                    case Word of
                        W -> collect_with_hash(X, Child, RestW, trie_match(X, Node, RestW, Acc));
                        _ -> collect_with_hash(X, Child, RestW, Acc)
                    end
                end, ResAcc, trie_children2(X, Node)).

follow_down_create(X, Words) ->
    case follow_down_last_node(X, Words) of
        {ok, FinalNode}      -> FinalNode;
        {error, Node, RestW} -> 
            lists:foldl(
                fun (W, CurNode) ->
                    NewNode = new_node_id(),
                    trie_add_edge(X, CurNode, NewNode, W),
                    NewNode
                end, Node, RestW)
    end.

follow_down_last_node(X, Words) ->
    follow_down(X, fun (_, Node, _) -> Node end, root, Words).

follow_down_get_path(X, Words) ->
    {ok, Path} =
        follow_down(X, fun (W, Node, PathAcc) -> [{Node, W} | PathAcc] end,
                    [{root, none}], Words),
    Path.

follow_down(X, AccFun, Acc0, Words) ->
    follow_down(X, root, AccFun, Acc0, Words).

follow_down(_X, _CurNode, _AccFun, Acc, []) ->
    {ok, Acc};
follow_down(X, CurNode, AccFun, Acc, Words = [W | RestW]) ->
    case trie_child(X, CurNode, W) of
        {ok, NextNode} -> follow_down(X, NextNode, AccFun,
                                      AccFun(W, NextNode, Acc), RestW);
        error          -> {error, Acc, Words}
    end.

remove_path_if_empty(_, [{root, none}]) ->
    ok;
remove_path_if_empty(X, [{Node, W} | [{Parent, _} | _] = RestPath]) ->
    case mnesia:read(rabbit_rtopic_trie_node,
                     #rtrie_node{exchange_name = X, node_id = Node}, write) of
        [] -> trie_remove_edge(X, Parent, Node, W),
              remove_path_if_empty(X, RestPath);
        _  -> ok
    end.

trie_child(X, Node, Word) ->
    case mnesia:read({rabbit_rtopic_trie_edge,
                      #rtrie_edge{exchange_name = X,
                                 node_id       = Node,
                                 word          = Word}}) of
        [#rtopic_trie_edge{node_id = NextNode}] -> {ok, NextNode};
        []                                      -> error
    end.

trie_children(X, Node) ->
    MatchHead =
        #rtopic_trie_edge{
           trie_edge = #rtrie_edge{exchange_name = X,
                                   node_id       = Node,
                                   _             = '_'},
           node_id = '$1'},
    mnesia:select(rabbit_rtopic_trie_edge, [{MatchHead, [], ['$1']}]).

trie_children2(X, Node) ->
    MatchHead =
        #rtopic_trie_edge{
           trie_edge = #rtrie_edge{exchange_name = X,
                                   node_id       = Node,
                                   word          = '$1'},
           node_id = '$2'},
    mnesia:select(rabbit_rtopic_trie_edge, [{MatchHead, [], [{{'$1', '$2'}}]}]).

trie_bindings(X, Node) ->
    MatchHead = #rtopic_trie_binding{
      trie_binding = #rtrie_binding{exchange_name = X,
                                   node_id       = Node,
                                   destination   = '$1'}},
    mnesia:select(rabbit_rtopic_trie_binding, [{MatchHead, [], ['$1']}]).

read_trie_node(X, Node) ->
    case mnesia:read(rabbit_rtopic_trie_node,
                     #rtrie_node{exchange_name = X,
                                 node_id       = Node}, write) of
        []   -> #rtopic_trie_node{trie_node = #rtrie_node{
                                  exchange_name = X,
                                  node_id       = Node},
                                  edge_count    = 0,
                                  binding_count = 0};
        [E0] -> E0
    end.

trie_update_node_counts(X, Node, Field, Delta) ->
    E = read_trie_node(X, Node),
    case setelement(Field, E, element(Field, E) + Delta) of
        #rtopic_trie_node{edge_count = 0, binding_count = 0} ->
            ok = mnesia:delete_object(rabbit_rtopic_trie_node, E, write);
        EN ->
            ok = mnesia:write(rabbit_rtopic_trie_node, EN, write)
    end.

trie_add_edge(X, FromNode, ToNode, W) ->
    trie_update_node_counts(X, FromNode, #rtopic_trie_node.edge_count, +1),
    trie_edge_op(X, FromNode, ToNode, W, fun mnesia:write/3).

trie_remove_edge(X, FromNode, ToNode, W) ->
    trie_update_node_counts(X, FromNode, #rtopic_trie_node.edge_count, -1),
    trie_edge_op(X, FromNode, ToNode, W, fun mnesia:delete_object/3).

trie_edge_op(X, FromNode, ToNode, W, Op) ->
    ok = Op(rabbit_rtopic_trie_edge,
            #rtopic_trie_edge{trie_edge = #rtrie_edge{exchange_name = X,
                                                      node_id       = FromNode,
                                                      word          = W},
                             node_id   = ToNode},
            write).

trie_add_binding(X, Node, D) ->
    trie_update_node_counts(X, Node, #rtopic_trie_node.binding_count, +1),
    trie_binding_op(X, Node, D, fun mnesia:write/3).

trie_remove_binding(X, Node, D) ->
    trie_update_node_counts(X, Node, #rtopic_trie_node.binding_count, -1),
    trie_binding_op(X, Node, D, fun mnesia:delete_object/3).

trie_binding_op(X, Node, D, Op) ->
    ok = Op(rabbit_rtopic_trie_binding,
            #rtopic_trie_binding{
              trie_binding = #rtrie_binding{exchange_name = X,
                                            node_id       = Node,
                                            destination   = D}},
            write).

trie_remove_all_nodes(X) ->
    remove_all(rabbit_rtopic_trie_node,
               #rtopic_trie_node{trie_node = #rtrie_node{exchange_name = X,
                                                       _               = '_'},
                                 _         = '_'}).

trie_remove_all_edges(X) ->
    remove_all(rabbit_rtopic_trie_edge,
               #rtopic_trie_edge{trie_edge = #rtrie_edge{exchange_name = X,
                                                       _               = '_'},
                                 _         = '_'}).

trie_remove_all_bindings(X) ->
    remove_all(rabbit_rtopic_trie_binding,
               #rtopic_trie_binding{
                 trie_binding = #rtrie_binding{exchange_name = X, _ = '_'},
                 _            = '_'}).

remove_all(Table, Pattern) ->
    lists:foreach(fun (R) -> mnesia:delete_object(Table, R, write) end,
                  mnesia:match_object(Table, Pattern, write)).

new_node_id() ->
    rabbit_guid:gen().

split_topic_key(Key) ->
    split_topic_key(Key, [], []).

split_topic_key(<<>>, [], []) ->
    [];
split_topic_key(<<>>, RevWordAcc, RevResAcc) ->
    lists:reverse([lists:reverse(RevWordAcc) | RevResAcc]);
split_topic_key(<<$., Rest/binary>>, RevWordAcc, RevResAcc) ->
    split_topic_key(Rest, [], [lists:reverse(RevWordAcc) | RevResAcc]);
split_topic_key(<<C:8, Rest/binary>>, RevWordAcc, RevResAcc) ->
    split_topic_key(Rest, [C | RevWordAcc], RevResAcc).

%%----------------------------------------------------------------------------
%% Mnesia initialization
%%----------------------------------------------------------------------------

init() ->
    Tables = 
    [{rabbit_rtopic_trie_node,
     [{record_name, rtopic_trie_node},
      {attributes, record_info(fields, rtopic_trie_node)},
      {type, ordered_set}]},
    {rabbit_rtopic_trie_edge,
     [{record_name, rtopic_trie_edge},
      {attributes, record_info(fields, rtopic_trie_edge)},
      {type, ordered_set}]},
    {rabbit_rtopic_trie_binding,
     [{record_name, rtopic_trie_binding},
      {attributes, record_info(fields, rtopic_trie_binding)},
      {type, ordered_set}]}],
    [begin
        mnesia:create_table(Table, Attrs),
        mnesia:add_table_copy(Table, node(), ram_copies)
     end || {Table, Attrs} <- Tables],
    
    TNames = [T || {T, _} <- Tables],
    mnesia:wait_for_tables(TNames, 30000),
    ok.
