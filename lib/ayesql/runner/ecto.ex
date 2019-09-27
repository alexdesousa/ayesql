if Code.ensure_loaded?(Ecto.Adapters.SQL) and Code.ensure_loaded?(Postgrex) do
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

    @impl true
    def run(stmt, args, options) do
      repo = get_repo(options)

      case Ecto.Adapters.SQL.query(repo, stmt, args) do
        {:ok, %Postgrex.Result{} = result} ->
          AyeSQL.Runner.Postgrex.handle_result(result)

        {:error, %Postgrex.Error{} = error} ->
          AyeSQL.Runner.Postgrex.handle_error(error)
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
