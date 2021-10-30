%%% ===========================================================================
%%% Value contract validation.
%%% ===========================================================================
-module(blockchain_contracts).

-export_type([
    key/0,
    val/0,
    size/0,
    txn_type/0,
    quantifier/0,
    forall/0,
    exists/0,
    either/0,
    contract/0,
    spec/0,
    failure/0,
    failure_bin/0,
    failure_int/0,
    failure_list/0,
    failure_txn/0,
    result/0
]).

-export([
     check/1,
     check/2,
     check_with_defined/1,
     is_satisfied/2,
     are_satisfied/1
]).

-type key() :: atom().
-type val() :: term().

%% TODO Need better name than "size"
%% - "range" is a good one, but then "exact" doesn't seem to fit in...
%% - "magnitude" - too clever?
%% - ...
-type size(A) ::
      any
    | {exact, A}
    | {range, Min :: A, Max :: A}
    | {min, A}
    | {max, A}
    .

-type size() ::
    size(integer()).

-type txn_type() ::
    any | {type, atom()}.

-type forall() :: forall | '∀'.  % and  ALL contracts must be satisfied
-type exists() :: exists | '∃'.  % or   AT LEAST ONE contract must be satisfied
-type either() :: either | '∃!'. % xor  EXACTLY ONE contract must be satisfied
-type quantifier() :: forall() | exists() | either().

-type contract() ::
      {quantifier(), [contract()]}
    | {'not', contract()}
    | any
    | defined
    | undefined
    | {string, size()}
    | {iodata, size()}
    | {binary, size()}
    | {list, size(), contract()}

    % TODO Reconsider name, since we only require element uniquness, not order.
    % ordset alternatives:
    % - ulist
    % - set_list
    % - list_set
    % - list_of_uniques
    | {ordset, size(), contract()}

    | {float, size(float())}
    | {integer, size()}
    % TODO Design integration of finer refinements, like is_power_of_2, etc.
    %       {integer, size(), [refinement()]} ?
    %       {integer, size(), [contract()]} ? where refinement is a contract variant
    %
    % Use-case in blockchain_txn_oui_v1.erl


    | {member, [any()]}
    | {address, libp2p}
    | {custom, fun((val()) -> boolean()), Label :: term()} % TODO Maybe rename "custom" to "test"
    | h3_string
    | {txn, txn_type()}
    | {val, val()}  % A concrete, given value.
    .
    %% TODO
    %%  - [x] txn
    %%  - [ ] tuple of size()
    %%  - [ ] records as tuple with given head
    %%  - [ ] atom
    %%  - [x] a concrete, given value, something like: -type() val(A) :: {val, A}.

-type spec() ::
    {key(), val(), contract()}.

-type failure_bin() ::
      {not_a_binary, val()}
    | {binary_wrong_size, Actual :: non_neg_integer(), Required :: size()}
    .

-type failure_iodata() ::
      not_iodata
    | {iodata_wrong_size, Actual :: non_neg_integer(), Required :: size()}
    .

-type failure_float() ::
      {not_a_float, val()}
    | {float_out_of_range, Actual :: float(), Required :: size(float())}
    .

-type failure_int() ::
      {not_an_integer, val()}
    | {integer_out_of_range, Actual :: integer(), Required :: size()}
    .

-type failure_list() ::
      {not_a_list, val()}
    | {list_wrong_size, Actual :: non_neg_integer(), Required :: size()}
    | {list_contains_invalid_elements, [term()]}
    .

-type failure_txn() ::
      not_a_txn
    | {txn_wrong_type, Actual :: atom(), Required :: atom()}
    | txn_malformed
    .

-type failure() ::
      invalid_address
    | invalid_h3_string
    | negation_failed
    | {unexpected_val, given, val(), expected, val()}
    | {not_a_member_of, [val()]}
    | defined
    | undefined
    | failure_iodata()
    | failure_txn()
    | failure_bin()
    | failure_int()
    | failure_float()
    | failure_list()
    | {list_contains_duplicate_elements, [term()]}
    | {invalid_string, failure_list()}
    .

