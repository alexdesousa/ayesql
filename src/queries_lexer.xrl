Definitions.

WhiteSpace = (\s|\t)+
NewLine    = (\n|\r)+

FunName    = {NewLine}*(\-\-)\sname\:\s[^\n\r]*
FunDocs    = {NewLine}*(\-\-)\sdocs\:\s[^\n\r]*
Comment    = (\-\-)[^\n\r]*

Atom       = [a-z_][0-9a-zA-Z_]*
NamedParam = :{Atom}

Fragment   = ([^\s\t\n\r?:'']*|::)+
String     = '([^\\'']|\\.)*'


Rules.

({WhiteSpace}|{NewLine})            : new_fragment(TokenLine, " ").

{FunName}                           : new_comment(TokenLine, TokenChars).
{FunDocs}                           : new_comment(TokenLine, TokenChars).

{NamedParam}                        : new_param(TokenLine, TokenChars).
({Comment}?|({String}|{Fragment})+) : new_fragment(TokenLine, TokenChars).


Erlang code.

-export([tokenize/1]).

tokenize(Binary) ->
  List = binary_to_list(Binary),
  string(List).

new_comment(TokenLine, "-- name:" ++ TokenChars) ->
  Value = string:trim(TokenChars),
  {token, {name, TokenLine, list_to_atom(Value)}};
new_comment(TokenLine, "\n-- name:" ++ TokenChars) ->
  Value = string:trim(TokenChars),
  {token, {name, TokenLine, list_to_atom(Value)}};
new_comment(TokenLine, "\n-- docs:" ++ TokenChars) ->
  Value = string:trim(TokenChars),
  {token, {docs, TokenLine, list_to_binary(Value)}};
new_comment(_, "--" ++ _) ->
  skip_token;
new_comment(TokenLine, "\n" ++ TokenChars) ->
  new_comment(TokenLine, TokenChars).

new_param(TokenLine, [$: | Name]) ->
  Key = list_to_atom(Name),
  {token, {named_param, TokenLine, Key}}.

new_fragment(TokenLine, "--" ++ _ = TokenChars) ->
  new_comment(TokenLine, TokenChars);
new_fragment(TokenLine, "") ->
  {token, {eof, TokenLine}};
new_fragment(TokenLine, TokenChars) ->
  {token, {fragment, TokenLine, list_to_binary(TokenChars)}}.
