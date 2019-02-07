-module(blockchain_keys_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([all/0]).

-export([
    keys_test/1
]).

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
        keys_test
    ].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @public
%% @doc
%% @end
%%--------------------------------------------------------------------
keys_test(_Config) ->
    BaseDir = "data/test_SUITE/keys_test",
    Balance = 5000,

    #{public := PubKey, secret := PrivKey} = libp2p_crypto:generate_keys(ecc_compact),
    SigFun = libp2p_crypto:mk_sig_fun(PrivKey),
    Opts = [
        {key, {PubKey, SigFun}},
        {seed_nodes, []},
        {port, 0},
        {num_consensus_members, 7},
        {base_dir, BaseDir}
    ],
    {ok, Sup} = blockchain_sup:start_link(Opts),
    ?assert(erlang:is_pid(blockchain_swarm:swarm())),

    % Generate fake blockchains (just the keys)
    RandomKeys1 = test_utils:generate_keys(5, ecc_compact) ,
    RandomKeys2 = test_utils:generate_keys(5, ed25519),
    Address = blockchain_swarm:pubkey_bin(),
    ConsensusMembers = [
        {Address, {PubKey, PrivKey, libp2p_crypto:mk_sig_fun(PrivKey)}}
    ] ++ RandomKeys1 ++ RandomKeys2,



    % Create genesis block
    GenPaymentTxs = [blockchain_txn_coinbase_v1:new(Addr, Balance)
                     || {Addr, _} <- ConsensusMembers],
    ConsensusGroupTx = blockchain_txn_consensus_group_v1:new([Addr || {Addr, _} <- ConsensusMembers]),
    Txs = GenPaymentTxs ++ [ConsensusGroupTx],
    GenesisBlock = blockchain_block:new_genesis_block(Txs),
    ok = blockchain_worker:integrate_genesis_block(GenesisBlock),

    Chain = blockchain_worker:blockchain(),
    Swarm = blockchain_swarm:swarm(),
    N = erlang:length(ConsensusMembers),

    ok = test_utils:wait_until(fun() -> {ok, 1} =:= blockchain:height(Chain) end),

    % Test a payment transaction, add a block and check balances
    {Payer, {_, _, PayerSigFun}} = lists:last(ConsensusMembers),
    Recipient = blockchain_swarm:pubkey_bin(),
    Tx = blockchain_txn_payment_v1:new(Payer, Recipient, 2500, 10, 1),
    SignedTx = blockchain_txn_payment_v1:sign(Tx, PayerSigFun),
    Block = test_utils:create_block(ConsensusMembers, [SignedTx]),
    _ = blockchain_gossip_handler:add_block(Swarm, Block, Chain, N, self()),

    ?assertEqual({ok, blockchain_block:hash_block(Block)}, blockchain:head_hash(Chain)),
    ?assertEqual({ok, Block}, blockchain:head_block(Chain)),
    ?assertEqual({ok, 2}, blockchain:height(Chain)),

    ?assertEqual({ok, Block}, blockchain:get_block(2, Chain)),

    Ledger = blockchain:ledger(Chain),
    {ok, NewEntry0} = blockchain_ledger_v1:find_entry(Recipient, Ledger),
    ?assertEqual(Balance + 2500, blockchain_ledger_entry_v1:balance(NewEntry0)),

    {ok, NewEntry1} = blockchain_ledger_v1:find_entry(Payer, Ledger),
    ?assertEqual(Balance - 2510, blockchain_ledger_entry_v1:balance(NewEntry1)),

    case erlang:is_process_alive(Sup) of
        true ->
            true = erlang:exit(Sup, normal),
            ok = test_utils:wait_until(fun() -> false =:= erlang:is_process_alive(Sup) end);
        false ->
            ok
    end.