-type result() ::
    ok | {error, {invalid, [{key(), failure()}]}}.

%% For internal use
-type test_result() ::
    pass | {fail, failure()}.

-define(CHAR_MIN, 0).
-define(CHAR_MAX, 255).

%% API ========================================================================

-spec is_satisfied(val(), contract()) -> boolean().
is_satisfied(Val, Contract) ->
    res_to_bool(test(Val, Contract)).

-spec are_satisfied([spec()]) -> boolean().
are_satisfied(Specs) ->
    result:to_bool(result:of_empty(check(Specs), {})).

-spec check([spec()]) -> result().
check(Specs) ->
    check_specs(Specs).

-spec check([spec()], fun((contract()) -> contract())) -> result().
check(Specs0, F) ->
    Specs1 = [{K, V, F(R)}|| {K, V, R} <- Specs0],
    check(Specs1).

-spec check_with_defined([spec()]) -> result().
check_with_defined(Specs) ->
    check(Specs, fun(R) -> {forall, [defined, R]} end).

%% Internal ===================================================================
-spec check_specs([spec()]) -> result().
check_specs(Specs) ->
    case lists:flatten([check_spec(S) || S <- Specs]) of
        [] ->
            ok;
        [_|_]=Invalid ->
            {error, {invalid, Invalid}}
    end.

-spec check_spec(spec()) -> [{key(), failure()}].
check_spec({Key, Val, Contract}) ->
    case test(Val, Contract) of
        pass ->
            [];
        {fail, Failure} ->
            [{Key, Failure}]
    end.

-spec test(val(), contract()) -> test_result().
test(_, any)                      -> pass;
test(V, {val, Expected})          -> test_val(V, Expected);
test(V, {'not', Contract})        -> test_not(V, Contract);
test(V, {custom, IsValid, Label}) -> test_custom(V, IsValid, Label);
test(V, defined)                  -> test_defined(V);
test(V, undefined)                -> test_undefined(V);
test(V, {string, SizeSpec})       -> test_string(V, SizeSpec);
test(V, {iodata, SizeSpec})       -> test_iodata(V, SizeSpec);
test(V, {binary, SizeSpec})       -> test_binary(V, SizeSpec);
test(V, {list, Size, Contract})   -> test_list(V, Size, Contract);
test(V, {ordset, Size, Contract}) -> test_ordset(V, Size, Contract);
test(V, {integer, SizeSpec})      -> test_int(V, SizeSpec);
test(V, {float, SizeSpec})        -> test_float(V, SizeSpec);
test(V, {member, Vs})             -> test_membership(V, Vs);
test(V, {address, libp2p})        -> test_address_libp2p(V);
test(V, h3_string)                -> test_h3_string(V);
test(V, {txn, TxnType})           -> test_txn(V, TxnType);
test(V, {ForAll, Contracts}) when ForAll =:= forall; ForAll =:= '∀'->
    test_forall(V, Contracts);
test(V, {Exists, Contracts}) when Exists =:= exists; Exists =:= '∃'  ->
    test_exists(V, Contracts);
test(V, {Either, Contracts}) when Either =:= either; Either =:= '∃!'  ->
    test_either(V, Contracts).

-spec test_not(val(), contract()) -> test_result().
test_not(V, Contract) ->
    case test(V, Contract) of
        pass -> {fail, negation_failed};
        {fail, _} -> pass
    end.

-spec test_val(val(), val()) -> test_result().
test_val(V, V) -> pass;
test_val(G, E) -> {fail, {unexpected_val, given, G, expected, E}}.

-spec test_forall(val(), [contract()]) -> test_result().
test_forall(V, Contracts) ->
    lists:foldl(
        fun (R, pass) -> test(V, R);
            (_, {fail, _}=Failed) -> Failed
        end,
        pass,
        Contracts
    ).

