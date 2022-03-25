defmodule AyeSQL.Core do
  @moduledoc """
  This module defines the core functionality for AyeSQL.
  """
  alias AyeSQL.AST
  alias AyeSQL.AST.Context
  alias AyeSQL.Error
  alias AyeSQL.Query

  @typedoc """
  AyeSQL query parameter name.
  """
  @type parameter_name :: atom()

  @typedoc """
  AyeSQL query parameters.
  """
  @type parameters :: map() | keyword()

  @typedoc """
  AyeSQL query options.
  """
  @type options :: keyword()

  ##########################
  # Query evaluation helpers

  # Evaluates the functions.
  @doc false
  @spec evaluate([AST.expand_function()], parameters(), Context.t()) ::
          {:ok, Query.t()} | {:error, Error.t()}
  def evaluate(functions, params, context)

  def evaluate([], _params, %Context{} = context) do
    Context.to_query(context)
  end

  def evaluate([fun | funs], params, %Context{} = context) do
    new_context = fun.(context, params)
    evaluate(funs, params, new_context)
  end
end
