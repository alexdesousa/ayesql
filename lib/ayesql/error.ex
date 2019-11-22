defmodule AyeSQL.Error do
  @moduledoc """
  This module defines an AyeSQL error.
  """
  alias __MODULE__, as: Error

  alias AyeSQL.AST.Context

  @doc """
  A query struct.
  """
  defstruct statement: "", arguments: [], errors: []

  @typedoc """
  Query statement.
  """
  @type statement :: binary()

  @typedoc """
  Query arguments.
  """
  @type arguments :: [term()]

  @typedoc """
  Query errors.
  """
  @type errors :: [Context.error()]

  @typedoc """
  An error type.
  """
  @type t :: %__MODULE__{
          statement: statement :: statement(),
          arguments: arguments :: arguments(),
          errors: errors :: errors()
        }

  ############
  # Public API

  @doc """
  Creates a new error given some `options`.
  """
  @spec new(keyword()) :: t() | no_return()
  def new(options) do
    %Error{}
    |> set_optional(:statement, options[:statement])
    |> set_optional(:arguments, options[:arguments])
    |> set_optional(:errors, options[:errors])
  end

  #########
  # Helpers

  @doc false
  @spec set_optional(t(), atom(), term()) :: t()
  def set_optional(error, key, value)

  def set_optional(%Error{} = error, :statement, stmt) when is_binary(stmt) do
    %Error{error | statement: stmt}
  end

  def set_optional(%Error{} = error, :arguments, args) when is_list(args) do
    %Error{error | arguments: args}
  end

  def set_optional(%Error{} = error, :errors, errors) when is_list(errors) do
    %Error{error | errors: errors}
  end
end