-spec test_exists(val(), [contract()]) -> test_result().
test_exists(V, Contracts) ->
    lists:foldl(
        fun (_, pass) -> pass;
            (R, {fail, _}) -> test(V, R)
        end,
        case Contracts of
            [] ->
                pass;
            [_|_] ->
                %% XXX Init failure must never escape this foldl
                {fail, {'BUG_IN', {?MODULE, 'test_exists', ?LINE}}}
        end,
        Contracts
    ).

-spec test_either(val(), [contract()]) -> test_result().
test_either(V, Contracts) ->
    Results = [test(V, R) || R <- Contracts],
    case lists:filter(fun res_to_bool/1, Results) of
        [] -> {fail, zero_contracts_satisfied};
        [_] -> pass;
        [_|_] -> {fail, multiple_contracts_satisfied}
    end.

-spec test_custom(val(), fun((val()) -> boolean()), term()) -> test_result().
test_custom(V, IsValid, Label) ->
    case IsValid(V) of
        true -> pass;
        false -> {fail, {Label, V}}
    end.

-spec test_defined(val()) -> test_result().
test_defined(undefined) ->
    {fail, undefined};
test_defined(_) ->
    pass.

-spec test_undefined(val()) -> test_result().
test_undefined(undefined) ->
    pass;
test_undefined(_) ->
    {fail, defined}.

-spec test_iodata(val(), size()) -> test_result().
test_iodata(V, SizeSpec) ->
    try erlang:iolist_size(V) of
        Size ->
            res_of_bool(
                is_in_range(Size, SizeSpec),
                {iodata_wrong_size, Size, SizeSpec}
            )
    catch
        _:_ ->
            {fail, not_iodata}
    end.

-spec test_binary(val(), size()) -> test_result().
test_binary(V, SizeSpec) ->
    case is_binary(V) of
        false ->
            {fail, {not_a_binary, V}};
        true ->
            Size = byte_size(V),
            res_of_bool(
                is_in_range(Size, SizeSpec),
                {binary_wrong_size, Size, SizeSpec}
            )
    end.

-spec test_string(val(), size()) -> test_result().
test_string(V, Size) ->
    case test(V, {list, Size, {integer, {range, ?CHAR_MIN, ?CHAR_MAX}}}) of
        pass ->
            pass;
        {fail, Reason} ->
            {fail, {invalid_string, Reason}}
    end.

-spec test_list_size(val(), size()) -> test_result().
test_list_size(V, SizeSpec) ->
    case is_list(V) of
        false ->
            {fail, {not_a_list, V}};
        true ->
            Size = length(V),
            res_of_bool(
                is_in_range(Size, SizeSpec),
                {list_wrong_size, Size, SizeSpec}
            )
    end.

-spec test_list(val(), size(), contract()) -> test_result().
test_list(Xs, SizeSpec, Contract) ->
    case test_list_size(Xs, SizeSpec) of
        {fail, _}=Fail ->
            Fail;
        pass ->
            Invalid =
                lists:foldl(
                    fun (X, Invalid) ->
                        case test(X, Contract) of
                            pass -> Invalid;
                            {fail, _} -> [X | Invalid]
                        end
                    end,
                    [],
                    Xs
                ),
            case Invalid of
                [] ->
                    pass;
                [_|_] ->
                    {fail, {list_contains_invalid_elements, Invalid}}
            end
    end.

-spec test_ordset(val(), size(), contract()) -> test_result().
test_ordset(Xs, Size, Contract) ->
    case test_list(Xs, Size, Contract) of
        {fail, _}=Fail ->
            Fail;
        pass ->
            case Xs -- lists:usort(Xs) of
                [] ->
                    pass;
                [_|_]=Dups ->
                    {fail, {list_contains_duplicate_elements, Dups}}
            end
    end.

