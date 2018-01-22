%% -------------------------------------------------------------------
%%
%% Copyright (c) 2017 Christopher S. Meiklejohn.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
%%

-module(functionality_SUITE).
-author("Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>").

%% common_test callbacks
-export([suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0,
         groups/0,
         init_per_group/2]).

%% tests
-compile([export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").

-define(APP, unir).
-define(CLIENT_NUMBER, 3).
-define(PEER_PORT, 9000).
-define(GET_REQUEST, fsm_get).
-define(PUT_REQUEST, fsm_put).

-define(SUPPORT, support).

%% ===================================================================
%% common_test callbacks
%% ===================================================================

suite() ->
    [{timetrap, {hours, 10}}].

init_per_suite(_Config) ->
    _Config.

end_per_suite(_Config) ->
    _Config.

init_per_testcase(Case, Config) ->
    ct:pal("Beginning test case ~p", [Case]),
    [{hash, erlang:phash2({Case, Config})}|Config].

end_per_testcase(Case, Config) ->
    ct:pal("Ending test case ~p", [Case]),
    Config.

init_per_group(disterl, Config) ->
    Config;

init_per_group(partisan, Config) ->
    [{partisan_dispatch, true}] ++ Config;

init_per_group(partisan_races, Config) ->
    init_per_group(partisan, Config);
init_per_group(partisan_scale, Config) ->
    init_per_group(partisan, Config);
init_per_group(partisan_large_scale, Config) ->
    init_per_group(partisan, Config);

init_per_group(partisan_with_parallelism, Config) ->
    [{parallelism, 5}] ++ init_per_group(partisan, Config);
init_per_group(partisan_with_binary_padding, Config) ->
    [{binary_padding, true}] ++ init_per_group(partisan, Config);
init_per_group(partisan_with_vnode_partitioning, Config) ->
    [{vnode_partitioning, true}] ++ init_per_group(partisan, Config);

init_per_group(bench, Config) ->
    ?SUPPORT:bench_config() ++ Config;

init_per_group(_, Config) ->
    Config.

end_per_group(_, _Config) ->
    ok.

all() ->
    [
     {group, default, []}
    ].

groups() ->
    [
     {basic, [],
      [membership_test, 
       metadata_test, 
       get_put_test,
       vnode_test,
       {group, bench}]},

     {bench, [],
      [bench_test]},

     {failures, [],
      [large_gossip_test,
       transition_test]},

     {default, [],
      [{group, bench}]
     },

     {disterl, [],
      [{group, basic}]
     },
     
     {partisan, [],
      [{group, basic}]
     },

     {races, [],
      [four_node_membership_test]},

     {partisan_races, [],
      [four_node_membership_test]},

     {scale, [],
      [scale_test]},

     {partisan_scale, [],
      [scale_test]},
     
     {large_scale, [],
      [large_scale_test]},

     {partisan_large_scale, [],
      [large_scale_test]},

     {partisan_with_parallelism, [],
      [{group, bench}]},

     {partisan_with_binary_padding, [],
      [{group, bench}]},

     {partisan_with_vnode_partitioning, [],
      [{group, bench}]}
    ].

%% ===================================================================
%% Tests.
%% ===================================================================

bench_test(Config) ->
    Nodes = ?SUPPORT:start(bench_test,
                           Config,
                           [{num_nodes, 3},
                           {partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    ct:pal("Configuration: ~p", [Config]),

    RootDir = ?SUPPORT:root_dir(Config),

    %% Configure parameters.
    ResultsParameters = case proplists:get_value(partisan_dispatch, Config, false) of
        true ->
            BinaryPadding = case proplists:get_value(binary_padding, Config, false) of
                true ->
                    "binary-padding";
                false ->
                    "no-binary-padding"
            end,

            VnodePartitioning = case proplists:get_value(vnode_partitioning, Config, false) of
                true ->
                    "vnode-partitioning";
                false ->
                    "no-vnode-partitioning"
            end,

            Parallelism = case proplists:get_value(parallelism, Config, 1) of
                1 ->
                    "parallelism-" ++ integer_to_list(1);
                P ->
                    "parallelism-" ++ integer_to_list(P)
            end,

            "partisan-" ++ BinaryPadding ++ "-" ++ VnodePartitioning ++ "-" ++ Parallelism;
        false ->
            "disterl"
    end,

    %% Select the node configuration.
    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    %% Verify partisan connection is configured with the correct
    %% membership information.
    ct:pal("Waiting for partisan membership..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_partisan_membership(SortedNodes)),

    %% Ensure we have the right number of connections.
    %% Verify appropriate number of connections.
    ct:pal("Waiting for partisan connections..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections(SortedNodes)),

    %% Configure bench paths.
    BenchDir = RootDir ++ "_build/default/lib/lasp_bench/",

    %% Build bench.
    ct:pal("Building benchmarking suite..."),
    BuildCommand = "cd " ++ BenchDir ++ "; make all",
    _BuildOutput = os:cmd(BuildCommand),
    % ct:pal("~p => ~p", [BuildCommand, BuildOutput]),

    %% Get benchmark configuration.
    BenchConfig = ?config(bench_config, Config),

    %% Run bench.
    ct:pal("Executing benchmark..."),
    SortedNodesString = lists:flatten(lists:join(",", lists:map(fun(N) -> atom_to_list(N) end, SortedNodes))),
    BenchCommand = "cd " ++ BenchDir ++ "; NODES=\"" ++ SortedNodesString ++ "\" _build/default/bin/lasp_bench " ++ RootDir ++ "examples/" ++ BenchConfig,
    _BenchOutput = os:cmd(BenchCommand),
    % ct:pal("~p => ~p", [BenchCommand, BenchOutput]),

    %% Generate results.
    ct:pal("Generating results..."),
    ResultsCommand = "cd " ++ BenchDir ++ "; make results",
    _ResultsOutput = os:cmd(ResultsCommand),
    % ct:pal("~p => ~p", [ResultsCommand, ResultsOutput]),

    case os:getenv("TRAVIS") of
        false ->
            %% Make results dir.
            ct:pal("Making results output directory..."),
            DirCommand = "mkdir " ++ RootDir ++ "results/",
            _DirOutput = os:cmd(DirCommand),
            % ct:pal("~p => ~p", [DirCommand, DirOutput]),

            %% Get full path to the results.
            ReadLinkCommand = "readlink " ++ BenchDir ++ "tests/current",
            ReadLinkOutput = os:cmd(ReadLinkCommand),
            FullResultsPath = string:substr(ReadLinkOutput, 1, length(ReadLinkOutput) - 1),
            ct:pal("~p => ~p", [ReadLinkCommand, ReadLinkOutput]),

            %% Get directory name.
            Directory = string:substr(FullResultsPath, string:rstr(FullResultsPath, "/") + 1, length(FullResultsPath)),
            ResultsDirectory = Directory ++ "-" ++ BenchConfig ++ "-" ++ ResultsParameters,

            %% Copy results.
            ct:pal("Copying results into output directory: ~p", [ResultsDirectory]),
            CopyCommand = "cp -rpv " ++ FullResultsPath ++ " " ++ RootDir ++ "results/" ++ ResultsDirectory,
            _CopyOutput = os:cmd(CopyCommand);
            % ct:pal("~p => ~p", [CopyCommand, CopyOutput]);
        _ ->
            ok
    end,

    ?SUPPORT:stop(Nodes),

    ok.

large_scale_test(Config) ->
    case os:getenv("TRAVIS") of
        "true" ->
            Nodes = ?SUPPORT:start(large_scale_test,
                                   Config,
                                   [{partisan_peer_service_manager,
                                       partisan_default_peer_service_manager},
                                   {num_nodes, 20},
                                   {cluster_nodes, false}]),

            ?SUPPORT:scale(Nodes);
        _ ->
            ct:pal("Skipping test; outside of the travis environment.")
    end,

    ok.

scale_test(Config) ->
    Nodes = ?SUPPORT:start(scale_test,
                           Config,
                           [{partisan_peer_service_manager,
                               partisan_default_peer_service_manager},
                           {num_nodes, 10},
                           {cluster_nodes, false}]),

    ?SUPPORT:scale(Nodes),

    ok.

transition_test(Config) ->
    Nodes = ?SUPPORT:start(transition_test,
                           Config,
                           [{partisan_peer_service_manager,
                               partisan_default_peer_service_manager},
                           {num_nodes, 4},
                           {cluster_nodes, false}]),

    %% Get the list of nodes.
    [{_, Node1}, {_, Node2}, {_, Node3}, {_, Node4}] = Nodes,

    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    %% Cluster the first two ndoes.
    ?assertEqual(ok, ?SUPPORT:join_cluster([Node1, Node2])),

    %% Verify appropriate number of connections.
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections([Node1, Node2])),

    %% Perform metadata storage write.
    ?assertEqual(ok, ?SUPPORT:perform_metadata_write(Node1)),

    %% Join the third node.
    ?assertEqual(ok, ?SUPPORT:staged_join(Node3, Node1)),

    %% Plan will only succeed once the ring has been gossiped.
    ?assertEqual(ok, ?SUPPORT:plan_and_commit(Node1)),

    %% Verify appropriate number of connections.
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections([Node1, Node2, Node3])),

    %% Join the fourth node.
    ?assertEqual(ok, ?SUPPORT:staged_join(Node4, Node1)),

    %% Plan will only succeed once the ring has been gossiped.
    ?assertEqual(ok, ?SUPPORT:plan_and_commit(Node1)),

    %% Verify appropriate number of connections.
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections([Node1, Node2, Node3, Node4])),

    %% Verify that we can read that value at all nodes.
    ?assertEqual(ok, ?SUPPORT:wait_until_metadata_read(SortedNodes)),

    %% Leave a node.
    ?assertEqual(ok, ?SUPPORT:leave(Node3)),

    %% Verify appropriate number of connections.
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections([Node1, Node2, Node4])),

    ?SUPPORT:stop(Nodes),

    ok.

metadata_test(Config) ->
    Nodes = ?SUPPORT:start(metadata_test,
                           Config,
                           [{partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    %% Get the first node.
    [{_Name, Node}|_] = Nodes,

    %% Put a value into the metadata system.
    ?assertEqual(ok, ?SUPPORT:perform_metadata_write(Node)),

    %% Verify that we can read that value at all nodes.
    ?assertEqual(ok, ?SUPPORT:wait_until_metadata_read(SortedNodes)),

    ?SUPPORT:stop(Nodes),

    ok.

get_put_test(Config) ->
    Nodes = ?SUPPORT:start(get_put_test,
                           Config,
                           [{partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    Key = key,
    Value = <<"binary">>,

    %% Get first node.
    Node = hd(SortedNodes),

    %% Make get request.
    case rpc:call(Node, ?APP, ?GET_REQUEST, [Key]) of
        {ok, _} ->
            ok;
        GetError ->
            ct:pal("Get failed: ~p", [GetError]),
            ct:fail({error, GetError})
    end,

    %% Make put request.
    case rpc:call(Node, ?APP, ?PUT_REQUEST, [Key, Value]) of
        {ok, _} ->
            ok;
        PutError ->
            ct:pal("Put failed: ~p", [PutError]),
            ct:fail({error, PutError})
    end,

    ?SUPPORT:stop(Nodes),

    ok.

four_node_membership_test(Config) ->
    Nodes = ?SUPPORT:start(four_node_membership_test,
                           Config,
                           [{num_nodes, 4},
                           {partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    %% Verify partisan connection is configured with the correct
    %% membership information.
    ct:pal("Waiting for partisan membership..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_partisan_membership(SortedNodes)),

    %% Ensure we have the right number of connections.
    %% Verify appropriate number of connections.
    ct:pal("Waiting for partisan connections..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections(SortedNodes)),

    ?SUPPORT:stop(Nodes),

    ok.

large_gossip_test(Config) ->
    Nodes = ?SUPPORT:start(large_gossip_test,
                           Config,
                           [{num_nodes, 5},
                           {partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    %% Verify partisan connection is configured with the correct
    %% membership information.
    ct:pal("Waiting for partisan membership..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_partisan_membership(SortedNodes)),

    %% Ensure we have the right number of connections.
    %% Verify appropriate number of connections.
    ct:pal("Waiting for partisan connections..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections(SortedNodes)),

    %% Bloat ring.
    ct:pal("Attempting to bloat the ring to see performance effect..."),
    Node1 = hd(SortedNodes),
    ok = rpc:call(Node1, riak_core_ring_manager, bloat_ring, []),

    %% Sleep for gossip rounds.
    ct:pal("Sleeping for 50 seconds..."),
    timer:sleep(50000),

    ?SUPPORT:stop(Nodes),

    ok.

membership_test(Config) ->
    Nodes = ?SUPPORT:start(membership_test,
                           Config,
                           [{num_nodes, 3},
                           {partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    %% Verify partisan connection is configured with the correct
    %% membership information.
    ct:pal("Waiting for partisan membership..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_partisan_membership(SortedNodes)),

    %% Ensure we have the right number of connections.
    %% Verify appropriate number of connections.
    ct:pal("Waiting for partisan connections..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections(SortedNodes)),

    ?SUPPORT:stop(Nodes),

    ok.

join_test(Config) ->
    Nodes = ?SUPPORT:start(join_test,
                           Config,
                           [{num_nodes, 3},
                           {partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    ?SUPPORT:stop(Nodes),

    ok.

vnode_test(Config) ->
    Nodes = ?SUPPORT:start(vnode_test,
                           Config,
                           [{partisan_peer_service_manager,
                               partisan_default_peer_service_manager}]),

    SortedNodes = lists:usort([Node || {_Name, Node} <- Nodes]),

    %% Verify partisan connection is configured with the correct
    %% membership information.
    ct:pal("Waiting for partisan membership..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_partisan_membership(SortedNodes)),

    %% Ensure we have the right number of connections.
    %% Verify appropriate number of connections.
    ct:pal("Waiting for partisan connections..."),
    ?assertEqual(ok, ?SUPPORT:wait_until_all_connections(SortedNodes)),

    %% Get the list of nodes.
    ct:pal("Nodes is: ~p", [Nodes]),
    [{_, Node1}, {_, _Node2}, {_, _Node3}] = Nodes,

    %% Attempt to access the vnode request API.
    %% This will test command/3 and command/4 behavior.
    ct:pal("Waiting for response from ping command..."),
    CommandResult = rpc:call(Node1, ?APP, ping, []),
    ?assertEqual(ok, CommandResult),

    %% Attempt to access the vnode request API.
    %% This will test sync_command/3 and sync_command/4 behavior.
    ct:pal("Waiting for response from sync_ping command..."),
    SyncCommandResult = rpc:call(Node1, ?APP, sync_ping, []),
    ?assertMatch({pong, _}, SyncCommandResult),

    %% Attempt to access the vnode request API.
    %% This will test sync_spawn_command/3 and sync_spawn_command/4 behavior.
    ct:pal("Waiting for response from sync_spawn_ping command..."),
    SyncSpawnCommandResult = rpc:call(Node1, ?APP, sync_spawn_ping, []),
    ?assertMatch({pong, _}, SyncSpawnCommandResult),

    %% Attempt to access the vnode request API via FSM.
    ct:pal("Waiting for response from fsm command..."),
    FsmResult = rpc:call(Node1, ?APP, fsm_ping, []),
    ?assertMatch(ok, FsmResult),

    ?SUPPORT:stop(Nodes),

    ok.