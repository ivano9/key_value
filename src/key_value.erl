%% =============================================================================
%%  key_value.erl -
%%
%%  Copyright (c) 2016-2023 Leapsight Technologies Limited. All rights reserved.
%%
%%  Licensed under the Apache License, Version 2.0 (the "License");
%%  you may not use this file except in compliance with the License.
%%  You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%%  Unless required by applicable law or agreed to in writing, software
%%  distributed under the License is distributed on an "AS IS" BASIS,
%%  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%  See the License for the specific language governing permissions and
%%  limitations under the License.
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc A Key-Value coding interface for property lists and maps.
%% @end
%% -----------------------------------------------------------------------------
-module(key_value).

-define(BADKEY, '$error_badkey').
-define(COLLECT_VALUES, '$collect_values').
-define(DEFAULT_COLLECT_OPTS, #{
    '$collect_values' => false,
    default => ?BADKEY,
    on_badkey => default,
    return => list
}).

-type t()               ::  map() | [proplists:property()].
-type key()             ::  term() | [term()].
-type fold_fun()        ::  fun(
                            (Key :: any(), Value :: any(), AccIn :: any()) ->
                                AccOut :: any()
                            ).
-type foreach_fun()     ::  fun((Key :: any(), Value :: any()) -> any()).
-type collect_opts()    ::  #{
                                default => any(),
                                on_badkey => skip | error,
                                return => map | list
                            }.
-type default()         ::  any() | fun(() -> any()).

-export_type([t/0]).
-export_type([key/0]).

-export([collect/2]).
-export([collect/3]).
-export([collect_values/2]).
-export([collect_values/3]).
-export([find/2]).
-export([fold/3]).
-export([foreach/2]).
-export([get/2]).
-export([get/3]).
-export([get_lazy/3]).
-export([get_bool/2]).
-export([is_key/2]).
-export([keys/1]).
-export([normalize/1]).
-export([put/3]).
-export([remove/2]).
-export([set/3]).
-export([take/2]).
-export([to_list/1]).
-export([to_map/1]).
-export([with/2]).

-compile({no_auto_import, [get/1]}).



%% =============================================================================
%% API
%% =============================================================================


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec normalize(KV :: t()) -> t().

normalize(KV) when is_list(KV) ->
    maps:to_list(
        lists:foldl(
            fun
                ({K, V}, Acc) ->
                    Acc#{K => V};
                (K, Acc) when is_atom(K) ->
                    Acc#{K => true}
            end,
            maps:new(),
            KV
        )
    );

normalize(KV) when is_map(KV) ->
    KV.



%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec is_key(Key :: key(), KV :: t()) -> boolean().

is_key(Key, KV) when is_list(Key), is_list(KV) ->
    case get(Key, KV, '$error') of
        '$error' ->
            false;
        _ ->
            true
    end;

is_key(Key, KV) when is_list(KV) ->
    proplists:is_defined(Key, KV);

is_key(Key, KV) when is_map(KV) ->
    maps:is_key(Key, KV).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec keys(KV :: t()) -> [key()].

keys(KV) when is_list(KV) ->
    proplists:get_keys(KV);

keys(KV) when is_map(KV) ->
    maps:keys(KV).


