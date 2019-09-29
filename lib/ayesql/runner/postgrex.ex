if Code.ensure_loaded?(Postgrex) do
  defmodule AyeSQL.Runner.Postgrex do
    @moduledoc """
    This module defines `Postgrex` default adapter.

    Can be used as follows:

    ```elixir
    defmodule MyQueries do
      use AyeSQL,
        module: AyeSQL.Runner.Postgrex

      defqueries("query/my_queries.sql")
    end
    ```

    And given a `connection` to the database, then it can be used with the
    query options:

    ```elixir
    iex> MyQueries.get_user([id: id], run?: true, conn: connection)
    {:ok, ...}
    ```
    """
    use AyeSQL.Runner

    alias AyeSQL.Runner

    @impl true
    def run(stmt, args, options) do
      conn = get_connection(options)

      with {:ok, result} <- Postgrex.query(conn, stmt, args) do
        Runner.handle_result(result)
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
