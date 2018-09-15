Definitions.

WhiteSpace = (\s|\t)+
NewLine    = (\n|\r\n|\r)+

Comment = (\-\-)[^\n\r]*{NewLine}

Atom       = [a-z][0-9a-zA-Z_]*
NamedParam = :{Atom}

Fragment   = ([^\s\t\n\r?:'';]*|::)+
String     = '([^\\'']|\\.)*'

EndSql     = ;{NewLine}*


Rules.

({WhiteSpace}|{NewLine})            : new_fragment(TokenLine, " ").

{NamedParam}                        : new_param(TokenLine, TokenChars).
({Comment}?|({String}|{Fragment})+) : new_fragment(TokenLine, TokenChars).
{EndSql}                            : {token, {end_sql, TokenLine}}.


Erlang code.

-export([tokenize/1]).

tokenize(Binary) ->
  List = binary_to_list(Binary),
  string(List).

new_comment(TokenLine, "-- name:" ++ TokenChars) ->
  Value = string:trim(TokenChars),
  {token, {name, TokenLine, list_to_atom(Value)}};
new_comment(TokenLine, "-- docs:" ++ TokenChars) ->
  Value = string:trim(TokenChars),
  {token, {docs, TokenLine, list_to_binary(Value)}};
new_comment(_, "--" ++ _) ->
  skip_token.

new_param(TokenLine, [$: | Name]) ->
  Key = list_to_atom(Name),
  {token, {named_param, TokenLine, Key}}.

new_fragment(TokenLine, "--" ++ _ = TokenChars) ->
  new_comment(TokenLine, TokenChars);
new_fragment(TokenLine, TokenChars) ->
  {token, {fragment, TokenLine, list_to_binary(TokenChars)}}.