-spec test_float(val(), size(float())) -> test_result().
test_float(V, Range) ->
    test_num(V, Range, fun erlang:is_float/1, not_a_float, float_out_of_range).

-spec test_int(val(), size()) -> test_result().
test_int(V, Range) ->
    test_num(V, Range, fun erlang:is_integer/1, not_an_integer, integer_out_of_range).

-spec test_num(val(), size(Type), fun((val()) -> boolean()), atom(), atom()) ->
    test_result() when Type :: integer() | float().
test_num(V, Range, TypeTest, TypeFailureLabel, RangeFailureLabel) ->
    case TypeTest(V) of
        false ->
            {fail, {TypeFailureLabel, V}};
        true ->
            res_of_bool(
                is_in_range(V, Range),
                {RangeFailureLabel, V, Range}
            )
    end.

-spec is_in_range(A, size(A)) -> boolean().
is_in_range(_, any) -> true;
is_in_range(X, {exact, Y}) -> X =:= Y;
is_in_range(X, {min, Min}) -> X >= Min;
is_in_range(X, {max, Max}) -> X =< Max;
is_in_range(X, {range, Min, Max}) ->
    is_in_range(X, {min, Min}) andalso
    is_in_range(X, {max, Max}).

-spec test_membership(val(), [val()]) -> test_result().
test_membership(V, Vs) ->
    res_of_bool(lists:member(V, Vs), {not_a_member_of, Vs}).

-spec test_address_libp2p(val()) -> test_result().
test_address_libp2p(V) ->
    try libp2p_crypto:bin_to_pubkey(V) of
        _ -> pass
    catch
        _:_ -> {fail, invalid_address}
    end.

-spec test_h3_string(val()) -> test_result().
test_h3_string(V) ->
    try h3:from_string(V) of
        _ -> pass
    catch
        _:_ -> {fail, invalid_h3_string}
    end.

-spec test_txn(val(), txn_type()) -> test_result().
test_txn(V, TxnType) ->
    case blockchain_txn:type_check(V) of
        {error, not_a_known_txn_value} ->
            {fail, not_a_txn};
        {ok, TypeActual} ->
            TypeRequired =
                case TxnType of
                    any ->
                        TypeActual;
                    {type, Type} ->
                        Type
                end,
            case TypeActual =:= TypeRequired of
                true ->
                    case TypeActual:is_well_formed(V) of
                        ok ->
                            pass;
                        {error, _} ->
                            {fail, txn_malformed} % TODO Return more info?
                    end;
                false ->
                    {fail, {txn_wrong_type, TypeActual, TypeRequired}}
            end
    end.

-spec res_of_bool(boolean(), failure()) -> test_result().
res_of_bool(true, _) -> pass;
res_of_bool(false, Failure) -> {fail, Failure}.

-spec res_to_bool(test_result()) -> boolean().
res_to_bool(pass) -> true;
res_to_bool({fail, _}) -> false.

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

%% Test cases =================================================================
logic_test_() ->
    [
        ?_assertEqual(pass, test(<<>>, {'∀', [defined, {binary, any}]})),
        ?_assertEqual(pass, test(<<>>, {forall, [defined, {binary, any}]})),
        ?_assertEqual(pass, test(<<>>, {exists, [defined, {binary, any}]})),
        ?_assertEqual(pass, test(<<>>, {'∃', [defined, {binary, {exact, 5}}]})),
        ?_assertEqual(pass, test(<<>>, {exists, [defined, {binary, {exact, 5}}]})),
        ?_assertEqual(
            pass,
            test(
                undefined,
                {exists, [
                    defined,
                    {binary, {exact, 5}},
                    {custom, fun erlang:is_atom/1, is_atom}
                ]}
            )
        ),
        ?_assertMatch(
            {fail, undefined},
            test(undefined, {forall, [defined, {binary, {exact, 5}}]})
        ),
        ?_assertMatch(
            {fail, {binary_wrong_size, 0, {exact, 5}}},
            test(<<>>, {forall, [defined, {binary, {exact, 5}}]})
        ),
        ?_assertEqual(pass, test(5, {either, [{integer, any}, {binary, any}]})),
        ?_assertEqual(pass, test(5, {'∃!', [{integer, any}, {binary, any}]})),
        ?_assertMatch(
            {fail, zero_contracts_satisfied},
            test(5, {either, [{integer, {max, 1}}, {integer, {exact, 10}}]})
        ),
        ?_assertMatch(
            {fail, multiple_contracts_satisfied},
            test(5, {either, [{integer, any}, {integer, any}]})
        ),
        ?_assertMatch(
            {fail, multiple_contracts_satisfied},
            test(5, {either, [{integer, any}, {integer, {range, 0, 10}}]})
        )
    ].

