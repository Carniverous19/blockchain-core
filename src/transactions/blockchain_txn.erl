%%%-------------------------------------------------------------------
%% @doc
%% == Blockchain Transaction Behavior ==
%% @end
%%%-------------------------------------------------------------------
-module(blockchain_txn).

%% The union type of all transactions is defined in
%% blockchain_txn.proto. The txn() type below should reflec that
%% union.
-include("pb/blockchain_txn_pb.hrl").

-type hash() :: <<_:256>>. %% SHA256 digest
-type txn() :: blockchain_txn_add_gateway_v1:txn_add_gateway()
             | blockchain_txn_assert_location_v1:txn_assert_location()
             | blockchain_txn_coinbase_v1:txn_coinbase()
             | blockchain_txn_security_coinbase_v1:txn_security_coinbase()
             | blockchain_txn_consensus_group_v1:txn_consensus_group()
             | blockchain_txn_gen_gateway_v1:txn_genesis_gateway()
             | blockchain_txn_payment_v1:txn_payment()
             | blockchain_txn_security_exchange_v1:txn_security_exchange()
             | blockchain_txn_oui_v1:txn_oui()
             | blockchain_txn_routing_v1:txn_routing()
             | blockchain_txn_create_htlc_v1:txn_create_htlc()
             | blockchain_txn_redeem_htlc_v1:txn_redeem_htlc()
             | blockchain_txn_poc_request_v1:txn_poc_request()
             | blockchain_txn_poc_receipts_v1:txn_poc_receipts()
             | blockchain_txn_vars_v1:txn_vars()
             | blockchain_txn_rewards_v1:txn_rewards()
             | blockchain_txn_token_burn_v1:txn_token_burn()
             | blockchain_txn_dc_coinbase_v1:txn_dc_coinbase()
             | blockchain_txn_token_burn_exchange_rate_v1:txn_token_burn_exchange_rate().

-type txns() :: [txn()].
-export_type([hash/0, txn/0, txns/0]).

-callback fee(txn()) -> non_neg_integer().
-callback hash(State::any()) -> hash().
-callback sign(txn(), libp2p_crypto:sig_fun()) -> txn().
-callback is_valid(txn(), blockchain:blockchain()) -> ok | {error, any()}.
-callback absorb(txn(),  blockchain:blockchain()) -> ok | {error, any()}.
-callback rescue_absorb(txn(),  blockchain:blockchain()) -> ok | {error, any()}.

-optional_callbacks([rescue_absorb/2]).

