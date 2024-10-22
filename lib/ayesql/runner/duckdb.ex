if Code.ensure_loaded?(Duckdbex) do
  defmodule AyeSQL.DuckdbexBehaviour do
    @moduledoc false

    defmacro __using__(_) do
      quote do
        @behaviour AyeSQL.DuckdbexBehaviour

        @impl AyeSQL.DuckdbexBehaviour
        def query(conn, stmt, args) do
          with {:ok, res} <- Duckdbex.query(conn, stmt, args) do
            columns = Duckdbex.columns(res)
            rows = Duckdbex.fetch_all(res)
            result = %{rows: rows, columns: columns}

            {:ok, result}
          end
        end

        defoverridable query: 3
      end
    end

    @callback query(
                Duckdbex.connection(),
                iodata(),
                list()
              ) ::
                {:ok, %{:rows => [list()], :columns => list()}}
                | {:error, Duckdbex.reason()}
  end

  defmodule AyeSQL.Duckdbex do
    @moduledoc false
    use AyeSQL.DuckdbexBehaviour
  end

  defmodule AyeSQL.Runner.Duckdbex do
    @moduledoc """
    This module defines `Duckdbex` default adapter.

    Can be used as follows:

    ```elixir
    defmodule MyQueries do
      use AyeSQL,
        runner: AyeSQL.Runner.Duckdbex

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
      module = Application.get_env(:ayesql, :duckdbex_module, AyeSQL.Duckdbex)

      conn =
        options[:conn] ||
          raise ArgumentError, message: "Connection `:conn` cannot be `nil`"

      with {:ok, result} <- module.query(conn, stmt, args) do
        {:ok, Runner.handle_result(result, options)}
      end
    end
  end
end