membership_test_() ->
    [
        ?_assertEqual(pass, test(x, {member, [x, y, x]})),
        ?_assertEqual({fail, {not_a_member_of, []}}, test(x, {member, []}))
    ].

integer_test_() ->
    [
        ?_assertEqual(pass, test(1, {integer, any})),
        ?_assertEqual(pass, test(1, {integer, {exact, 1}})),
        ?_assertEqual(
            {fail, {integer_out_of_range, 2, {exact, 1}}},
            test(2, {integer, {exact, 1}})
        )
    ].

float_test_() ->
    [
        ?_assertEqual(pass, test(1.0, {float, any})),
        ?_assertEqual(pass, test(1.0, {float, {exact, 1.0}})),
        ?_assertEqual(
            {fail, {float_out_of_range, 2.0, {exact, 1.0}}},
            test(2.0, {float, {exact, 1.0}})
        )
    ].

custom_test_() ->
    BarContract = {custom, fun(X) -> X =:= bar end, not_bar},
    Key = foo,
    [
        ?_assertEqual(pass, test(bar, BarContract)),
        ?_assertEqual({fail, {not_bar, baz}}, test(baz, BarContract)),
        ?_assertEqual(ok, check([{Key, bar, BarContract}])),
        ?_assertEqual(
            {error, {invalid, [{Key, {not_bar, baz}}]}},
            check([{Key, baz, BarContract}])
        )
    ].

defined_test_() ->
    Contract = defined,
    Key = foo,
    [
        ?_assertEqual(pass, test(bar, Contract)),
        ?_assertEqual({fail, undefined}, test(undefined, Contract)),
        ?_assertEqual(ok, check([{Key, bar, Contract}])),
        ?_assertEqual(
            {error, {invalid, [{Key, undefined}]}},
            check([{Key, undefined, Contract}])
        )
    ].

binary_test_() ->
    Key = foo,
    [
        ?_assertEqual(pass, test(<<>>, {binary, any})),
        ?_assertEqual(pass, test(<<>>, {binary, {exact, 0}})),
        ?_assertEqual(pass, test(<<>>, {binary, {range, 0, 1024}})),
        ?_assertEqual(
            {fail, {binary_wrong_size, 0, {range, 1, 1024}}},
            test(<<>>, {binary, {range, 1, 1024}})
        ),
        ?_assertEqual(pass, test(<<"a">>, {binary, {range, 1, 1024}})),
        ?_assertEqual(pass, test(<<"bar">>, {binary, {range, 3, 1024}})),
        ?_assertEqual(ok, check([{Key, <<>>, {binary, any}}])),
        ?_assertEqual(ok, check([{Key, <<>>, {binary, {exact, 0}}}])),
        ?_assertEqual(
            {error, {invalid, [{Key, {binary_wrong_size, 0, {range, 8, 1024}}}]}},
            check([{Key, <<>>, {binary, {range, 8, 1024}}}])
        )
    ].