-export([
    hash/1,
    validate/2, validate/3,
    absorb/2,
    sign/2,
    absorb_and_commit/3, absorb_and_commit/4,
    unvalidated_absorb_and_commit/4,
    absorb_block/2, absorb_block/3,
    sort/2,
    type/1,
    serialize/1,
    deserialize/1,
    wrap_txn/1,
    unwrap_txn/1,
    is_valid/2
]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(BLOCK_DELAY, 50).
-define(ORDER, [
    {blockchain_txn_rewards_v1, 1},
    {blockchain_txn_vars_v1, 2},
    {blockchain_txn_consensus_group_v1, 3},
    {blockchain_txn_coinbase_v1, 4},
    {blockchain_txn_security_coinbase_v1, 5},
    {blockchain_txn_dc_coinbase_v1, 6},
    {blockchain_txn_gen_gateway_v1, 7},
    {blockchain_txn_token_burn_exchange_rate_v1, 8},
    {blockchain_txn_oui_v1, 9},
    {blockchain_txn_routing_v1, 10},
    {blockchain_txn_create_htlc_v1, 11},
    {blockchain_txn_payment_v1, 12},
    {blockchain_txn_security_exchange_v1, 13},
    {blockchain_txn_add_gateway_v1, 14},
    {blockchain_txn_assert_location_v1, 15},
    {blockchain_txn_redeem_htlc_v1, 16},
    {blockchain_txn_poc_request_v1, 17},
    {blockchain_txn_poc_receipts_v1, 18}
]).

hash(Txn) ->
    (type(Txn)):hash(Txn).

sign(Txn, SigFun) ->
    (type(Txn)):sign(Txn, SigFun).

serialize(Txn) ->
    blockchain_txn_pb:encode_msg(wrap_txn(Txn)).

deserialize(Bin) ->
    unwrap_txn(blockchain_txn_pb:decode_msg(Bin, blockchain_txn_pb)).

%% Since the proto file for the transaction union includes the
%% definitions of the underlying protobufs for each transaction we
%% break encapsulation here and do no tuse the txn modules themselves.
-spec wrap_txn(blockchain_txn:txn()) -> #blockchain_txn_pb{}.
wrap_txn(#blockchain_txn_assert_location_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={assert_location, Txn}};
wrap_txn(#blockchain_txn_payment_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={payment, Txn}};
wrap_txn(#blockchain_txn_security_exchange_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={security_exchange, Txn}};
wrap_txn(#blockchain_txn_create_htlc_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={create_htlc, Txn}};
wrap_txn(#blockchain_txn_redeem_htlc_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={redeem_htlc, Txn}};
wrap_txn(#blockchain_txn_add_gateway_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={add_gateway, Txn}};
wrap_txn(#blockchain_txn_coinbase_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={coinbase, Txn}};
wrap_txn(#blockchain_txn_security_coinbase_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={security_coinbase, Txn}};
wrap_txn(#blockchain_txn_consensus_group_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={consensus_group, Txn}};
wrap_txn(#blockchain_txn_poc_request_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={poc_request, Txn}};
wrap_txn(#blockchain_txn_poc_receipts_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={poc_receipts, Txn}};
wrap_txn(#blockchain_txn_gen_gateway_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={gen_gateway, Txn}};
wrap_txn(#blockchain_txn_oui_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={oui, Txn}};
wrap_txn(#blockchain_txn_routing_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={routing, Txn}};
wrap_txn(#blockchain_txn_vars_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={vars, Txn}};
wrap_txn(#blockchain_txn_rewards_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={rewards, Txn}};
wrap_txn(#blockchain_txn_token_burn_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={token_burn, Txn}};
wrap_txn(#blockchain_txn_dc_coinbase_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={dc_coinbase, Txn}};
wrap_txn(#blockchain_txn_token_burn_exchange_rate_v1_pb{}=Txn) ->
    #blockchain_txn_pb{txn={token_burn_exchange_rate, Txn}}.

-spec unwrap_txn(#blockchain_txn_pb{}) -> blockchain_txn:txn().
unwrap_txn(#blockchain_txn_pb{txn={_, Txn}}) ->
    Txn.

%%--------------------------------------------------------------------
%% @doc
%% Called in the miner
%% @end
%%--------------------------------------------------------------------
-spec validate(txns(), blockchain:blockchain()) -> {blockchain_txn:txns(), blockchain_txn:txns()}.
validate(Transactions, Chain) ->
    validate(Transactions, Chain, false).

-spec validate(txns(), blockchain:blockchain(), boolean()) ->
                      {blockchain_txn:txns(), blockchain_txn:txns()}.
validate(Transactions, _Chain, true) ->
    {Transactions, []};
validate(Transactions, Chain0, false) ->
    Ledger0 = blockchain:ledger(Chain0),
    Ledger1 = blockchain_ledger_v1:new_context(Ledger0),
    Chain1 = blockchain:ledger(Ledger1, Chain0),
    validate(Transactions, [], [], undefined, [], Chain1).

validate([], Valid, Invalid, PType, PBuf, Chain) ->
    {Valid1, Invalid1} =
        case PType of
            undefined ->
                {Valid, Invalid};
            _ ->
                Res = blockchain_utils:pmap(
                        fun(T) ->
                                Type = ?MODULE:type(T),
                                {T, catch Type:is_valid(T, Chain)}
                        end, lists:reverse(PBuf)),
                separate_res(Res, Chain, Valid, Invalid)
        end,
    Ledger = blockchain:ledger(Chain),
    blockchain_ledger_v1:delete_context(Ledger),
    lager:info("valid: ~p, invalid: ~p", [types(Valid1), types(Invalid1)]),
    {lists:reverse(Valid1), Invalid1};
validate([Txn | Tail] = Txns, Valid, Invalid, PType, PBuf, Chain) ->
    Type = ?MODULE:type(Txn),
    case Type of
        blockchain_txn_poc_request_v1 when PType == undefined orelse PType == Type ->
            validate(Tail, Valid, Invalid, Type, [Txn | PBuf], Chain);
        blockchain_txn_poc_receipts_v1 when PType == undefined orelse PType == Type ->
            validate(Tail, Valid, Invalid, Type, [Txn | PBuf], Chain);
        _Else when PType == undefined ->
            case catch Type:is_valid(Txn, Chain) of
                ok ->
                    case ?MODULE:absorb(Txn, Chain) of
                        ok ->
                            validate(Tail, [Txn|Valid], Invalid, PType, PBuf, Chain);
                        {error, _Reason} ->
                            lager:error("invalid txn while absorbing ~p : ~p / ~p", [Type, _Reason, Txn]),
                            validate(Tail, Valid, [Txn | Invalid], PType, PBuf, Chain)
                    end;
                {error, {bad_nonce, {_NonceType, Nonce, LedgerNonce}}} when Nonce > LedgerNonce + 1 ->
                    %% we don't have enough context to decide if this transaction is valid yet, keep it
                    %% but don't include it in the block (so it stays in the buffer)
                    validate(Tail, Valid, Invalid, PType, PBuf, Chain);
                Error ->
                    lager:error("invalid txn ~p : ~p / ~p", [Type, Error, Txn]),
                    %% any other error means we drop it
                    validate(Tail, Valid, [Txn | Invalid], PType, PBuf, Chain)
            end;
        _Else ->
            Res = blockchain_utils:pmap(
                    fun(T) ->
                            Ty = ?MODULE:type(T),
                            {T, catch Ty:is_valid(T, Chain)}
                    end, lists:reverse(PBuf)),
            {Valid1, Invalid1} = separate_res(Res, Chain, Valid, Invalid),
            validate(Txns, Valid1, Invalid1, undefined, [], Chain)
    end.

separate_res([], _Chain, V, I) ->
    {V, I};
separate_res([{T, ok} | Rest], Chain, V, I) ->
    case ?MODULE:absorb(T, Chain) of
        ok ->
            separate_res(Rest, Chain, [T|V], I);
        {error, _Reason} ->
            lager:error("invalid txn while absorbing ~p : ~p / ~p", [type(T), _Reason, T]),
            separate_res(Rest, Chain, V, [T | I])
    end;
separate_res([{T, Err} | Rest], Chain, V, I) ->
    case Err of
        {error, {bad_nonce, {_NonceType, Nonce, LedgerNonce}}} when Nonce > LedgerNonce + 1 ->
            separate_res(Rest, Chain, V, I);
        Error ->
            lager:error("invalid txn ~p : ~p / ~p", [type(T), Error, T]),
            %% any other error means we drop it
            separate_res(Rest, Chain, V, [T | I])
    end.


types(L) ->
    lists:map(fun type/1, L).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec absorb_and_commit(blockchain_block:block(), blockchain:blockchain(), fun()) ->
                               ok | {error, any()}.
absorb_and_commit(Block, Chain0, BeforeCommit) ->
    absorb_and_commit(Block, Chain0, BeforeCommit, false).

-spec absorb_and_commit(blockchain_block:block(), blockchain:blockchain(), fun(), boolean()) ->
                               ok | {error, any()}.
absorb_and_commit(Block, Chain0, BeforeCommit, Rescue) ->
    Ledger0 = blockchain:ledger(Chain0),
    Ledger1 = blockchain_ledger_v1:new_context(Ledger0),
    Chain1 = blockchain:ledger(Ledger1, Chain0),
    Transactions0 = blockchain_block:transactions(Block),
    Transactions = lists:sort(fun sort/2, (Transactions0)),
    case ?MODULE:validate(Transactions, Chain1, Rescue) of
        {_ValidTxns, []} ->
            case ?MODULE:absorb_block(Block, Rescue, Chain1) of
                {ok, Chain2} ->
                    Ledger2 = blockchain:ledger(Chain2),
                    case BeforeCommit() of
                         ok ->
                            ok = blockchain_ledger_v1:commit_context(Ledger2),
                            absorb_delayed(Block, Chain0);
                       Any ->
                            Any
                    end;
                Error ->
                    blockchain_ledger_v1:delete_context(Ledger1),
                    Error
            end;
        {_ValidTxns, InvalidTxns} ->
            lager:error("found invalid transactions: ~p", [InvalidTxns]),
            {error, invalid_txns}
    end.

-spec unvalidated_absorb_and_commit(blockchain_block:block(), blockchain:blockchain(), fun(), boolean()) ->
                               ok | {error, any()}.
unvalidated_absorb_and_commit(Block, Chain0, BeforeCommit, Rescue) ->
    Ledger0 = blockchain:ledger(Chain0),
    Ledger1 = blockchain_ledger_v1:new_context(Ledger0),
    Chain1 = blockchain:ledger(Ledger1, Chain0),
    case ?MODULE:absorb_block(Block, Rescue, Chain1) of
        {ok, Chain2} ->
            Ledger2 = blockchain:ledger(Chain2),
            case BeforeCommit() of
                ok ->
                    ok = blockchain_ledger_v1:commit_context(Ledger2),
                    absorb_delayed(Block, Chain0);
                Any ->
                    Any
            end;
        Error ->
            blockchain_ledger_v1:delete_context(Ledger1),
            Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec absorb_block(blockchain_block:block(), blockchain:blockchain()) ->
                          {ok, blockchain:blockchain()} | {error, any()}.
absorb_block(Block, Chain) ->
    absorb_block(Block, false, Chain).

-spec absorb_block(blockchain_block:block(), boolean(), blockchain:blockchain()) ->
                          {ok, blockchain:blockchain()} | {error, any()}.
absorb_block(Block, Rescue, Chain) ->
    Ledger = blockchain:ledger(Chain),
    Transactions0 = blockchain_block:transactions(Block),
    Transactions = lists:sort(fun sort/2, (Transactions0)),
    Height = blockchain_block:height(Block),
    case absorb_txns(Transactions, Rescue, Chain) of
        ok ->
            ok = blockchain_ledger_v1:update_transaction_fee(Ledger),
            ok = blockchain_ledger_v1:increment_height(Block, Ledger),
            ok = blockchain_ledger_v1:process_delayed_txns(Height, Ledger, Chain),
            {ok, Chain};
        Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec absorb(txn(),blockchain:blockchain()) -> ok | {error, any()}.
absorb(Txn, Chain) ->
    Type = ?MODULE:type(Txn),
    try Type:absorb(Txn, Chain) of
        {error, _Reason}=Error ->
            lager:info("failed to absorb ~p ~p", [Type, _Reason]),
            Error;
        ok -> ok
    catch
        What:Why:Stack ->
            lager:warning("crash during absorb: ~p ~p", [Why, Stack]),
            {error, {Type, What, {Why, Stack}}}
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec is_valid(txn(), blockchain:blockchain()) -> ok | {error, any()}.
is_valid(Txn, Chain) ->
    Type = ?MODULE:type(Txn),
    try Type:is_valid(Txn, Chain) of
        Res ->
            Res
    catch
        What:Why:Stack ->
            lager:warning("crash during validation: ~p ~p", [Why, Stack]),
            {error, {Type, What, {Why, Stack}}}
end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec sort(txn(), txn()) -> boolean().
sort(TxnA, TxnB) ->
    {type_order(TxnA), actor(TxnA), nonce(TxnA)} =< {type_order(TxnB), actor(TxnB), nonce(TxnB)}.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec type(txn()) -> atom().
type(#blockchain_txn_assert_location_v1_pb{}) ->
    blockchain_txn_assert_location_v1;
type(#blockchain_txn_payment_v1_pb{}) ->
    blockchain_txn_payment_v1;
type(#blockchain_txn_security_exchange_v1_pb{}) ->
    blockchain_txn_security_exchange_v1;
type(#blockchain_txn_create_htlc_v1_pb{}) ->
    blockchain_txn_create_htlc_v1;
type(#blockchain_txn_redeem_htlc_v1_pb{}) ->
    blockchain_txn_redeem_htlc_v1;
type(#blockchain_txn_add_gateway_v1_pb{}) ->
    blockchain_txn_add_gateway_v1;
type(#blockchain_txn_coinbase_v1_pb{}) ->
    blockchain_txn_coinbase_v1;
type(#blockchain_txn_security_coinbase_v1_pb{}) ->
    blockchain_txn_security_coinbase_v1;
type(#blockchain_txn_consensus_group_v1_pb{}) ->
    blockchain_txn_consensus_group_v1;
type(#blockchain_txn_poc_request_v1_pb{}) ->
    blockchain_txn_poc_request_v1;
type(#blockchain_txn_poc_receipts_v1_pb{}) ->
    blockchain_txn_poc_receipts_v1;
type(#blockchain_txn_gen_gateway_v1_pb{}) ->
    blockchain_txn_gen_gateway_v1;
type(#blockchain_txn_oui_v1_pb{}) ->
    blockchain_txn_oui_v1;
type(#blockchain_txn_routing_v1_pb{}) ->
    blockchain_txn_routing_v1;
type(#blockchain_txn_vars_v1_pb{}) ->
    blockchain_txn_vars_v1;
type(#blockchain_txn_rewards_v1_pb{}) ->
    blockchain_txn_rewards_v1;
type(#blockchain_txn_token_burn_v1_pb{}) ->
    blockchain_txn_token_burn_v1;
type(#blockchain_txn_dc_coinbase_v1_pb{}) ->
    blockchain_txn_dc_coinbase_v1;
type(#blockchain_txn_token_burn_exchange_rate_v1_pb{}) ->
    blockchain_txn_token_burn_exchange_rate_v1.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec type_order(txn()) -> non_neg_integer().
type_order(Txn) ->
    Type = type(Txn),
    case lists:keyfind(Type, 1, ?ORDER) of
        {Type, Index} -> Index;
        false -> erlang:length(?ORDER)
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec absorb_txns(txns(), boolean(), blockchain:blockchain()) ->
                         ok | {error, any()}.
absorb_txns([], _Rescue, _Chain) ->
    ok;
absorb_txns([Txn|Txns], Rescue, Chain) ->
    Type = ?MODULE:type(Txn),
    case Rescue andalso
        erlang:function_exported(Type, rescue_absorb, 2) of
        true ->
            case Type:rescue_absorb(Txn, Chain) of
                ok -> absorb_txns(Txns, Rescue, Chain);
                {error, _} = E -> E
            end;
        false ->
            case ?MODULE:absorb(Txn, Chain) of
                {error, _Reason}=Error -> Error;
                ok -> absorb_txns(Txns, Rescue, Chain)
            end
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec absorb_delayed(blockchain_block:block(), blockchain:blockchain()) -> ok | {error, any()}.
absorb_delayed(Block0, Chain0) ->
    Ledger0 = blockchain:ledger(Chain0),
    DelayedLedger0 = blockchain_ledger_v1:mode(delayed, Ledger0),
    DelayedLedger1 = blockchain_ledger_v1:new_context(DelayedLedger0),
    Chain1 = blockchain:ledger(DelayedLedger1, Chain0),
    case blockchain_ledger_v1:current_height(Ledger0) of
        % This is so it absorbs genesis
        {ok, H} when H < 2 ->
            absorb_delayed_(Block0, Chain1);
        {ok, CurrentHeight} ->
            {ok, DelayedHeight} = blockchain_ledger_v1:current_height(DelayedLedger1),
            % Then we absorb if minimum limit is there
            case CurrentHeight - DelayedHeight > ?BLOCK_DELAY of
                false ->
                    ok;
                true ->
                    {ok, Block1} = blockchain:get_block(DelayedHeight+1, Chain0),
                    absorb_delayed_(Block1, Chain1)
            end;
        _Any ->
            _Any
    end.

absorb_delayed_(Block, Chain0) ->
    case ?MODULE:absorb_block(Block, Chain0) of
        {ok, Chain1} ->
            Ledger = blockchain:ledger(Chain1),
            ok = blockchain_ledger_v1:commit_context(Ledger);
        Error ->
            Ledger = blockchain:ledger(Chain0),
            blockchain_ledger_v1:delete_context(Ledger),
            Error
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec nonce(txn()) -> integer().
nonce(Txn) ->
    case ?MODULE:type(Txn) of
        blockchain_txn_assert_location_v1 ->
            blockchain_txn_assert_location_v1:nonce(Txn);
        blockchain_txn_payment_v1 ->
            blockchain_txn_payment_v1:nonce(Txn);
        blockchain_txn_security_exchange_v1 ->
            blockchain_txn_security_exchange_v1:nonce(Txn);
        _ ->
            -1 %% other transactions sort first
    end.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec actor(txn()) -> libp2p_crypto:pubkey_bin() | <<>>.
actor(Txn) ->
    case ?MODULE:type(Txn) of
        blockchain_txn_assert_location_v1 ->
            blockchain_txn_assert_location_v1:gateway(Txn);
        blockchain_txn_payment_v1 ->
            blockchain_txn_payment_v1:payer(Txn);
        blockchain_txn_security_exchange_v1 ->
            blockchain_txn_security_exchange_v1:payer(Txn);
        blockchain_txn_create_htlc_v1 ->
            blockchain_txn_create_htlc_v1:payer(Txn);
        blockchain_txn_redeem_htlc_v1 ->
            blockchain_txn_redeem_htlc_v1:payee(Txn);
        blockchain_txn_poc_request_v1 ->
            blockchain_txn_poc_request_v1:challenger(Txn);
        blockchain_txn_add_gateway_v1 ->
            blockchain_txn_add_gateway_v1:owner(Txn);
        blockchain_txn_coinbase_v1 ->
            blockchain_txn_coinbase_v1:payee(Txn);
        blockchain_txn_security_coinbase_v1 ->
            blockchain_txn_security_coinbase_v1:payee(Txn);
        blockchain_txn_poc_receipts_v1 ->
            blockchain_txn_poc_receipts_v1:challenger(Txn);
        blockchain_txn_oui_v1 ->
            blockchain_txn_oui_v1:owner(Txn);
        blockchain_txn_routing_v1 ->
            blockchain_txn_routing_v1:owner(Txn);
        blockchain_txn_token_burn_v1 ->
            blockchain_txn_token_burn_v1:payer(Txn);
        blockchain_txn_dc_coinbase_v1 ->
            blockchain_txn_dc_coinbase_v1:payee(Txn);
        _ ->
            <<>>
    end.

%% ------------------------------------------------------------------
%% EUNIT Tests
%% ------------------------------------------------------------------
-ifdef(TEST).

-endif.
