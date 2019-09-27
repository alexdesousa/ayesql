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
    iex> MyQueries.get_user([id: id], run?: true, options: [conn: connection])
    {:ok, ...}
    ```
    """
    use AyeSQL.Runner

    @impl true
    def run(stmt, args, options) do
      conn = get_connection(options)

      case Postgrex.query(options[:conn], stmt, args) do
        {:ok, %Postgrex.Result{} = result} ->
          handle_result(result)

        {:error, %Postgrex.Error{} = error} ->
          handle_error(error)
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

    # Handles the result.
    @doc false
    @spec handle_result(Postgrex.Result.t()) :: {:ok, [map()]}
    def handle_result(result)

    def handle_result(%Postgrex.Result{columns: nil}) do
      {:ok, []}
    end

    def handle_result(%Postgrex.Result{columns: columns, rows: rows}) do
      columns = Enum.map(columns, &String.to_atom/1)

      result =
        rows
        |> Stream.map(&Stream.zip(columns, &1))
        |> Enum.map(&Map.new/1)

      {:ok, result}
    end

    # Handles the error.
    @doc false
    @spec handle_error(Postgrex.Error.t()) :: {:error, term()}
    def handle_error(%Postgrex.Error{postgres: reason}) do
      {:error, reason}
    end
  end
end
