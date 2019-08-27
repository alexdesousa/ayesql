Nonterminals queries query fragments params.
Terminals name docs fragment named_param.
Rootsymbol queries.


queries -> query         : [ '$1' ].
queries -> query queries : [ '$1' | '$2' ].

query -> name fragments      : {extract_value('$1'), list_to_binary(""), '$2'}.
query -> name docs fragments : {extract_value('$1'), extract_value('$2'), '$3'}.

fragments -> fragment                         : [ extract_value('$1') ].
fragments -> params                           : ['$1'].
fragments -> fragment fragments               : [ extract_value('$1') | '$2'].
fragments -> params fragments                 : [ '$1' | '$2' ].

params -> named_param : extract_value('$1').

Erlang code.

extract_value({_, _, Value}) ->
  Value.
