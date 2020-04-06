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
      repo = get_repo(options)

      with {:ok, result} <- SQL.query(repo, stmt, args) do
        Runner.handle_result(result)
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
  end
end
