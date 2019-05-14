-module(blockchain_data_credits_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).

-export([
    basic_test/1
]).

-include("blockchain.hrl").

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @public
%% @doc
%%   Running tests for this suite
%% @end
%%--------------------------------------------------------------------
all() ->
    [
        basic_test
    ].

%%--------------------------------------------------------------------
%% TEST CASE SETUP
%%--------------------------------------------------------------------

init_per_testcase(_TestCase, Config0) ->
    blockchain_ct_utils:init_per_testcase(_TestCase, [{"T", 3}, {"N", 1}|Config0]).

%%--------------------------------------------------------------------
%% TEST CASE TEARDOWN
%%--------------------------------------------------------------------
end_per_testcase(_TestCase, Config) ->
    blockchain_ct_utils:end_per_testcase(_TestCase, Config).

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @public
%% @doc
%% @end
%%--------------------------------------------------------------------
basic_test(Config) ->
    [RouterNode, GatewayNode1, GatewayNode2] = proplists:get_value(nodes, Config, []),

    ct:pal("RouterNode: ~p GatewayNode1: ~p GatewayNode2: ~p", [RouterNode, GatewayNode1, GatewayNode2]),

    % Simulate Atom burn to Data Credits
    Keys = libp2p_crypto:generate_keys(ecc_compact),
    ok = ct_rpc:call(RouterNode, blockchain_data_credits_servers_monitor, channel_server, [Keys, 100]),

    % Check that 100 credits was added
    #{public := PubKey} = Keys,
    PubKeyBin = libp2p_crypto:pubkey_to_bin(PubKey),
    {ok, ChannelServer} = ct_rpc:call(RouterNode, blockchain_data_credits_servers_monitor, channel_server, [PubKeyBin]),
    ?assertEqual({ok, 100}, ct_rpc:call(RouterNode, blockchain_data_credits_channel_server, credits, [ChannelServer])),

    % Make a payment request from GatewayNode1 of 10 credits
    RouterPubKeyBin = ct_rpc:call(RouterNode, blockchain_swarm, pubkey_bin, []),
    ok = ct_rpc:call(GatewayNode1, blockchain_data_credits_clients_monitor, payment_req, [RouterPubKeyBin, 10]),

    % Checking that we have 90 credits now
    ok = blockchain_ct_utils:wait_until(fun() ->
        {ok, 90} == ct_rpc:call(RouterNode, blockchain_data_credits_channel_server, credits, [ChannelServer])
    end, 10, 500),

    % Make another DIRECT payment request from RouterNode of 10 credits (we use the PubKeyBin as an ID)
    ok = ct_rpc:call(RouterNode, blockchain_data_credits_servers_monitor, payment_req, [PubKeyBin, RouterPubKeyBin, 10]),

    % Checking that we have 80 credits now
    ok = blockchain_ct_utils:wait_until(fun() ->
        {ok, 80} == ct_rpc:call(RouterNode, blockchain_data_credits_channel_server, credits, [ChannelServer])
    end, 10, 500),

    % Make a payment request from GatewayNode2 of 10 credits
    ok = ct_rpc:call(GatewayNode2, blockchain_data_credits_clients_monitor, payment_req, [RouterPubKeyBin, 10]),

    % Checking that we have 70 credits now
    ok = blockchain_ct_utils:wait_until(fun() ->
        {ok, 70} == ct_rpc:call(RouterNode, blockchain_data_credits_channel_server, credits, [ChannelServer])
    end, 10, 500),

    ok.