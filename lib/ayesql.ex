defmodule AyeSQL do
  @moduledoc """
  > **Aye** _/ʌɪ/_ _exclamation (archaic dialect)_: said to express assent; yes.

  _AyeSQL_ is a small Elixir library for using raw SQL.

  ## Overview

  Inspired on Clojure library [Yesql](https://github.com/krisajenkins/yesql),
  _AyeSQL_ tries to find a middle ground between those two approaches by:

  - Keeping the SQL in SQL files.
  - Generating Elixir functions for every query.
  - Having named parameters and query composability easily.

  Using the previous query, we would create a SQL file with the following
  contents:

  ```sql
  -- name: get_day_interval
  -- docs: Gets days interval.
  SELECT generate_series(
           current_date - :days::interval, -- Named parameter :days
           current_date - interval '1 day',
           interval '1 day'
         )::date AS date;

  -- name: get_avg_clicks
  -- docs: Gets average click count.
      WITH computed_dates AS ( :get_day_interval )
    SELECT dates.date AS day, count(clicks.id) AS count
      FROM computed_date AS dates
           LEFT JOIN clicks AS clicks ON date(clicks.inserted_at) = dates.date
     WHERE clicks.link_id = :link_id -- Named parameter :link_id
  GROUP BY dates.date
  ORDER BY dates.date;
  ```

  In Elixir we would load all the queries in this file by doing the following:

  ```elixir
  defmodule Queries do
    use AyeSQL

    defqueries("queries.sql") # File name with relative path to SQL file.
  end
  ```

  And then we could execute the query as follows:

  ```elixir
  params = %{
    link_id: 42,
    days: %Postgrex.Interval{secs: 864000} # 10 days
  }

  {:ok, result} = Queries.get_avg_clicks(params, run?: true)
  ```
  """
  alias AyeSQL.Core

  @typedoc """
  AyeSQL query runners.
  """
  @type app :: :ecto | :postgrex

  @typedoc """
  AyeSQL query statement.
  """
  @type query :: Core.query()

  @doc """
  Uses `AyeSQL` for loading queries.

  The available options are:

  - `app` - The app that will run the query. Defaults to `:ecto`, but it
  can also be `:postgrex`.
  - `repo` - Database repo name. Used by `:ecto` app.
  - `conn` - Connection with the database. Used by `:postgrex` app.
  """
  defmacro __using__(options) do
    {module, conn_name} = get_options(options)

    quote do
      import AyeSQL, only: [defqueries: 1]

      @ayesql_db_module unquote(module)
      @ayesql_db_conn_name unquote(conn_name)

      @doc """
      Runs the `query`. On error, fails.
      """
      @spec run!(AyeSQL.query()) :: term() | no_return()
      def run!(query)

      def run!(query) do
        case run(query) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise RuntimeError, message: reason
        end
      end

      @doc """
      Runs the `query`.
      """
      @spec run(AyeSQL.query()) :: {:ok, term()} | {:error, term()}
      def run(query)

      def run({stmt, args}) when is_binary(stmt) and is_list(args) do
        AyeSQL.run(@ayesql_db_module, @ayesql_db_conn_name, stmt, args)
      end

      ########################
      # Helpers for inspection

      @doc false
      @spec __db_module__() :: module()
      def __db_module__, do: @ayesql_db_module

      @doc false
      @spec __db_conn_name__() :: term()
      def __db_conn_name__, do: @ayesql_db_conn_name
    end
  end

  # Runs a `stmt` with some `args` in an `app`.
  @doc false
  @spec run(module(), term(), Core.statement(), Core.arguments()) ::
          {:ok, term()} | {:error, term()}
  def run(module, conn_name, stmt, args)

  def run(module, conn_name, stmt, args) do
    apply(module, :query, [conn_name, stmt, args])
  end

  @doc """
  Macro to load queries from a `file`.

  Let's say we have the file `sql/my_queries.sql` with the following contents:

  ```
  -- name: get_user
  -- docs: Gets user by username
  SELECT *
    FROM users
   WHERE username = :username;
  ```

  We can load our queries to Elixir using the macro `defqueries/1` as follows:

  ```
  defmodule Queries do
    use AyeSQL

    defqueries("sql/my_queries.sql")
  end
  ```

  We can now do the following to get the SQL and the ordered arguments:

  ```
  iex(1)> Queries.get_user!(%{username: "some_user"})
  {"SELECT * FROM user WHERE username = $1", ["some_user"]}
  ```

  If we would like to execute the previous query directly, the we could do the
  following:

  ```
  iex(1)> Queries.get_user!(%{username: "some_user"}, run?: true)
  %Postgrex.Result{...}
  ```

  We can also run the query by composing it with the `Queries.run/1` function
  generated in the module e.g:
  ```
  iex(1)> %{username: "some_user"} |> Queries.get_user!() |> Queries.run!()
  %Postgrex.Result{...}
  ```
  """
  defmacro defqueries(relative) do
    dirname = Path.dirname(__CALLER__.file)
    filename = Path.expand("#{dirname}/#{relative}")

    [
      (quote do: @external_resource unquote(filename)),
      Core.create_queries(filename)
    ]
  end

  #########
  # Helpers

  # Returns valid options or fails
  @spec get_options(keyword()) :: {module(), term()} | no_return()
  defp get_options(options) do
    app = options[:app]
    repo = options[:repo]
    conn = options[:conn]

    get_options(app, repo, conn)
  end

  # Returns valid options or fails
  @spec get_options(app(), term(), term()) :: {module(), term()} | no_return()
  defp get_options(app, repo, conn)

  defp get_options(:ecto, nil, _conn) do
    raise ArgumentError, "Repo cannot be nil for ecto"
  end

  defp get_options(:postgrex, _repo, nil) do
    raise ArgumentError, "Connection cannot be nil for Postgrex"
  end

  defp get_options(:ecto, repo, _conn) do
    {Ecto.Adapters.SQL, repo}
  end

  defp get_options(:postgrex, _repo, conn) do
    {Postgrex, conn}
  end

  defp get_options(nil, repo, _conn) do
    get_options(:ecto, repo, nil)
  end
end
