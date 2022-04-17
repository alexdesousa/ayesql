defmodule AyeSQL.AST do
  @moduledoc """
  This module defines function for expanding the AST.
  """
  alias AyeSQL.AST.Context
  alias AyeSQL.Compiler
  alias AyeSQL.Core
  alias AyeSQL.Error
  alias AyeSQL.Query

  @empty :"$AYESQL_EMPTY"
  @not_found :"$AYESQL_NOT_FOUND"

  @typedoc """
  Function to be applied with some parameters and context.
  """
  @type expand_function ::
          (Context.t(), Core.parameters() -> Context.t())

  @typedoc false
  @type query_function ::
          (Core.parameters(), Core.options() ->
             {:ok, Query.t()} | {:error, Error.t()})

  @typedoc false
  @type local_query :: atom()

  @typedoc false
  @type remote_query :: query_function()

  @typedoc false
  @type query :: local_query() | remote_query()

  @typedoc false
  @type query_call :: query() | {query(), Core.parameters()}

  @typedoc false
  @type value ::
          :"$AYESQL_EMPTY"
          | :"$AYESQL_NOT_FOUND"
          | {:in, [term()]}
          | {:inner, [query_call()]}
          | {:inner, [query_call()], binary()}
          | query()
          | term()

  #######################
  # AST expansion helpers

  # Expands tokens to functions.
  @doc false
  @spec expand(module(), Compiler.fragments()) :: [expand_function()]
  def expand(module, content) when is_list(content) do
    Enum.map(content, &do_expand(module, &1))
  end

  # Expands a token to a function
  @spec do_expand(module(), binary() | atom()) :: expand_function()
  defp do_expand(module, value)

  defp do_expand(_, value) when is_binary(value) do
    expand_binary_fn(value)
  end

  defp do_expand(module, key) when is_atom(key) do
    if is_query?(module, key) do
      expand_function_fn(module, key)
    else
      expand_param_fn(module, key)
    end
  end

  # Function to process binaries.
  @spec expand_binary_fn(binary()) :: expand_function()
  defp expand_binary_fn(value) do
    fn %Context{} = context, _ ->
      Context.put_statement(context, value)
    end
  end

  # Function to process function calls.
  @spec expand_function_fn(module(), atom()) :: expand_function()
  defp expand_function_fn(module, key) do
    fn %Context{} = context, params ->
      expand_remote_function({module, key}, context, params)
    end
  end

  # Function to process parameters.
  @spec expand_param_fn(module(), atom()) :: expand_function()
  defp expand_param_fn(module, key) do
    fn %Context{} = context, params ->
      case fetch(params, key) do
        @not_found ->
          Context.not_found(context, key)

        @empty ->
          Context.id(context)

        {:in, values} when is_list(values) ->
          Context.put_variables(context, values)

        {:inner, values} ->
          expand_inner(module, values, context, params)

        {:inner, values, separator} ->
          expand_inner(module, values, separator, context, params)

        local_function when is_atom(local_function) ->
          expand_local_function(module, local_function, context, params)

        remote_function when is_function(remote_function) ->
          expand_remote_function(remote_function, context, params)

        value ->
          Context.put_variable(context, value)
      end
    end
  end

  #########
  # Helpers

  # Expands inner query.
  @spec expand_inner(module(), [query_call()], Context.t(), Core.parameters()) ::
          Context.t()
  @spec expand_inner(
          module(),
          [query_call()],
          binary(),
          Context.t(),
          Core.parameters()
        ) :: Context.t()
  defp expand_inner(module, values, separator \\ " ", context, params)

  defp expand_inner(module, values, separator, context, params)
       when is_binary(separator) and is_list(values) do
    values
    |> Stream.intersperse(separator)
    |> Enum.reduce(context, &expand_query(module, &1, &2, params))
  end

  # Expands a query.
  @spec expand_query(
          module(),
          binary() | query_call(),
          Context.t(),
          Core.parameters()
        ) :: Context.t()
  defp expand_query(module, fragment, context, params)

  defp expand_query(_module, separator, context, _params)
       when is_binary(separator) do
    Context.put_statement(context, "#{separator}")
  end

  defp expand_query(module, local_function, context, params)
       when is_atom(local_function) do
    expand_local_function(module, local_function, context, params)
  end

  defp expand_query(_module, remote_function, context, params)
       when is_function(remote_function) do
    expand_remote_function(remote_function, context, params)
  end

  defp expand_query(module, {function, params}, context, _) do
    expand_query(module, function, context, params)
  end

  # Expands local function
  @spec expand_local_function(module(), atom(), Context.t(), Core.parameters()) ::
          Context.t()
  defp expand_local_function(module, local, context, params)

  defp expand_local_function(module, value, %Context{} = context, params) do
    if is_query?(module, value) do
      expand_remote_function({module, value}, context, params)
    else
      Context.put_variable(context, value)
    end
  end

  # Expands remote function
  @spec expand_remote_function(
          query_function() | {module(), atom()},
          Context.t(),
          Core.parameters()
        ) :: Context.t()
  defp expand_remote_function(fun, context, params)

  defp expand_remote_function({module, name}, %Context{} = context, params) do
    expand_remote_function(&apply(module, name, [&1, &2]), context, params)
  end

  defp expand_remote_function(fun, %Context{index: index} = context, params) do
    case fun.(params, index: index, run: false) do
      {:ok, %Query{} = query} ->
        Context.merge_query(context, query)

      {:error, %Error{} = error} ->
        Context.merge_error(context, error)
    end
  end

  # Whether an atom is a query o not.
  @spec is_query?(module(), Core.parameter_name()) :: boolean()
  defp is_query?(nil, _key), do: false

  defp is_query?(module, key) do
    :functions
    |> module.module_info()
    |> Enum.member?({key, 2})
  end

  # Fetches values from a map or a Keyword list.
  @spec fetch(Core.parameters(), Core.parameter_name()) :: value()
  defp fetch(values, atom)

  defp fetch(values, atom) when is_map(values) do
    default =
      if optional?(atom) do
        @empty
      else
        @not_found
      end

    Map.get(values, atom, default)
  end

  defp fetch(values, atom) when is_list(values) do
    values
    |> Map.new()
    |> fetch(atom)
  end

  # Whether the parameter is optional or not.
  @spec optional?(Core.parameter_name()) :: boolean()
  defp optional?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("_")
  end
end
