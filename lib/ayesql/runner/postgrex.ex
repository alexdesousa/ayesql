if Code.ensure_loaded?(Postgrex) do
  defmodule AyeSQL.Runner.Postgrex do
    @moduledoc """
    This module defines `Postgrex` default adapter.

    Can be used as follows:

    ```elixir
    defmodule MyQueries do
      use AyeSQL,
        runner: AyeSQL.Runner.Postgrex

      defqueries("query/my_queries.sql")
    end
    ```

    And given a `connection` to the database, then it can be used with the
    query options:

    ```elixir
    iex> MyQueries.get_user([id: id], run?: true, conn: connection)
    {:ok, ...}
    ```

    Queries can be run in streaming mode with the `stream_fun` / `stream_timeout` option:

    ``elixir
    iex> MyQueries.get_user([id: id], run?: true, conn: connection, stream_fun: &IO.inspect/1)
    :ok
    ```

    The `stream_fun` function is called for each row in the stream, the whole
    execution happens in a transaction (ref. `Postgrex.stream/4` docs).
    `stream_timeout` option can be used to control the underlying Postgrex
    transation `timeout` option.
    """
    use AyeSQL.Runner

    alias AyeSQL.Query
    alias AyeSQL.Runner

    @type connection :: pid() | atom()

    @impl true
    def run(%Query{statement: stmt, arguments: args}, options) do
      conn = get_connection(options)
      stream? = Keyword.has_key?(options, :stream_fun)

      if stream? do
        stream(conn, stmt, args, options[:stream_fun], options[:stream_timeout])
      else
        query(conn, stmt, args)
      end
    end

    #########
    # Helpers

    # Gets the connection.
    @spec get_connection(keyword()) :: term() | no_return()
    defp get_connection(options) do
      with nil <- options[:conn] do
        raise ArgumentError, "Connection `:conn` cannot be nil"
      end
    end

    @spec query(connection(), Query.statement(), Query.arguments()) ::
            {:ok, [map()]}
    defp query(conn, stmt, args) do
      with {:ok, result} <- Postgrex.query(conn, stmt, args) do
        Runner.handle_result(result)
      end
    end

    @spec stream(
            connection(),
            Query.statement(),
            Query.arguments(),
            (map() -> any()),
            nil | timeout()
          ) :: {:ok, :ok}
    defp stream(conn, stmt, args, stream_fun, stream_timeout) do
      transaction_options =
        if stream_timeout, do: [timeout: stream_timeout], else: []

      Postgrex.transaction(
        conn,
        fn conn ->
          Postgrex.stream(conn, stmt, args)
          |> Runner.handle_result_stream()
          |> Stream.each(stream_fun)
          |> Stream.run()
        end,
        transaction_options
      )

      {:ok, :ok}
    end
  end
end
