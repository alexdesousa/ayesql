defmodule AyeSQL.Parser do
  @moduledoc """
  This module defines AyeSQL file parsing.
  """

  @typedoc """
  File name.
  """
  @type filename :: binary()

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

  @doc """
  Creates several queries from the contents of a `file`.
  """
  @spec create_queries(filename()) :: list() | no_return()
  def create_queries(file) do
    contents = File.read!(file)

    with {:ok, tokens, _} <- :queries_lexer.tokenize(contents),
         {:ok, ast} <- :queries_parser.parse(tokens) do
      for function <- Enum.map(ast, &create_query/1) do
        quote do: unquote(function)
      end
    else
      {:error, {line, _module, error}, _} ->
        raise CompileError,
          file: "#{file}",
          line: line,
          description: "#{inspect(error)}"

      {:error, {line, _module, error}} ->
        raise CompileError,
          file: "#{file}",
          line: line,
          description: "#{inspect(error)}"
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
      @doc AyeSQL.Parser.gen_docs(unquote(docs), unquote(content))
      @spec unquote(name)(AyeSQL.Core.parameters()) ::
              {:ok, AyeSQL.Query.t() | term()}
              | {:error, AyeSQL.Error.t() | term()}
      @spec unquote(name)(AyeSQL.Core.parameters(), AyeSQL.Core.options()) ::
              {:ok, AyeSQL.Query.t() | term()}
              | {:error, AyeSQL.Error.t() | term()}
      def unquote(name)(params, options \\ [])

      def unquote(name)(params, options) do
        {index, options} = Keyword.pop(options, :index, 1)
        {run?, options} = Keyword.pop(options, :run?, AyeSQL.Core.run?())

        content = AyeSQL.AST.expand(__MODULE__, unquote(content))
        context = AyeSQL.AST.Context.new(index: index)

        with {:ok, result} <- AyeSQL.Core.evaluate(content, params, context) do
          if run?, do: run(result, options), else: {:ok, result}
        end
      end
    end
  end

  # Creates query function with bang.
  @spec create_query!(name(), docs()) :: term()
  defp create_query!(name, docs) do
    name! = String.to_atom("#{name}!")

    quote do
      @doc AyeSQL.Parser.gen_docs!(unquote(docs))
      @spec unquote(name!)(AyeSQL.Core.parameters()) ::
              AyeSQL.Query.t() | term() | no_return()
      @spec unquote(name!)(AyeSQL.Core.parameters(), AyeSQL.Core.options()) ::
              AyeSQL.Query.t() | term() | no_return()
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
  @spec gen_docs(docs(), content()) :: binary() | boolean()
  def gen_docs("", _content), do: false

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
    #{inspect(params)}
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

  @doc false
  @spec gen_docs!(docs()) :: binary() | boolean()
  def gen_docs!(""), do: false

  def gen_docs!(docs) do
    """
    #{docs}. On error, fails (See function without bang for
    more information).
    """
  end
end
