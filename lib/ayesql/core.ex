defmodule AyeSQL.Core do
  @moduledoc """
  This module defines the core functionality for AyeSQL.
  """
  alias AyeSQL.AST
  alias AyeSQL.AST.Context
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

  ############
  # Public API

  @doc """
  Whether the queries should run by default or not.

  You can set this in the configuration as:

  ```elixir
  use Mix.Config

  config :ayesql,
    run?: true
  ```
  """
  @spec run?() :: boolean()
  def run? do
    default = false
    value = Application.get_env(:ayesql, :run?, default)

    if is_boolean(value), do: value, else: default
  end

  ##########################
  # Query evaluation helpers

  # Evaluates the functions.
  @doc false
  @spec evaluate([AST.expand_function()], parameters()) ::
          {:ok, Query.t()} | {:error, Context.t()}
  @spec evaluate([AST.expand_function()], parameters(), Context.t()) ::
          {:ok, Query.t()} | {:error, Context.t()}
  def evaluate(functions, params, context \\ %Context{})

  def evaluate([], _params, %Context{} = context) do
    Context.to_query(context)
  end

  def evaluate([fun | funs], params, %Context{} = context) do
    new_context = fun.(context, params)
    evaluate(funs, params, new_context)
  end
end