list_test_() ->
    Key = foo,
    BadList = <<"trust me, i'm a list">>,
    [
        ?_assertEqual(pass, test([], {list, any, any})),
        ?_assertEqual(pass, test([], {list, {exact, 0}, any})),
        ?_assertEqual(pass, test([], {list, {range, 0, 1024}, any})),
        ?_assertEqual(
            {fail, {list_wrong_size, 0, {range, 1, 1024}}},
            test([], {list, {range, 1, 1024}, any})
        ),
        ?_assertEqual(pass, test([a], {list, {range, 1, 1024}, any})), % TODO atom contract
        ?_assertEqual(pass, test([a, b, c], {list, {range, 3, 1024}, any})), % TODO atom contract
        ?_assertEqual(pass, test([a, b, c, d, e, f], {list, {range, 3, 1024}, any})), % TODO atom contract
        ?_assertEqual(ok, check([{Key, [], {list, any, any}}])),
        ?_assertEqual(ok, check([{Key, [], {list, {exact, 0}, any}}])),
        ?_assertEqual(
            {error, {invalid, [{Key, {list_wrong_size, 0, {range, 8, 1024}}}]}},
            check([{Key, [], {list, {range, 8, 1024}, any}}])
        ),
        ?_assertEqual(
            {error, {invalid, [{Key, {not_a_list, BadList}}]}},
            check(
                [{Key, BadList, {list, {range, 8, 1024}, any}}]
            )
        ),
        ?_assertEqual(pass, test([], {list, any, {integer, any}})),
        ?_assertEqual(pass, test([], {list, any, {integer, {range, 1, 5}}})),
        ?_assertEqual(pass, test([1, 2, 3], {list, any, {integer, any}})),
        ?_assertEqual(pass, test([1, 2, 3], {list, {exact, 3}, {integer, any}})),
        ?_assertEqual(pass, test([1, 2, 3], {list, any, {integer, {range, 1, 5}}})),
        ?_assertEqual(
            {fail, {list_contains_invalid_elements, [30]}},
            test([1, 2, 30], {list, any, {integer, {range, 1, 5}}})
        )
    ].

address_test_() ->
    Addr = addr_gen(),
    [
        ?_assertEqual(pass, test(Addr, {address, libp2p})),
        ?_assertEqual(
            {fail, invalid_address},
            test(<<"eggplant", Addr/binary>>, {address, libp2p})
        ),
        ?_assertEqual(
            pass,
            test(
                Addr,
                {forall, [
                    defined,
                    {binary, any},
                    {binary, {range, 0, 1024}},
                    {binary, {exact, 33}},
                    {address, libp2p}
                ]}
            )
        )
    ].

iodata_test_() ->
    CharMin = 0,
    CharMax = 255,
    IOData = ["foo", <<"baz">>],
    [
        ?_assertEqual(pass                                    , test_iodata(IOData, any)),
        ?_assertMatch({fail, {iodata_wrong_size, _, {min, _}}}, test_iodata(IOData, {min, iolist_size(IOData) + 1})),
        ?_assertMatch({fail, {iodata_wrong_size, _, {max, _}}}, test_iodata(IOData, {max, iolist_size(IOData) - 1})),

        ?_assertEqual({fail, not_iodata}, test_iodata(undefined, any)),
        ?_assertEqual({fail, not_iodata}, test_iodata([undefined], any)),
        ?_assertEqual({fail, not_iodata}, test_iodata(["foo", bar, <<"baz">>], any)),
        ?_assertEqual(pass, test_iodata(["foo", [["123"], [[], ["qux"]]], <<"baz">>], any)),
        ?_assertEqual({fail, not_iodata}, test_iodata(["foo", [["123"], [[hi], ["qux"]]], <<"baz">>], any)),
        ?_assertEqual({fail, not_iodata}, test_iodata(["foo", [["123"], [[], ["qux"]]], CharMin - 1, <<"baz">>], any)),
        ?_assertEqual({fail, not_iodata}, test_iodata(["foo", [["123"], [[], ["qux"]]], CharMax + 1, <<"baz">>], any)),
        ?_assertEqual(pass, test_iodata(["foo", [["123"], [[], ["qux"]]], CharMin, <<"baz">>], any)),
        ?_assertEqual(pass, test_iodata(["foo", [["123"], [[], ["qux"]]], CharMax, <<"baz">>], any)),
        ?_assertEqual(pass, test([[], [<<"1">>], "2", <<"3">>], {list, any, {iodata, any}})),

        ?_assertMatch(pass                                       , test("12345678", {list, any, {integer, any}})),
        ?_assertMatch({fail, {list_contains_invalid_elements, _}}, test("12345678", {list, any, {iodata, any}})),
        ?_assertEqual(pass                                       , test("12345678", {iodata, any}))
    ].

