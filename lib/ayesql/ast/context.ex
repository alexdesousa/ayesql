defmodule AyeSQL.AST.Context do
  @moduledoc """
  This module defines an AST context.
  """
  alias __MODULE__, as: Context
  alias AyeSQL.Core
  alias AyeSQL.Error
  alias AyeSQL.Query

  @doc """
  AST context struct.
  """
  defstruct index: 1, statement: [], arguments: [], errors: []

  @typedoc """
  Current context index.
  """
  @type index :: non_neg_integer()

  @typedoc """
  Accumulated statement.
  """
  @type statement :: [binary()]

  @typedoc """
  Argument list.
  """
  @type arguments :: [term()]

  @typedoc """
  Error type.
  """
  @type error_type :: :not_found

  @typedoc """
  Error.
  """
  @type error :: {Core.parameter_name(), error_type()}

  @typedoc """
  AST context.
  """
  @type t :: %__MODULE__{
          index: index :: index(),
          statement: statement :: statement(),
          arguments: arguments :: arguments(),
          errors: errors :: [error()]
        }

  ############
  # Public API

  @doc """
  Creates a new context given some `options`.
  """
  @spec new(keyword()) :: t() | no_return()
  def new(options) do
    %Context{}
    |> set_optional(:index, options[:index])
    |> set_optional(:statement, options[:statement])
    |> set_optional(:arguments, options[:arguments])
    |> set_optional(:errors, options[:errors])
  end

  @doc """
  Context id function.
  """
  @spec id(t()) :: t()
  def id(context)

  def id(%Context{} = context), do: context

  @doc """
  Adds statement in a `context` given a new `value`.
  """
  @spec put_statement(t()) :: t()
  @spec put_statement(t(), nil | binary()) :: t()
  def put_statement(context, value \\ nil)

  def put_statement(%Context{index: index} = context, nil) do
    variable = "$#{inspect(index)}"
    put_statement(context, variable)
  end

  def put_statement(%Context{statement: stmt} = context, value)
      when is_binary(value) do
    %Context{context | statement: [value | stmt]}
  end

  @doc """
  Adds arguments in a `context` given a new `value`.
  """
  @spec put_argument(t(), term()) :: t()
  def put_argument(context, value)

  def put_argument(%Context{arguments: args} = context, value) do
    %Context{context | arguments: [value | args]}
  end

  @doc """
  Adds a `value` to the `context` index.
  """
  @spec add_index(t(), non_neg_integer()) :: t()
  def add_index(context, value \\ 1)

  def add_index(%Context{index: index} = context, value)
      when is_integer(value) and value > 0 do
    %Context{context | index: index + value}
  end

  @doc """
  Puts a new variable `value` in the `context`.
  """
  @spec put_variable(t(), term()) :: t()
  def put_variable(context, value)

  def put_variable(%Context{} = context, value) do
    context
    |> put_statement()
    |> put_argument(value)
    |> add_index()
  end

  @doc """
  Puts several variable `value` in the `context` as an SQL list.
  """
  @spec put_variables(t(), [term()]) :: t()
  def put_variables(%Context{index: index} = context, values) do
    inner_context =
      values
      |> Enum.reduce(new(index: index), &put_variable(&2, &1))
      |> Map.update(:statement, [], &Enum.reverse/1)
      |> Map.update(:statement, [], &Enum.join(&1, ","))

    merge(context, inner_context)
  end

  @doc """
  Merges two contexts.
  """
  @spec merge(t(), t()) :: t()
  def merge(old, new)

  def merge(%Context{} = old, %Context{} = new) do
    new(
      index: new.index,
      statement: List.flatten([new.statement | old.statement]),
      arguments: new.arguments ++ old.arguments,
      errors: new.errors ++ old.errors
    )
  end

  @doc """
  Merges a `context` with a `query`.
  """
  @spec merge_query(t(), Query.t()) :: t()
  def merge_query(context, query)

  def merge_query(%Context{} = context, %Query{} = query) do
    new(
      index: context.index + length(query.arguments),
      statement: [query.statement | context.statement],
      arguments: Enum.reverse(query.arguments) ++ context.arguments,
      errors: context.errors
    )
  end

  @doc """
  Merges a `context` with an `error`
  """
  @spec merge_error(t(), Error.t()) :: t()
  def merge_error(context, error)

  def merge_error(%Context{} = context, %Error{} = error) do
    new(
      index: context.index + length(error.arguments),
      statement: [error.statement | context.statement],
      arguments: Enum.reverse(error.arguments) ++ context.arguments,
      errors: context.errors ++ error.errors
    )
  end

  @doc """
  Transforms a context to a query.
  """
  @spec to_query(t()) :: {:ok, Query.t()} | {:error, Error.t()}
  def to_query(context)

  def to_query(%Context{errors: []} = context) do
    stmt = join_statement(context.statement)
    args = Enum.reverse(context.arguments)
    query = Query.new(statement: stmt, arguments: args)

    {:ok, query}
  end

  def to_query(%Context{} = context) do
    stmt = join_statement(context.statement)
    args = Enum.reverse(context.arguments)
    errors = Enum.reverse(context.errors)
    error = Error.new(statement: stmt, arguments: args, errors: errors)

    {:error, error}
  end

  @doc """
  Updates `context` with the error not found for a `key`.
  """
  @spec not_found(t(), Core.parameter_name()) :: t()
  def not_found(context, key)

  def not_found(%Context{statement: statement, errors: errors} = context, key) do
    %Context{
      context
      | statement: ["<missing #{key}>" | statement],
        errors: Keyword.put(errors, key, :not_found)
    }
  end

  #########
  # Helpers

  @doc false
  @spec set_optional(t(), atom(), term()) :: t() | no_return()
  def set_optional(context, key, value)

  def set_optional(%Context{} = context, :index, index)
      when is_integer(index) do
    %Context{context | index: index}
  end

  def set_optional(%Context{} = context, :statement, stmt) when is_list(stmt) do
    if Enum.all?(stmt, &is_binary/1) do
      %Context{context | statement: stmt}
    else
      raise ArgumentError, message: "statement should be a binary list"
    end
  end

  def set_optional(%Context{} = context, :arguments, args) when is_list(args) do
    %Context{context | arguments: args}
  end

  def set_optional(%Context{} = context, :errors, errors)
      when is_list(errors) do
    is_error = fn e ->
      is_tuple(e) and is_atom(elem(e, 0)) and tuple_size(e) == 2
    end

    if Enum.all?(errors, is_error) do
      %Context{context | errors: errors}
    else
      raise ArgumentError, message: "errors should be a keyword list"
    end
  end

  def set_optional(context, _, _) do
    context
  end

  # Joins a statement into a binary.
  @spec join_statement(statement()) :: binary()
  defp join_statement(statement) when is_list(statement) do
    statement
    |> Enum.reverse()
    |> Enum.join()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.trim(";")
  end
end
