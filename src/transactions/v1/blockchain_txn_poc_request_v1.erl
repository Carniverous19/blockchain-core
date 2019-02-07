%%%-------------------------------------------------------------------
%% @doc
%% == Blockchain Transaction Create Proof of Coverage Request ==
%% Submitted by a gateway who wishes to initiate a PoC Challenge
%%%-------------------------------------------------------------------
-module(blockchain_txn_poc_request_v1).

-behavior(blockchain_txn).

-include("pb/blockchain_txn_poc_request_v1_pb.hrl").

-export([
    new/3,
    gateway/1,
    hash/1,
    onion/1,
    signature/1,
    fee/1,
    sign/2,
    is_valid/1,
    absorb/2
]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-type txn_poc_request() :: #blockchain_txn_poc_request_v1_pb{}.
-export_type([txn_poc_request/0]).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec new(libp2p_crypto:pubkey_bin(), binary(),  binary()) -> txn_poc_request().
new(Gateway, Hash, Onion) ->
    #blockchain_txn_poc_request_v1_pb{
       gateway=Gateway,
       hash=Hash,
       onion=Onion,
       signature = <<>>
      }.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec gateway(txn_poc_request()) -> libp2p_crypto:pubkey_bin().
gateway(Txn) ->
    Txn#blockchain_txn_poc_request_v1_pb.gateway.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec hash(txn_poc_request()) -> blockchain_txn:hash().
hash(Txn) ->
    Txn#blockchain_txn_poc_request_v1_pb.hash.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec onion(txn_poc_request()) -> binary().
onion(Txn) ->
    Txn#blockchain_txn_poc_request_v1_pb.onion.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec signature(txn_poc_request()) -> binary().
signature(Txn) ->
    Txn#blockchain_txn_poc_request_v1_pb.signature.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec fee(txn_poc_request()) -> non_neg_integer().
fee(Txn) ->
    Txn#blockchain_txn_poc_request_v1_pb.fee.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec sign(txn_poc_request(), libp2p_crypto:sig_fun()) -> txn_poc_request().
sign(Txn, SigFun) ->
    EncodedTxn = blockchain_txn_poc_request_v1_pb:encode_msg(Txn),
    Txn#blockchain_txn_poc_request_v1_pb{signature=SigFun(EncodedTxn)}.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec is_valid(txn_poc_request()) -> boolean().
is_valid(Txn=#blockchain_txn_poc_request_v1_pb{gateway=Gateway, signature=Signature}) ->
    PubKey = libp2p_crypto:bin_to_pubkey(Gateway),
    BaseTxn = Txn#blockchain_txn_poc_request_v1_pb{signature = <<>>},
    EncodedTxn = blockchain_txn_poc_request_v1_pb:encode_msg(BaseTxn),
    libp2p_crypto:verify(EncodedTxn, Signature, PubKey).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec absorb(txn_poc_request(), blockchain_ledger_v1:ledger()) -> ok | {error, any()}.
absorb(Txn, Ledger) ->
    case ?MODULE:is_valid(Txn) of
        true ->
            Gateway = ?MODULE:gateway(Txn),
            Hash = ?MODULE:hash(Txn),
            Onion = ?MODULE:onion(Txn),
            blockchain_ledger_v1:request_poc(Gateway, {Hash, Onion}, Ledger);
        false ->
            {error, bad_signature}
    end.

%% ------------------------------------------------------------------
%% EUNIT Tests
%% ------------------------------------------------------------------
-ifdef(TEST).

new_test() ->
    Tx = #blockchain_txn_poc_request_v1_pb{
        gateway= <<"gateway_address">>,
        hash= <<"hash">>,
        onion = <<"onion">>,
        signature= <<>>
    },
    ?assertEqual(Tx, new(<<"gateway_address">>, <<"hash">>, <<"onion">>)).

hash_test() ->
    Tx = new(<<"gateway_address">>, <<"hash">>, <<"onion">>),
    ?assertEqual(<<"hash">>, hash(Tx)).

onion_test() ->
    Tx = new(<<"gateway_address">>, <<"hash">>, <<"onion">>),
    ?assertEqual(<<"onion">>, onion(Tx)).

gateway_test() ->
    Tx = new(<<"gateway_address">>, <<"hash">>, <<"onion">>),
    ?assertEqual(<<"gateway_address">>, gateway(Tx)).

signature_test() ->
    Tx = new(<<"gateway_address">>, <<"hash">>, <<"onion">>),
    ?assertEqual(<<>>, signature(Tx)).

sign_test() ->
    #{public := PubKey, secret := PrivKey} = libp2p_crypto:generate_keys(ecc_compact),
    Tx0 = new(<<"gateway_address">>, <<"hash">>, <<"onion">>),
    SigFun = libp2p_crypto:mk_sig_fun(PrivKey),
    Tx1 = sign(Tx0, SigFun),
    Sig1 = signature(Tx1),

    EncodedTx1 = blockchain_txn_poc_request_v1_pb:encode_msg(Tx1#blockchain_txn_poc_request_v1_pb{signature = <<>>}),
    ?assert(libp2p_crypto:verify(EncodedTx1, Sig1, PubKey)).


-endif.