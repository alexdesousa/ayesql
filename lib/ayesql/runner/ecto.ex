if Code.ensure_loaded?(Ecto.Adapters.SQL) do
  defmodule AyeSQL.Runner.Ecto do
    @moduledoc """
    This module defines `Ecto` default adapter.

    Can be used as follows:

    ```elixir
    defmodule MyQueries do
      use AyeSQL, repo: MyRepo

      defqueries("query/my_queries.sql")
    end
    ```

    Queries can be run in streaming mode with the `stream_fun` / `stream_timeout` option:

    ``elixir
    iex> MyQueries.get_user([id: id], run?: true, stream_fun: &IO.inspect/1)
    :ok
    ```

    The `stream_fun` function is called for each row in the stream, the whole
    execution happens in a transaction (ref. `Ecto.Repo.stream/4` docs).
    `stream_timeout` option can be used to control the underlying ecto
    transation `timeout` option.
    """
    use AyeSQL.Runner

    alias AyeSQL.Query
    alias AyeSQL.Runner
    alias Ecto.Adapter
    alias Ecto.Adapters.SQL

    @impl true
    def run(%Query{statement: stmt, arguments: args}, options) do
      repo = get_repo(options)
      stream? = Keyword.has_key?(options, :stream_fun)

      if stream? do
        stream(repo, stmt, args, options[:stream_fun], options[:stream_timeout])
      else
        query(repo, stmt, args)
      end
    end

    #########
    # Helpers

    # Gets repo module.
    @spec get_repo(keyword()) :: module() | no_return()
    defp get_repo(options) do
      repo = options[:repo]

      if Code.ensure_loaded?(repo) do
        repo
      else
        raise ArgumentError, "Invalid value for #{inspect(repo: repo)}"
      end
    end

    @spec query(module(), Query.statement(), Query.arguments()) ::
            {:ok, [map()]}
    defp query(repo, stmt, args) do
      with {:ok, result} <- SQL.query(repo, stmt, args) do
        Runner.handle_result(result)
      end
    end

    @spec stream(
            module(),
            Query.statement(),
            Query.arguments(),
            (map() -> any()),
            nil | timeout()
          ) :: {:ok, :ok}
    defp stream(repo, stmt, args, stream_fun, stream_timeout) do
      adapter_meta = Adapter.lookup_meta(repo)

      transaction_options =
        if stream_timeout, do: [timeout: stream_timeout], else: []

      SQL.transaction(adapter_meta, transaction_options, fn ->
        SQL.stream(repo, stmt, args)
        |> Runner.handle_result_stream()
        |> Stream.each(stream_fun)
        |> Stream.run()
      end)

      {:ok, :ok}
    end
  end
end
