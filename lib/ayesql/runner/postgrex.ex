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

    Queries can be run in streaming mode with the `stream_into` / `stream_timeout` option:

    ``elixir
    iex> MyQueries.get_user([id: id], run?: true, conn: connection, stream_into: &IO.inspect/1)
    :ok
    ```
    """
    use AyeSQL.Runner

    alias AyeSQL.Query
    alias AyeSQL.Runner

    @impl true
    def run(%Query{statement: stmt, arguments: args}, options) do
      conn = get_connection(options)
      stream_into_fun = options[:stream_into]

      if stream_into_fun do
        timeout = options[:stream_timeout]
        transaction_options = if timeout, do: [timeout: timeout], else: []

        Postgrex.transaction(
          conn,
          fn conn ->
            Postgrex.stream(conn, stmt, args)
            |> Runner.handle_result_stream()
            |> Stream.each(stream_into_fun)
            |> Stream.run()
          end,
          transaction_options
        )

        {:ok, nil}
      else
        with {:ok, result} <- Postgrex.query(conn, stmt, args) do
          Runner.handle_result(result)
        end
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
  end
end
