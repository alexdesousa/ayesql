if Code.ensure_loaded?(Postgrex) do
  defmodule AyeSQL.PostgrexBehaviour do
    @moduledoc false

    defmacro __using__(_) do
      quote do
        @behaviour AyeSQL.PostgrexBehaviour

        @impl AyeSQL.PostgrexBehaviour
        defdelegate query(conn, stmt, args, options), to: Postgrex

        defoverridable query: 4
      end
    end

    @callback query(
                Postgrex.conn(),
                iodata(),
                list(),
                [Postgrex.execute_option()]
              ) ::
                {:ok, Postgrex.Result.t()}
                | {:error, Exception.t()}
  end

  defmodule AyeSQL.Postgrex do
    @moduledoc false
    use AyeSQL.PostgrexBehaviour
  end

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
    iex> MyQueries.get_user([id: id], conn: connection)
    {:ok, ...}
    ```
    """
    use AyeSQL.Runner

    alias AyeSQL.Query
    alias AyeSQL.Runner

    @impl true
    def run(%Query{statement: stmt, arguments: args}, options) do
      module = Application.get_env(:ayesql, :postgrex_module, AyeSQL.Postgrex)
      query_options = Keyword.drop(options, [:conn, :into])
      conn = get_connection(options)

      with {:ok, result} <- module.query(conn, stmt, args, query_options) do
        result = Runner.handle_result(result, options)
        {:ok, result}
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
