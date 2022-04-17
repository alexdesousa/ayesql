Nonterminals queries named_queries named_query fragments.
Terminals '$name' '$docs' '$fragment' '$named_param'.
Rootsymbol queries.


queries -> fragments     : [ {nil, nil, join_fragments('$1', [])} ].
queries -> named_queries : '$1'.

named_queries -> named_query               : [ '$1' ].
named_queries -> named_query named_queries : [ '$1' | '$2' ].

named_query -> '$name' fragments         : {extract_value('$1'), nil, join_fragments('$2', [])}.
named_query -> '$name' '$docs' fragments : {extract_value('$1'), extract_value('$2'), join_fragments('$3', [])}.

fragments -> '$fragment'              : [ extract_value('$1') ].
fragments -> '$named_param'           : [ extract_value('$1') ].
fragments -> '$fragment' fragments    : [ extract_value('$1') | '$2' ].
fragments -> '$named_param' fragments : [ extract_value('$1') | '$2' ].

Erlang code.

extract_value({'$name', _, {Value, _, _}}) ->
  binary_to_atom(Value);
extract_value({'$docs', _, {<<>>, _, _}}) ->
  nil;
extract_value({'$docs', _, {Value, _, _}}) ->
  Value;
extract_value({'$fragment', _, {Value, _, _}}) ->
  Value;
extract_value({'$named_param', _, {Value, _, _}}) ->
  binary_to_atom(Value).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Helper for joining fragments

join_fragments([], Acc) ->
  'Elixir.Enum':reverse(Acc);

join_fragments(Values, Acc) ->
  case 'Elixir.Enum':split_while(Values, fun(Value) -> is_binary(Value) end) of
    {NewValues, [Diff | Rest]} ->
      NewAcc = [Diff, 'Elixir.Enum':join(NewValues, <<" ">>) | Acc],
      join_fragments(Rest, NewAcc);

    {NewValues, []} ->
      NewAcc = ['Elixir.Enum':join(NewValues, <<" ">>) | Acc],
      join_fragments([], NewAcc)
  end.