%% -----------------------------------------------------------------------------
%% @doc Returns value `Value' associated with `Key' if `KV' contains `Key'.
%% `Key' can be a term or a path represented as a list of terms.
%%
%% The call fails with a {badarg, `KV'} exception if `KV' is not a
%% property list or map. It also fails with a {badkey, `Key'} exception if no
%% value is associated with `Key'.
%% @end
%% -----------------------------------------------------------------------------
-spec get(Key :: key(), KV :: t()) -> Value :: term().

get(Key, KV) ->
    get(Key, KV, ?BADKEY).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec get(Key :: key(), KV :: t(), Default :: default()) -> term().

get([], _, _) ->
    error(badkey);

get(_, [], Default) ->
    maybe_badkey(Default);

get(_, KV, Default) when is_map(KV) andalso map_size(KV) == 0 ->
    maybe_badkey(Default);

get([H|[]], KV, Default) ->
    get(H, KV, Default);

get([H|T], KV, Default) when is_list(KV) ->
    case lists:keyfind(H, 1, KV) of
        {H, Child} ->
            get(T, Child, Default);
        false ->
            maybe_expand(H, KV, Default)
    end;

get(Key, KV, Default) when is_list(KV) ->
    case lists:keyfind(Key, 1, KV) of
        {Key, Value} ->
            Value;
        false ->
            maybe_expand(Key, KV, Default)
    end;

get([H|T], KV, Default) when is_map(KV) ->
    case maps:find(H, KV) of
        {ok, Child} ->
            get(T, Child, Default);
        error ->
            maybe_badkey(Default)
    end;

get(Key, KV, Default) when is_map(KV) ->
    maybe_badkey(maps:get(Key, KV, Default));

get(_, _, _) ->
    error(badarg).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec get_lazy(Key :: key(), KV :: t(), Fun :: fun(() -> any())) -> term().


get_lazy(Key, KV, Fun) when is_function(Fun, 0) ->
    try
        get(Key, KV)
    catch
        error:badkey ->
            Fun()
    end.



%% -----------------------------------------------------------------------------
%% @doc Returns the value of a boolean key/value option. If `get(Key, KV)'
%% would yield `{Key, true}', this function returns `true', otherwise `false'.
%%
%% This is the same as calling `get(Key, KV, false)'.
%% @end
%% -----------------------------------------------------------------------------
-spec get_bool(Key :: key(), KV :: t()) -> boolean().

get_bool(Key, KV) ->
    get(Key, KV, false).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec find(Key :: key(), KV :: t()) -> {ok, Value :: any()} | error.

find(Key, KV) ->
    case get(Key, KV, '$error') of
        '$error' ->
            error;
        Value ->
            {ok, Value}
    end.


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec with(Keys :: [key()], t()) -> t().

with(Keys, KV) ->
    collect_values(Keys, KV).


%% -----------------------------------------------------------------------------
%% @doc Calls {@link collect/3} with the default options.
%% @end
%% -----------------------------------------------------------------------------
-spec collect([key()], KV :: t()) -> [any()].

collect(Keys, KV) ->
    %% TODO this is not efficient as we traverse the tree from root for
    %% every key. We should implement collect_map/2 (which should be
    %% optimised) and then return the values for the Keys.
    collect(Keys, KV, ?DEFAULT_COLLECT_OPTS).


%% -----------------------------------------------------------------------------
%% @doc Returns a list of values associated with the keys `Keys'.
%%
%% ?> The value returned by this function are not raw values, but Babel
%% datatype values. If you want to get the raw values use
%% {@link collect_values/3} instead.
%%
%% The return depends on the following options:
%%
%% * `default' - the value to use as default when a key in `Keys' is not
%% present in the map `Map'. The presence of a default value disables the
%% option `on_badkey'.
%% * `on_badkey' - what happens when a key is not present in the map and there
%% was no default value provided. Valid values are `skip', or `error'. When
%% using `skip' the function simply ignores the missing key and returns all
%% found keys. Using `error' will fail with a `badkey' exception.
%% * `return` - the Erlang return type of the function. Valid values are `list'
%% and `map'. Notice that naturally Erlang maps will deduplicate keys whereas
%% lists would not. Default value: `list'.
%%
%% **Examples**:
%%
%% <pre lang="erlang"><![CDATA[
%% Map = #{
%%         <<"x">> => #{
%%             <<"a">> => 1,
%%             <<"b">> => 2
%%         }
%%     }.
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect([<<"x">>], Map).
%% [{key_value,#{<<"a">> => {babel_counter,0,1},
%%               <<"b">> => {babel_counter,0,2}},
%%             [<<"a">>,<<"b">>],
%%             [],undefined}]
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect([<<"y">>], Map).
%% ** exception error: badkey
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect([<<"y">>], Map, #{on_badkey => skip}).
%% []
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect([<<"y">>], Map, #{default => undefined}).
%% [undefined]
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect([<<"x">>], Map, #{return => map}).
%% #{<<"x">> =>
%%       {key_value,#{<<"a">> => {babel_counter,0,1},
%%                    <<"b">> => {babel_counter,0,2}},
%%                  [<<"a">>,<<"b">>],
%%                  [],undefined}}
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect(
%%     [ [<<"x">>, <<"a">>], [<<"x">>, <<"b">>]  ],
%%     Map,
%%     #{return => list}
%% ).
%% [{babel_counter, 0, 1},{babel_counter, 0, 2}]
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect(
%%     [ [<<"x">>, <<"a">>], [<<"x">>, <<"b">>]  ],
%%     Map,
%%     #{return => map}
%% ).
%% #{<<"x">> =>
%%       #{<<"a">> => {babel_counter,0,1},
%%         <<"b">> => {babel_counter,0,2}}}
%% ]]></pre>
%%
%% !> The function is not clever in terms of optimisations, so judgment is
%% required when used. For example if
%% `Keys = [ [A, B, X], [A, B, Y], [A, B, Z] ]', it will iterate 3 times
%% traversing the whole path from A to X, A to Y and A to Z i.e. reading A then
%% B three times. In the future we might want to change this so that [A, B] is
%% read once.
%%
%% @throws badkey
%% @end
%% -----------------------------------------------------------------------------
-spec collect(Keys :: key(), Map :: t(), Opts :: collect_opts()) ->
    [{key(), any()}] | map().

collect(Keys, Map, Opts0) when is_list(Keys) andalso is_map(Opts0) ->
    Opts1 = maps:merge(?DEFAULT_COLLECT_OPTS, Opts0),
    Opts = maps:put(?COLLECT_VALUES, false, Opts1),
    Acc = case maps:get(return, Opts) of
        list -> [];
        map -> maps:new()
    end,
    do_collect(Keys, Map, Opts, Acc).


%% -----------------------------------------------------------------------------
%% @doc Returns a list of values associated with the keys `Keys'.
%% Fails with a `{badkey, K}` exeception if any key `K' in `Keys' is not
%% present in the map.
%% @end
%% -----------------------------------------------------------------------------
-spec collect_values([key()], Map :: t()) -> [any()].

collect_values(Keys, Map) ->
    collect_values(Keys, Map, ?DEFAULT_COLLECT_OPTS).


%% -----------------------------------------------------------------------------
%% @doc Returns a list of values associated with the keys `Keys'.
%%
%%
%% The return depends on the following options:
%%
%% * `default' - the value to use as default when a key in `Keys' is not
%% present in the map `Map'. The presence of a default value disables the
%% option `on_badkey'.
%% * `on_badkey' - what happens when a key is not present in the map and there
%% was no default value provided. Valid values are `skip', or `error'. When
%% using `skip' the function simply ignores the missing key and returns all
%% found keys. Using `error' will fail with a `badkey' exception.
%% * `return` - the Erlang return type of the function. Valid values are `list'
%% and `map'. Notice that naturally Erlang maps will deduplicate keys whereas
%% lists would not. Default value: `list'.
%%
%% **Examples**:
%%
%% <pre lang="erlang"><![CDATA[
%% Map =
%%     #{
%%         <<"x">> => #{
%%             <<"a">> => 1,
%%             <<"b">> => 2
%%         }
%%     }.
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect_values([<<"x">>], Map).
%% [#{<<"a">> => 1, <<"b">> => 2}]
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect_values([<<"y">>], Map).
%% ** exception error: badkey
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect_values([<<"y">>], Map, #{on_badkey => skip}).
%% []
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect_values([<<"y">>], Map, #{default => undefined}).
%% [undefined]
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect_values([<<"x">>], Map, #{return => map}).
%% #{<<"x">> => #{<<"a">> => 1, <<"b">> => 2}}.
%% ]]></pre>
%%
%% <pre lang="erlang"><![CDATA[
%% key_value:collect_values(
%%     [ [<<"x">>, <<"a">>], [<<"x">>, <<"b">>]  ],
%%     Map,
%%     #{return => list}
%% ).
%% [1,2]
%% ]]></pre>
%% <pre lang="erlang"><![CDATA[
%% key_value:collect_values(
%%     [ [<<"x">>, <<"a">>], [<<"x">>, <<"b">>]  ],
%%     Map,
%%     #{return => map}
%% ).
%% #{<<"x">> => #{<<"a">> => 1, <<"b">> => 2}}
%% ]]></pre>
%%
%% !> The function is not clever in terms of optimisations, so judgment is
%% required when used. For example if
%% `Keys = [ [A, B, X], [A, B, Y], [A, B, Z] ]', it will iterate 3 times
%% traversing the whole path from A to X, Y and Z i.e. reading A then B three
%% times. In the future we might want to change this so that [A, B] is read
%% once.
%%
%% @throws badkey
%% @end
%% -----------------------------------------------------------------------------
-spec collect_values([key()], Map :: t(), Opts :: collect_opts()) ->
    [any()] | #{binary() => any()}.

collect_values(Keys, Map, Opts0) ->
    %% We remove the posibility of a user forcing this function to behave like
    %% collect_values/3 to maintain the semantics of the API.
    Opts1 = maps:merge(?DEFAULT_COLLECT_OPTS, Opts0),
    Opts = maps:put(?COLLECT_VALUES, false, Opts1),
    do_collect(Keys, Map, Opts, []).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec set(Key :: key(), Value :: any(), KV :: t()) -> NewKV :: t().

set(Key, Value, KV) ->
    put(Key, Value, KV).


%% -----------------------------------------------------------------------------
%% @doc Inserts or updates a Value at the given Key or Path within a KV map 
%% or proplist. If Key is a path (list of keys), it traverses or creates 
%% the nested structure maintaining the parent's data type.
%% @end
%% -----------------------------------------------------------------------------
-spec put(Key :: key(), Value :: any(), KV :: t()) -> NewKV :: t().

put([H], Value, KV) ->
	put(H, Value, KV);

put([H | T], Value, KV) when is_list(KV) ->
	InnerTerm = put(T, Value, get(H, KV, [])),
	lists:keystore(H, 1, KV, {H, InnerTerm});

put([H | T], Value, KV) when is_map(KV) ->
	InnerTerm = put(T, Value, get(H, KV, #{})),
	KV#{H => InnerTerm};

put([], _Value, _KV) ->
	error(badkey);

put(Key, Value, KV) when is_list(KV) ->
	lists:keystore(Key, 1, KV, {Key, Value});

put(Key, Value, KV) when is_map(KV) ->
	KV#{Key => Value};

put(_Key, _Value, _KV) ->
	error(badarg).


%% -----------------------------------------------------------------------------
%% @doc Removes the Key or Path from the KV structure.
%% Maintains the data type (map or proplist) of the parent when traversing.
%% @end
%% -----------------------------------------------------------------------------
-spec remove(Key :: key(), KV :: t()) -> NewKV :: t().

remove([H], KV) ->
	remove(H, KV);

remove([H | T], KV) when is_list(KV) ->
	InnerTerm = remove(T, get(H, KV, [])),
	lists:keystore(H, 1, KV, {H, InnerTerm});

remove([H | T], KV) when is_map(KV) ->
	InnerTerm = remove(T, get(H, KV, #{})),
	KV#{H => InnerTerm};

remove([], _KV)  ->
	error(badkey);

remove(Key, KV) when is_list(KV) ->
	lists:keydelete(Key, 1, KV);

remove(Key, KV) when is_map(KV) ->
	maps:remove(Key, KV);

remove(_Key, _KV) ->
	error(badarg).


%% -----------------------------------------------------------------------------
%% @doc Extracts the Value associated with Key or Path and returns a tuple
%% containing the Value and the NewKV structure without the Key.
%% @end
%% -----------------------------------------------------------------------------
-spec take(Key :: key(), KV :: t()) -> {Value :: term(), NewKV :: t()} | error.

take([H], KV) ->
	take(H, KV);

take([H | T], KV) when is_list(KV) ->
	case take(T, get(H, KV, [])) of
		{Val, InnerTerm} ->
			{Val, lists:keystore(H, 1, KV, {H, InnerTerm})};
		error ->
			error
	end;

take([H | T], KV) when is_map(KV) ->
	case take(T, get(H, KV, #{})) of
		{Val, InnerTerm} ->
			{Val, KV#{H => InnerTerm}};
		error ->
			error
	end;

take([], _KV)  ->
	error(badkey);

take(Key, KV) when is_list(KV) ->
	case lists:keytake(Key, 1, KV) of
		{value, {_Key, Value}, NewKV} ->
			{Value, NewKV};
		false ->
			error
	end;

take(Key, KV) when is_map(KV) ->
	maps:take(Key, KV);

take(_Key, _KV) ->
	error(badarg).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec fold(Fun :: fold_fun(), Acc :: any(), KV :: t()) -> NewAcc :: any().

fold(Fun, Acc, KV) when is_list(KV) ->
    lists:foldl(
        fun
            ({K, V}, In) ->
                Fun(K, V, In);
            (K, In) when is_atom(K) ->
                Fun(K, true, In)
        end,
        Acc,
        KV
    );

fold(Fun, Acc, KV) when is_map(KV) ->
    maps:fold(Fun, Acc, KV).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec foreach(Fun :: foreach_fun(), KV :: t()) -> ok.

foreach(Fun, KV) when is_list(KV) ->
    _ = lists:foreach(
        fun
            ({K, V}) ->
                _ = Fun(K, V),
                ok;
            (K) when is_atom(K) ->
                _ = Fun(K, true),
                ok
        end,
        KV
    ),
    ok;

foreach(Fun, KV) when is_map(KV) ->
    maps:foreach(Fun, KV).


%% -----------------------------------------------------------------------------
%% @doc
%% @end
%% -----------------------------------------------------------------------------
-spec to_list(KV :: t()) -> [{key(), any()}].

to_list(KV) when is_list(KV) ->
    lists:map(
        fun
            ({_, _} = Pair) ->
                Pair;
            (K) when is_atom(K) ->
                {K, true}
        end,
        KV
    );

to_list(KV) when is_map(KV) ->
    maps:to_list(KV).


%% -----------------------------------------------------------------------------
%% @doc Converts the KV term to a map following the same semantics offered by
%% {@link get/3}.
%% @end
%% -----------------------------------------------------------------------------
-spec to_map(KV :: t()) -> [{key(), any()}].

to_map(KV) when is_list(KV) ->
    %% FIFO wins as in search
    lists:foldl(
        fun
            ({K, V}, Acc) ->
                case maps:is_key(K, Acc) of
                    true ->
                        Acc;
                    false ->
                        Acc#{K => V}
                end;
            (K, Acc) ->
                case maps:is_key(K, Acc) of
                    true ->
                        Acc;
                    false ->
                        Acc#{K => true}
                end
        end,
        #{},
        KV
    );

to_map(KV) when is_map(KV) ->
    KV.



%% =============================================================================
%% PRIVATE
%% =============================================================================



%% @private
maybe_expand(K, KV, Default) ->
    case lists:member(K, KV) of
        true ->
            true;
        false ->
            maybe_badkey(Default)
    end.


%% @private
maybe_badkey(?BADKEY) ->
    error(badkey);

maybe_badkey(Fun) when is_function(Fun, 0) ->
    Fun();

maybe_badkey(Term) ->
    Term.



%% @private
do_collect([H|T], Map, Opts, Acc0) ->
    Strategy = maps:get(on_badkey, Opts),

    try
        Default = maps:get(default, Opts),
        %% We get the value for key or path H
        Value = get(H, Map, Default),
        Acc1 = collect_acc(H, Value, Opts, Acc0),
        do_collect(T, Map, Opts, Acc1)
    catch
        error:badkey when Strategy == skip ->
            do_collect(T, Map, Opts, Acc0);
        error:badkey when Strategy == error ->
            error({badkey, H})
    end;

do_collect([], _, _, Acc) when is_map(Acc) ->
    Acc;

do_collect([], _, _, Acc) when is_list(Acc) ->
    lists:reverse(Acc).


%% @private
collect_acc(_, Value, #{?COLLECT_VALUES := true}, Acc) when is_list(Acc) ->
    [Value | Acc];

collect_acc(Key, Value, #{?COLLECT_VALUES := false}, Acc) when is_list(Acc) ->
    [{Key, Value} | Acc];

collect_acc(Key, Value, #{?COLLECT_VALUES := false}, Acc) when is_map(Acc) ->
    key_value:put(Key, Value, Acc).




