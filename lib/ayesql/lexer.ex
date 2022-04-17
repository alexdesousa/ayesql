defmodule AyeSQL.Lexer do
  @moduledoc """
  This module defines the lexer for the `AyeSQL` language.
  """

  @typedoc """
  Line number.
  """
  @type line :: pos_integer()

  @typedoc """
  Column number.
  """
  @type column :: pos_integer()

  @typedoc """
  Location.
  """
  @type location :: {line(), column()}

  @typedoc """
  Original match from the string.
  """
  @type original :: binary()

  @typedoc """
  Token value.
  """
  @type value :: binary()

  @typedoc """
  Token name.
  """
  @type token_name ::
          :"$name"
          | :"$docs"
          | :"$fragment"
          | :"$named_param"

  @typedoc """
  Token.
  """
  @type token :: {token_name(), line(), {value(), original(), location()}}

  @typedoc """
  Tokens.
  """
  @type tokens :: [token()]

  @typedoc """
  Lexer option.
  """
  @type option ::
          {:error_context, pos_integer()}
          | {:filename, Path.t()}

  @typedoc """
  Lexer options.
  """
  @type options :: [option()]

  @doc """
  Gets tokens from the `contents` of a string.
  """
  @spec tokenize(binary()) :: tokens() | no_return()
  @spec tokenize(binary(), options()) :: tokens() | no_return()
  def tokenize(contents, options \\ [])

  def tokenize(contents, options) do
    case :ayesql_lexer.tokenize(contents) do
      {:ok, tokens, _} ->
        calculate_columns(tokens)

      {:error, {line, _, reason}, _} ->
        raise AyeSQL.CompileError,
          contents: contents,
          line: line,
          header: get_reason(reason),
          context: options[:error_context] || 2,
          filename: options[:filename] || "nofile"
    end
  end

  #########
  # Helpers

  @spec calculate_columns(tokens()) :: tokens()
  @spec calculate_columns(tokens(), {tokens(), location()}) :: tokens()
  defp calculate_columns(tokens, acc \\ {[], {1, 1}})

  defp calculate_columns([], {acc, _}) do
    Enum.reverse(acc)
  end

  defp calculate_columns(
         [{name, _, {value, original, {line, len}}} | tokens],
         {acc, {line, column}}
       ) do
    new_acc = [{name, line, {value, original, {line, column}}} | acc]
    calculate_columns(tokens, {new_acc, {line, column + len}})
  end

  defp calculate_columns([{_, _, {_, _, {line, _}}} | _] = tokens, {acc, _}) do
    calculate_columns(tokens, {acc, {line, 1}})
  end

  @spec get_reason(term()) :: binary()
  defp get_reason({:illegal, [first | _]}) do
    "Unexpected token \"#{[first]}\""
  end
end
