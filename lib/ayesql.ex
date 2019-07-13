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
    app =
      with app when app in [:ecto, :postgrex] <- options[:app] do
        app
      else
        _ -> :ecto
      end

    quote do
      import AyeSQL, only: [defqueries: 1]

      @ayesql_db_app unquote(app)
      @ayesql_db_conn unquote(options[:conn])
      @ayesql_db_repo unquote(options[:repo])

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
        AyeSQL.run(
          @ayesql_db_app,
          @ayesql_db_repo,
          @ayesql_db_conn,
          stmt,
          args
        )
      end
    end
  end

  # Runs a `stmt` with some `args` in an `app`.
  @doc false
  @spec run(Core.app(), term(), term(), Core.statement(), Core.arguments()) ::
          {:ok, term()} | {:error, term()}
  def run(app, repo, conn, stmt, args)

  def run(:ecto, nil, _, _, _) do
    {:error, "Missing `:repo` attribute in module definition"}
  end

  def run(:postgrex, _, nil, _, _) do
    {:error, "Missing `:conn` attribute in module definition"}
  end

  def run(:ecto, repo, _, stmt, args) do
    apply(Ecto.Adapters.SQL, :query, [repo, stmt, args])
  end

  def run(:postgrex, _, conn, stmt, args) do
    apply(Postgrex, :query, [conn, stmt, args])
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
  defmacro defqueries(file) do
    contents = File.read!(file)

    with {:ok, tokens, _} <- :queries_lexer.tokenize(contents),
         {:ok, ast}       <- :queries_parser.parse(tokens) do
      [
        (quote do: @external_resource unquote(file)),
        Core.create_queries(ast)
      ]
    else
      {:error, {line, module, error}} ->
        raise CompileError,
          file: "#{module}",
          line: line,
          description: "#{inspect error}"

      {line, module, error} ->
        raise CompileError,
          file: "#{module}",
          line: line,
          description: "#{inspect error}"
    end
  end
end
