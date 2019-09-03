defmodule AyeSQL.Core do
  @moduledoc """
  This module defines the core functionality for AyeSQL.
  """

  @typedoc """
  SQL query statements.
  """
  @type statement :: binary()

  @typedoc """
  SQL query arguments.
  """
  @type arguments :: list()

  @typedoc """
  AyeSQL query.
  """
  @type query :: {statement(), arguments()}

  @typedoc """
  AyeSQL query parameters.
  """
  @type parameters :: map() | keyword()

  @typedoc """
  AyeSQL query options.
  """
  @type options :: keyword()

  @typedoc """
  Name of the query function.
  """
  @type name :: atom()

  @typedoc """
  Documentation of the query function.
  """
  @type docs :: binary()

  @typedoc """
  Contents of the query.
  """
  @type content :: [atom() | binary()]

  @typedoc """
  Definition of the query in the AST.
  """
  @type fun_def :: {name(), docs(), content()}

  @typedoc """
  AyeSQL AST.
  """
  @type ast :: [fun_def()]

  @typedoc false
  @type index :: {non_neg_integer(), [binary()], list()}

  @typedoc false
  @type expand_function ::
          (index(), parameters() -> {:ok, index()} | {:error, term()})

  @typedoc false
  @type query_function ::
          (parameters(), options() ->
            {:ok, query()} | {:ok, term()} | {:error, term()})

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

  @doc """
  Creates several queries from the contents of a `file`.
  """
  @spec create_queries(binary()) :: list() | no_return()
  def create_queries(file) do
    contents = File.read!(file)

    with {:ok, tokens, _} <- :queries_lexer.tokenize(contents),
         {:ok, ast}       <- :queries_parser.parse(tokens) do
      for function <- Enum.map(ast, &create_query/1) do
        quote do: unquote(function)
      end
    else
      {:error, {line, _module, error}, _} ->
        raise CompileError,
          file: "#{file}",
          line: line,
          description: "#{inspect error}"

      {:error, {line, _module, error}} ->
        raise CompileError,
          file: "#{file}",
          line: line,
          description: "#{inspect error}"
    end
  end

  ########################
  # Query creation helpers

  # Creates quoted query functions (with and without bang).
  @spec create_query(fun_def()) :: term()
  defp create_query({name, docs, content}) do
    content =
      content
      |> join_fragments()
      |> Macro.escape()

    quote do
      unquote(create_query(name, docs, content))

      unquote(create_query!(name, docs))
    end
  end

  # Joins string fragments.
  @spec join_fragments(content()) :: content()
  @spec join_fragments(content(), content()) :: content()
  defp join_fragments(content, acc \\ [])

  defp join_fragments([], acc) do
    Enum.reverse(acc)
  end

  defp join_fragments(values, acc) do
    case Enum.split_while(values, &is_binary/1) do
      {new_values, [diff | rest]} ->
        new_acc = [diff, Enum.join(new_values, " ") | acc]
        join_fragments(rest, new_acc)

      {new_values, []} ->
        new_acc = [Enum.join(new_values, " ") | acc]
        join_fragments([], new_acc)

    end
  end

  # Creates query function without bang.
  @spec create_query(name(), docs(), content()) :: term()
  defp create_query(name, docs, content) do
    quote do
      @doc AyeSQL.Core.gen_docs(unquote(docs), unquote(content))
      @spec unquote(name)(AyeSQL.Core.parameters()) ::
              {:ok, AyeSQL.Core.query()} | {:ok, term()} | {:error, term()}
      @spec unquote(name)(AyeSQL.Core.parameters(), AyeSQL.Core.options()) ::
              {:ok, AyeSQL.Core.query()} | {:ok, term()} | {:error, term()}
      def unquote(name)(params, options \\ [])

      def unquote(name)(params, options) do
        index = Keyword.get(options, :index, 1)
        run? = Keyword.get(options, :run?, AyeSQL.Core.run?())

        content = AyeSQL.Core.expand(__MODULE__, unquote(content))
        base = {index, [], []}

        with {:ok, result} <- AyeSQL.Core.evaluate(content, base, params) do
          if run?, do: run(result), else: {:ok, result}
        end
      end
    end
  end

  # Creates query function with bang.
  @spec create_query!(name(), docs()) :: term()
  defp create_query!(name, docs) do
    name! = String.to_atom("#{name}!")

    quote do
      @doc """
      #{unquote(docs)}. On error, fails (See function without bang for
      more information).
      """
      @spec unquote(name!)(AyeSQL.Core.parameters()) ::
              AyeSQL.Core.query() | term() | no_return()
      @spec unquote(name!)(AyeSQL.Core.parameters(), AyeSQL.Core.options()) ::
              AyeSQL.Core.query() | term() | no_return()
      def unquote(name!)(params, options \\ [])

      def unquote(name!)(params, options) do
        case unquote(name)(params, options) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise RuntimeError, message: reason
        end
      end
    end
  end

  # Generates docs for a query.
  @doc false
  @spec gen_docs(docs(), content()) :: binary()
  def gen_docs(docs, content) do
    params = Enum.filter(content, &is_atom/1)

    query =
      content
      |> Stream.map(&if is_atom(&1), do: inspect(&1), else: &1)
      |> Enum.join(" ")
      |> String.trim()

    """
    #{docs}

    Expected `params` are:

    ```elixir
    #{inspect params}
    ```

    with the following `options`:
    - `run?` - Whether it should run the query or not. Defaults to
      `#{AyeSQL.Core.run?()}`.

    and generates/runs the query:

    ```sql
    #{query}
    ```
    """
  end

  #######################
  # AST expansion helpers

  # Expands tokens to functions.
  @doc false
  @spec expand(module(), content()) :: [expand_function()]
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
    functions =
      :functions
      |> module.module_info()
      |> Enum.filter(fn {param, value} -> param == key and value == 2 end)
    if functions == [] do
      expand_param_fn(key)
    else
      expand_function_fn(module, key)
    end
  end

  # Function to process binaries.
  @spec expand_binary_fn(binary()) :: expand_function()
  defp expand_binary_fn(value) do
    fn {index, stmt, args}, _ ->
      {:ok, {index, [value | stmt], args}}
    end
  end

  # Function to process parameters.
  @spec expand_param_fn(atom()) :: expand_function()
  defp expand_param_fn(key) do
    fn acc, params ->
      case fetch(params, key) do
        nil ->
          {:error, "Cannot find #{key} in parameters"}

        value ->
          expand_value(value, acc, params)
      end
    end
  end

  # Fetches values from a map or a Keyword list.
  @spec fetch(parameters(), atom()) :: term()
  defp fetch(values, atom)

  defp fetch(values, atom) when is_map(values) do
    Map.get(values, atom)
  end

  defp fetch(values, atom) when is_list(values) do
    Keyword.get(values, atom)
  end

  # Expands values
  @spec expand_value(
          {:in, term()} | query_function() | term(),
          index(),
          parameters()
        ) :: {:ok, index()} | {:error, term()}
  defp expand_value(value, index, params)

  defp expand_value({:in, vals}, {index, stmt, args}, _) when is_list(vals) do
    {next_index, variables} = expand_list(index, vals)
    new_stmt = [variables | stmt]
    new_args = Enum.reverse(vals) ++ args

    {:ok, {next_index, new_stmt, new_args}}
  end

  defp expand_value(fun, {index, stmt, args}, params) when is_function(fun) do
    with {:ok, {new_stmt, new_args}} <- fun.(params, [index: index, run?: false]) do
      new_index = index + length(new_args)
      new_stmt = [new_stmt | stmt]
      new_args = Enum.reverse(new_args) ++ args
      {:ok, {new_index, new_stmt, new_args}}
    end
  end

  defp expand_value(value, {index, stmt, args}, _) do
    variable = "$#{inspect index}"
    {:ok, {index + 1, [variable | stmt], [value | args]}}
  end

  # Expands a list to a list of variables.
  @spec expand_list(non_neg_integer(), list()) :: {non_neg_integer(), binary()}
  defp expand_list(index, list) do
    {next_index, variables} =
      Enum.reduce(list, {index, []}, fn _, {index, acc} ->
        {index + 1, ["$#{inspect index}" | acc]}
      end)

    variables =
      variables
      |> Enum.reverse()
      |> Enum.join(",")

    {next_index, "#{variables}"}
  end

  # Function to process function calls.
  @spec expand_function_fn(module(), atom()) :: expand_function()
  defp expand_function_fn(module, key) do
    fn {index, stmt, args}, params ->
      fun_args = [params, [index: index, run?: false]]
      with {:ok, {new_stmt, new_args}} <- apply(module, key, fun_args) do
        new_index = index + length(new_args)
        new_stmt = [new_stmt | stmt]
        new_args = Enum.reverse(new_args) ++ args
        {:ok, {new_index, new_stmt, new_args}}
      end
    end
  end

  ##########################
  # Query evaluation helpers

  # Evaluates the functions.
  @doc false
  @spec evaluate([expand_function()], index(), parameters()) ::
          {:ok, query()} | {:error, term()}
  def evaluate(functions, index, params)

  def evaluate([], {_, stmt, acc}, _) do
    new_stmt =
      stmt
      |> Enum.reverse()
      |> Enum.join()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> String.trim(";")

    new_acc = Enum.reverse(acc)

    {:ok, {new_stmt, new_acc}}
  end

  def evaluate([fun | funs], acc, params) do
    with {:ok, new_acc} <- fun.(acc, params) do
      evaluate(funs, new_acc, params)
    end
  end
end
