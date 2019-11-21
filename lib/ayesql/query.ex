defmodule AyeSQL.Query do
  @moduledoc """
  This module defines an AyeSQL query.
  """
  alias __MODULE__, as: Query

  @doc """
  A query struct.
  """
  defstruct statement: "", arguments: []

  @typedoc """
  Query statement.
  """
  @type statement :: binary()

  @typedoc """
  Query arguments.
  """
  @type arguments :: [term()]

  @typedoc """
  A query type.
  """
  @type t :: %__MODULE__{
    statement: statement :: statement(),
    arguments: arguments :: arguments()
  }

  ############
  # Public API

  @doc """
  Creates a new query given some `options`.
  """
  @spec new(keyword()) :: t() | no_return()
  def new(options) do
    %Query{}
    |> set_optional(:statement, options[:statement])
    |> set_optional(:arguments, options[:arguments])
  end

  #########
  # Helpers

  @doc false
  @spec set_optional(t(), atom(), term()) :: t()
  def set_optional(query, key, value)

  def set_optional(%Query{} = query, :statement, stmt) when is_binary(stmt) do
    %Query{query | statement: stmt}
  end

  def set_optional(%Query{} = query, :arguments, args) when is_list(args) do
    %Query{query | arguments: args}
  end

  def set_optional(query, _, _) do
    query
  end
end
