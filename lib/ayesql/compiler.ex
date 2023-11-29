defmodule AyeSQL.Compiler do
  @moduledoc """
  This module defines functions to compile `AyeSQL` language strings.
  """
  alias AyeSQL.Lexer

  @typedoc """
  Query fragment.
  """
  @type fragment :: binary()

  @typedoc """
  Query parameter.
  """
  @type param :: atom()

  @typedoc """
  Query fragments.
  """
  @type fragments :: [fragment() | param()]

  @typedoc """
  Query name.
  """
  @type name :: nil | atom()

  @typedoc """
  Query documentation.
  """
  @type docs :: nil | binary()

  @typedoc """
  Query.
  """
  @type query :: {name(), docs(), fragments()}

  @typedoc """
  Queries.
  """
  @type queries :: [query()]

  @doc """
  Compiles the `contents` of a file or string into valid AyeSQL queries.
  """
  @spec compile_queries(binary()) ::
          [Macro.t()]
          | no_return()
  @spec compile_queries(binary(), Lexer.options()) ::
          [Macro.t()]
          | no_return()
  def compile_queries(contents, options \\ []) do
    error_context = options[:error_context] || 2
    filename = options[:filename] || "nofile"

    case compile(contents, options) do
      [_ | _] = queries ->
        queries

      _ ->
        raise AyeSQL.CompileError,
          contents: contents,
          line: 1,
          header:
            "Cannot create unnamed queries (use `AyeSQL.Compile.create_query/2` instead)",
          context: error_context,
          filename: filename
    end
  end

  @doc """
  Compiles a single query from the `contents` of a string.
  """
  @spec compile_query(binary()) ::
          Macro.t()
          | no_return()
  @spec compile_query(binary(), Lexer.options()) ::
          Macro.t()
          | no_return()
  def compile_query(contents, options \\ []) do
    error_context = options[:error_context] || 2
    filename = options[:filename] || "nofile"

    case compile(contents, options) do
      query when not is_list(query) ->
        query

      _ ->
        raise AyeSQL.CompileError,
          contents: contents,
          line: 1,
          header:
            "Cannot create named queries (use `AyeSQL.Compile.create_queries/2` instead)",
          context: error_context,
          filename: filename
    end
  end

  @doc """
  Evaluates the `contents` of a string to an anonymous function with a query
  that receives parameters and options.
  """
  @spec eval_query(binary()) ::
          (AyeSQL.Core.parameters(), AyeSQL.Core.options() ->
             {:ok, AyeSQL.Query.t() | term()}
             | {:error, AyeSQL.Error.t() | term()})
          | no_return()
  @spec eval_query(binary(), Lexer.options()) ::
          (AyeSQL.Core.parameters(), AyeSQL.Core.options() ->
             {:ok, AyeSQL.Query.t() | term()}
             | {:error, AyeSQL.Error.t() | term()})
          | no_return()
  def eval_query(contents, options \\ []) do
    contents
    |> compile_query(options)
    |> Code.eval_quoted()
    |> elem(0)
  end

  ##################
  # Queries creation

  @spec compile(binary(), Lexer.options()) ::
          Macro.t()
          | [Macro.t()]
          | no_return()
  defp compile(contents, options) do
    contents
    |> Lexer.tokenize(options)
    |> :ayesql_parser.parse()
    |> case do
      {:ok, queries} ->
        create_queries(queries)

      {:error, reason} ->
        raise_error(contents, reason, options)
    end
  end

  @spec create_queries(queries()) :: Macro.t() | [Macro.t()]
  @spec create_queries(queries(), [Macro.t()]) :: Macro.t() | [Macro.t()]
  defp create_queries(queries, acc \\ [])

  defp create_queries([{nil, nil, fragments}], _acc) do
    create_single_query(fragments)
  end

  defp create_queries([], acc) do
    Enum.reverse(acc)
  end

  defp create_queries([{_name, _docs, _fragments} = query | queries], acc) do
    acc = [create_query!(query), create_query(query) | acc]

    create_queries(queries, acc)
  end

  @spec create_single_query(fragments()) :: Macro.t()
  defp create_single_query(fragments) do
    fragments = Macro.escape(fragments)

    quote do
      fn params, options ->
        {index, options} = Keyword.pop(options, :index, 1)
        {run?, options} = Keyword.pop(options, :run, true)

        {db_runner, db_options} =
          Keyword.pop(options, :runner, AyeSQL.Runner.Ecto)

        content = AyeSQL.AST.expand(__MODULE__, unquote(fragments))
        context = AyeSQL.AST.Context.new(index: index)

        with {:ok, query} <- AyeSQL.Core.evaluate(content, params, context) do
          if run? do
            AyeSQL.run(db_runner, query, db_options)
          else
            {:ok, query}
          end
        end
      end
    end
  end

  @spec create_query(query()) :: Macro.t()
  defp create_query({name, docs, fragments}) do
    fragments = Macro.escape(fragments)

    quote do
      @doc AyeSQL.Compiler.gen_docs(unquote(docs), unquote(fragments))
      @spec unquote(name)(AyeSQL.Core.parameters()) ::
              {:ok, AyeSQL.Query.t() | term()}
              | {:error, AyeSQL.Error.t() | term()}
      @spec unquote(name)(AyeSQL.Core.parameters(), AyeSQL.Core.options()) ::
              {:ok, AyeSQL.Query.t() | term()}
              | {:error, AyeSQL.Error.t() | term()}
      def unquote(name)(params, options \\ [])

      def unquote(name)(params, options) do
        options = Keyword.merge(__MODULE__.__db_options__(), options)

        {index, options} = Keyword.pop(options, :index, 1)
        {run?, options} = Keyword.pop(options, :run, true)

        content = AyeSQL.AST.expand(__MODULE__, unquote(fragments))
        context = AyeSQL.AST.Context.new(index: index)

        with {:ok, query} <- AyeSQL.Core.evaluate(content, params, context) do
          if run? do
            __MODULE__.run(query, options)
          else
            {:ok, query}
          end
        end
      end
    end
  end

  @spec create_query!(query()) :: Macro.t()
  defp create_query!({name, docs, _}) do
    name! = String.to_atom("#{name}!")

    quote do
      @doc AyeSQL.Compiler.gen_docs!(unquote(docs))
      @spec unquote(name!)(AyeSQL.Core.parameters()) ::
              AyeSQL.Query.t()
              | term()
              | no_return()
      @spec unquote(name!)(AyeSQL.Core.parameters(), AyeSQL.Core.options()) ::
              AyeSQL.Query.t()
              | term()
              | no_return()
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

  #################
  # Docs generation

  # Generates docs for a query.
  @doc false
  @spec gen_docs(docs(), fragments()) :: binary() | boolean()
  def gen_docs(nil, _fragments), do: false

  def gen_docs(docs, fragments) do
    params = Enum.filter(fragments, &is_atom/1)

    query =
      fragments
      |> Stream.map(&if is_atom(&1), do: inspect(&1), else: &1)
      |> Enum.join(" ")
      |> String.trim()

    """
    #{docs}

    Expected `params` are:

    ```elixir
    #{inspect(params)}
    ```

    with the following `options`:
    - `run` - Whether it should run the query or not.

    and generates/runs the query:

    ```sql
    #{query}
    ```
    """
  end

  @doc false
  @spec gen_docs!(docs()) :: binary() | boolean()
  def gen_docs!(nil), do: false

  def gen_docs!(docs) do
    """
    #{docs}. On error, fails (See function without bang for
    more information).
    """
  end

  ########################
  # Compiler error helpers

  @spec raise_error(binary(), {pos_integer(), atom(), list()}, Lexer.options()) ::
          no_return()
  defp raise_error(
         contents,
         {line, _, [~c"syntax error before: ", info]},
         options
       ) do
    error_context = options[:error_context] || 2
    filename = options[:filename] || "nofile"

    info
    |> IO.iodata_to_binary()
    |> Code.eval_string()
    |> case do
      {{_, _, {line, column}}, []} ->
        raise AyeSQL.CompileError,
          contents: contents,
          line: line,
          column: column,
          context: error_context,
          filename: filename

      _ ->
        raise AyeSQL.CompileError,
          contents: contents,
          line: line,
          context: error_context,
          filename: filename
    end
  end
end
