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

    alias AyeSQL.Runner

    @impl true
    def run(stmt, args, options) do
      repo = get_repo(options)

      with {:ok, result} <- Ecto.Adapters.SQL.query(repo, stmt, args) do
        Runner.handle_result(result)
      end
    end

    #########
    # Helpers

    # Gets repo module.
    @spec get_repo(keyword()) :: module() | no_return()
    defp get_repo(options) do
      with nil <- options[:repo] do
        raise ArgumentError, "Repo `:repo` cannot be nil"
      end
    end
  end
end