string_test_() ->
    [
        ?_assertEqual(pass, test("foo", {string, any})),
        ?_assertEqual(
            {fail, {invalid_string, {list_wrong_size, 3, {min, 4}}}},
            test("foo", {string, {min, 4}})
        ),
        ?_assertEqual(
            {fail, {invalid_string, {not_a_list, <<"foo">>}}},
            test(<<"foo">>, {string, any})
        ),
        ?_assertEqual(
            {fail, {invalid_string, {list_contains_invalid_elements, [?CHAR_MIN - 1]}}},
            test("foo" ++ [?CHAR_MIN - 1], {string, any})
        ),
        ?_assertEqual(
            {fail, {invalid_string, {list_contains_invalid_elements, [?CHAR_MAX + 1]}}},
            test("foo" ++ [?CHAR_MAX + 1], {string, any})
        )
    ].

txn_test_() ->
    Addr = addr_gen(),
    Type = blockchain_txn_add_gateway_v1,
    Txn  = Type:new(Addr, Addr),
    [
        ?_assertEqual({fail, not_a_txn}, test(trust_me_im_a_txn, {txn, any})),
        ?_assertEqual(pass, test(Txn, {txn, any})),
        ?_assertEqual(pass, test(Txn, {txn, {type, Type}})),
        ?_assertEqual(
            {fail, {txn_wrong_type, Type, not_a_txn_type}},
            test(Txn, {txn, {type, not_a_txn_type}})
        ),
        ?_assertEqual(
            {fail, txn_malformed},
            test(Type:new(<<"not addr">>, Addr), {txn, any})
        )
    ].

is_satisfied_test() ->
    ?assert(is_satisfied("foo", {forall, [{string, any}, {iodata, any}]})).

ordset_test_() ->
    [
        ?_assertMatch(pass, test([], {ordset, any, any})),
        ?_assertMatch(pass, test([a, b, c], {ordset, any, any})),

        % XXX Note that it isn't a strict ordset, since order is not enforced,
        % only uniquness:
        ?_assertMatch(pass, test([c, a, b], {ordset, any, any})),
        ?_assertMatch(pass, test([c, b, a], {ordset, any, any})),

        ?_assertMatch(
            {fail, {list_contains_duplicate_elements, [c]}},
            test([c, b, a, c], {ordset, any, any})
        ),
        ?_assertMatch(
            {fail, {list_contains_duplicate_elements, [c, c]}},
            test([c, b, a, c, c], {ordset, any, any})
        )
    ].

val_test_() ->
    [
        ?_assertEqual(pass, test(a, {val, a})),
        ?_assertEqual(
            {fail, {unexpected_val, given, b, expected, a}},
            test(b, {val, a})
        ),
        ?_assertEqual(
            {fail, negation_failed},
            test(a, {'not', {val, a}})
        ),
        ?_assertEqual(
            pass,
            test(b, {'not', {val, a}})
        )
    ].

%% Test helpers ===============================================================

-spec addr_gen() -> binary().
addr_gen() ->
    #{public := PK, secret := _} =
        libp2p_crypto:generate_keys(ecc_compact),
    libp2p_crypto:pubkey_to_bin(PK).

-endif.