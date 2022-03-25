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
    """
    use AyeSQL.Runner

    alias AyeSQL.Query
    alias AyeSQL.Runner
    alias Ecto.Adapters.SQL

    @impl true
    def run(%Query{statement: stmt, arguments: args}, options) do
      query_options = Keyword.drop(options, [:repo, :into])
      repo = get_repo(options)

      with {:ok, result} <- SQL.query(repo, stmt, args, query_options) do
        result = Runner.handle_result(result, options)
        {:ok, result}
      end
    end

    #########
    # Helpers

    # Gets repo module.
    @spec get_repo(keyword()) :: module() | no_return()
    defp get_repo(options) do
      repo = options[:repo]

      case Code.ensure_loaded(repo) do
        {:module, ^repo} ->
          repo

        _ ->
          raise ArgumentError, "Invalid module for Ecto repo: #{inspect(repo)}"
      end
    end
  end
end
