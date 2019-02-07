%%%-------------------------------------------------------------------
%% @doc
%% == Blockchain Transaction OUI ==
%% @end
%%%-------------------------------------------------------------------
-module(blockchain_txn_oui_v1).

-behavior(blockchain_txn).

-include("pb/blockchain_txn_oui_v1_pb.hrl").

-export([
    new/3,
    hash/1,
    oui/1,
    fee/1,
    owner/1,
    signature/1,
    sign/2,
    is_valid/1,
    absorb/2
]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-type txn_oui() :: #blockchain_txn_oui_v1_pb{}.
-export_type([txn_oui/0]).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec new(binary(), non_neg_integer(), libp2p_crypto:pubkey_bin()) -> txn_oui().
new(OUI, Fee, Owner) ->
    #blockchain_txn_oui_v1_pb{
       oui=OUI,
       fee=Fee,
       owner=Owner,
       signature= <<>>
      }.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec hash(txn_oui()) -> blockchain_txn:hash().
hash(Txn) ->
    BaseTxn = Txn#blockchain_txn_oui_v1_pb{signature = <<>>},
    EncodedTxn = blockchain_txn_oui_v1_pb:encode_msg(BaseTxn),
    crypto:hash(sha256, EncodedTxn).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec oui(txn_oui()) -> binary().
oui(Txn) ->
    Txn#blockchain_txn_oui_v1_pb.oui.
%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec fee(txn_oui()) -> non_neg_integer().
fee(Txn) ->
    Txn#blockchain_txn_oui_v1_pb.fee.
%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec owner(txn_oui()) -> libp2p_crypto:pubkey_bin().
owner(Txn) ->
    Txn#blockchain_txn_oui_v1_pb.owner.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec signature(txn_oui()) -> binary().
signature(Txn) ->
    Txn#blockchain_txn_oui_v1_pb.signature.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec sign(txn_oui(), libp2p_crypto:sig_fun()) -> txn_oui().
sign(Txn, SigFun) ->
    EncodedTxn = blockchain_txn_oui_v1_pb:encode_msg(Txn),
    Txn#blockchain_txn_oui_v1_pb{signature=SigFun(EncodedTxn)}.


%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec is_valid(txn_oui()) -> boolean().
is_valid(Txn=#blockchain_txn_oui_v1_pb{owner=Owner, signature=Signature}) ->
    PubKey = libp2p_crypto:bin_to_pubkey(Owner),
    BaseTxn = Txn#blockchain_txn_oui_v1_pb{signature = <<>>},
    EncodedTxn = blockchain_txn_oui_v1_pb:encode_msg(BaseTxn),
    libp2p_crypto:verify(EncodedTxn, Signature, PubKey).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec absorb(txn_oui(), blockchain_ledger_v1:ledger()) -> ok | {error, any()}.
absorb(Txn, Ledger) ->
    case ?MODULE:is_valid(Txn) of
        false ->
            {error, invalid_transaction};
        true ->
            Fee = ?MODULE:fee(Txn),
            Owner = ?MODULE:owner(Txn),
            case blockchain_ledger_v1:find_entry(Owner, Ledger) of
                {error, _}=Error ->
                    Error;
                {ok, LastEntry} ->
                    Nonce = blockchain_ledger_entry_v1:nonce(LastEntry) + 1,
                    blockchain_ledger_v1:debit_account(Owner, Fee, Nonce, Ledger)
            end
    end.


%% ------------------------------------------------------------------
%% EUNIT Tests
%% ------------------------------------------------------------------
-ifdef(TEST).

new_test() ->
    Tx = #blockchain_txn_oui_v1_pb{
        oui= <<"0">>,
        fee=1,
        owner= <<"owner">>,
        signature= <<>>
    },
    ?assertEqual(Tx, new(<<"0">>, 1, <<"owner">>)).

oui_test() ->
    Tx = new(<<"0">>, 1, <<"owner">>),
    ?assertEqual(<<"0">>, oui(Tx)).

fee_test() ->
    Tx = new(<<"0">>, 1, <<"owner">>),
    ?assertEqual(1, fee(Tx)).

owner_test() ->
    Tx = new(<<"0">>, 1, <<"owner">>),
    ?assertEqual(<<"owner">>, owner(Tx)).

signature_test() ->
    Tx = new(<<"0">>, 1, <<"owner">>),
    ?assertEqual(<<>>, signature(Tx)).

sign_test() ->
    #{public := PubKey, secret := PrivKey} = libp2p_crypto:generate_keys(ecc_compact),
    Tx0 = new(<<"0">>, 1, <<"owner">>),
    SigFun = libp2p_crypto:mk_sig_fun(PrivKey),
    Tx1 = sign(Tx0, SigFun),
    Sig1 = signature(Tx1),
    EncodedTx1 = blockchain_txn_oui_v1_pb:encode_msg(Tx1#blockchain_txn_oui_v1_pb{signature = <<>>}),
    ?assert(libp2p_crypto:verify(EncodedTx1, Sig1, PubKey)).

is_valid_test() ->
    #{public := PubKey, secret := PrivKey} = libp2p_crypto:generate_keys(ecc_compact),
    Owner1 = libp2p_crypto:pubkey_to_bin(PubKey),
    Tx0 = new(<<"0">>, 1, Owner1),
    SigFun = libp2p_crypto:mk_sig_fun(PrivKey),
    Tx1 = sign(Tx0, SigFun),
    ?assert(is_valid(Tx1)),
    #{public := PubKey2} = libp2p_crypto:generate_keys(ecc_compact),
    Owner2 = libp2p_crypto:pubkey_to_bin(PubKey2),
    Tx2 = new(<<"0">>, 1, Owner2),
    Tx3 = sign(Tx2, SigFun),
    ?assertNot(is_valid(Tx3)).

-endif.