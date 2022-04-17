Definitions.

%%%%%%%%%%%%
% Whitespace

WhiteSpace = (\s|\t)+
NewLine    = (\n|\r)+

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Comments and special directives

FunName    = {NewLine}*(\-\-)\sname\:\s[^\n\r]+
FunDocs    = {NewLine}*(\-\-)\sdocs\:\s[^\n\r]+
Comment    = (\-\-)[^\n\r]+

Atom       = [a-z_][0-9a-zA-Z_]*
NamedParam = :{Atom}

Fragment   = ([^\s\t\n\r:'']+|:[^a-z][^\s\t\n\r'']*)+
String     = '([^\\'']|\\.)*'


Rules.

({WhiteSpace}|{NewLine})            : new_fragment(TokenLine, TokenLen, " ").

{FunName}                           : new_comment(TokenLine, TokenLen, TokenChars).
{FunDocs}                           : new_comment(TokenLine, TokenLen, TokenChars).

{NamedParam}                        : new_param(TokenLine, TokenLen, TokenChars).
({Comment}?|({String}|{Fragment})+) : new_fragment(TokenLine, TokenLen, TokenChars).


Erlang code.

-export([tokenize/1]).

tokenize(Binary) ->
  List = binary_to_list(Binary),
  string(List).

%%%%%%%%%%%%%%%%%%
% Token generators

new_token(Name, Value, Value, Line, Len) ->
  TokenName = string:concat("$", Name),
  Token = list_to_atom(TokenName),
  String = list_to_binary(Value),
  {token, {Token, Line, {String, String, {Line, Len}}}};
new_token(Name, Value, String, Line, Len) ->
  V0 = string:concat("$", Name),
  Token = list_to_atom(V0),
  Modified = list_to_binary(Value),
  Original = list_to_binary(String),
  {token, {Token, Line, {Modified, Original, {Line, Len}}}}.

new_fragment(TokenLine, TokenLen, "--" ++ _ = TokenChars) ->
  new_comment(TokenLine, TokenLen, TokenChars);
new_fragment(TokenLine, TokenLen, "") ->
  {token, {eof, TokenLine}};
new_fragment(TokenLine, TokenLen, TokenChars) ->
  new_token("fragment", TokenChars, TokenChars, TokenLine, TokenLen).

new_comment(TokenLine, TokenLen, "-- name: " ++ Value = TokenChars) ->
  Identifier = string:trim(Value),
  new_token("name", Identifier, TokenChars, TokenLine, TokenLen);
new_comment(TokenLine, TokenLen, "-- docs: " ++ Value = TokenChars) ->
  Documentation = string:trim(Value),
  new_token("docs", Documentation, TokenChars, TokenLine, TokenLen);
new_comment(_, _, "--" ++ _) ->
  skip_token;
new_comment(TokenLine, TokenLen, TokenChars) ->
  Trimmed = string:trim(TokenChars),
  new_comment(TokenLine, TokenLen, Trimmed).

new_param(TokenLine, TokenLen, [$: | Value] = TokenChars) ->
  Name = string:trim(Value),
  new_token("named_param", Name, TokenChars, TokenLine, TokenLen).
