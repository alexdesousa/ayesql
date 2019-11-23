defmodule AyeSQL do
  @moduledoc """
  > **Aye** _/ʌɪ/_ _exclamation (archaic dialect)_: said to express assent; yes.

  _AyeSQL_ is a library for using raw SQL.

  ## Overview

  Inspired by Clojure library [Yesql](https://github.com/krisajenkins/yesql),
  _AyeSQL_ tries to find a middle ground between strings with raw SQL queries and
  SQL DSLs by:

  - Keeping SQL in SQL files.
  - Generating Elixir functions for every query.
  - Supporting mandatory and optional named parameters.
  - Allowing query composability with ease.
  - Working out of the box with PostgreSQL using
    [Ecto](https://github.com/elixir-ecto/ecto_sql) or
    [Postgrex](https://github.com/elixir-ecto/postgrex):
  - Being extended to support other databases via the behaviour `AyeSQL.Runner`.

  ## Small Example

  Let's say we have an
  [SQL query](https://stackoverflow.com/questions/39556763/use-ecto-to-generate-series-in-postgres-and-also-retrieve-null-values-as-0)
  to retrieve the click count of a certain type of link every day of the last `X`
  days. In raw SQL this could be written as:

  ```sql
      WITH computed_dates AS (
             SELECT dates::date AS date
               FROM generate_series(
                      current_date - $1::interval,
                      current_date - interval '1 day',
                      interval '1 day'
                    ) AS dates
           )
    SELECT dates.date AS day, count(clicks.id) AS count
      FROM computed_dates AS dates
           LEFT JOIN clicks AS clicks ON date(clicks.inserted_at) = dates.date
     WHERE clicks.link_id = $2
  GROUP BY dates.date
  ORDER BY dates.date;
  ```

  The equivalent query in Ecto would be:

  ```elixir
  dates = ~s(
  SELECT generate_series(
           current_date - ?::interval,
           current_date - interval '1 day',
           interval '1 day'
         )::date AS d
  )

  from(
    c in "clicks",
    right_join: day in fragment(dates, ^days),
    on: day.d == fragment("date(?)", c.inserted_at),
    where: c.link_id = ^link_id
    group_by: day.d,
    order_by: day.d,
    select: %{
      day: fragment("date(?)", day.d),
      count: count(c.id)
    }
  )
  ```

  Using fragments can get convoluted and difficult to maintain. In AyeSQL, the
  equivalent would be to create an SQL file with the query e.g. `queries.sql`:

  ```sql
  -- name: get_day_interval
  SELECT datetime::date AS date
    FROM generate_series(
          current_date - :days::interval, -- Named parameter :days
          current_date - interval '1 day',
          interval '1 day'
        );

  -- name: get_avg_clicks
  -- docs: Gets average click count.
      WITH computed_dates AS ( :get_day_interval ) -- Composing with another query
    SELECT dates.date AS day, count(clicks.id) AS count
      FROM computed_date AS dates
          LEFT JOIN clicks AS clicks ON date(clicks.inserted_at) = dates.date
    WHERE clicks.link_id = :link_id -- Named parameter :link_id
  GROUP BY dates.date
  ORDER BY dates.date;
  ```

  In Elixir, we would load all the queries in this file by creating the following
  module:

  ```elixir
  defmodule Queries do
    use AyeSQL, repo: MyRepo

    defqueries("queries.sql") # File name with relative path to SQL file.
  end
  ```

  or using the macro `defqueries/3`:

  ```elixir
  import AyeSQL, only: [defqueries: 3]

  defqueries(Queries, "queries.sql", repo: MyRepo)
  ```

  Both approaches will create a module called `Queries` with all the queries
  defined in `queries.sql`.

  And then we could execute the query as follows:

  ```elixir
  iex> params = [
  ...>   link_id: 42,
  ...>   days: %Postgrex.Interval{secs: 864_000} # 10 days
  ...> ]
  iex> Queries.get_avg_clicks(params, run?: true)
  {:ok,
    [
      %{day: ..., count: ...},
      %{day: ..., count: ...},
      %{day: ..., count: ...},
      ...
    ]
  }
  ```
  """
  alias AyeSQL.Query
  alias AyeSQL.Parser

  @doc """
  Uses `AyeSQL` for loading queries.

  By default, supports the option `runner` (see `AyeSQL.Runner` behaviour).

  Any other option will be passed to the runner.
  """
  defmacro __using__(options) do
    {db_runner, db_options} = Keyword.pop(options, :runner, AyeSQL.Runner.Ecto)

    quote do
      import AyeSQL, only: [defqueries: 1]

      @__db_runner__ unquote(db_runner)
      @__db_options__ unquote(db_options)

      @doc """
      Runs the `query`. On error, fails.
      """
      @spec run!(Query.t()) :: term() | no_return()
      @spec run!(Query.t(), keyword()) :: term() | no_return()
      def run!(query, options \\ [])

      def run!(query, options) do
        case run(query, options) do
          {:ok, result} ->
            result

          {:error, reason} ->
            raise RuntimeError, message: reason
        end
      end

      @doc """
      Runs the `query`.
      """
      @spec run(Query.t()) :: {:ok, term()} | {:error, term()}
      @spec run(Query.t(), keyword()) :: {:ok, term()} | {:error, term()}
      def run(query, options \\ [])

      def run(%Query{} = query, options) do
        db_options = Keyword.merge(@__db_options__, options)

        AyeSQL.run(@__db_runner__, query, db_options)
      end

      ########################
      # Helpers for inspection

      @doc false
      @spec __db_runner__() :: module()
      def __db_runner__, do: @__db_runner__

      @doc false
      @spec __db_options__() :: term()
      def __db_options__, do: @__db_options__
    end
  end

  # Runs a `stmt` with some `args` in an `app`.
  @doc false
  @spec run(module(), Query.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def run(module, query, options)

  def run(module, %Query{} = query, options) do
    module.run(query, options)
  end

  @doc """
  Macro to load queries from a `file`.

  Let's say we have the file `lib/sql/queries.sql` with the following contents:

  ```sql
  -- name: get_user
  -- docs: Gets user by username
  SELECT *
    FROM users
   WHERE username = :username;
  ```

  Then we can load our queries to Elixir using the macro `defqueries/1`:

  ```
  # file: lib/queries.ex
  defmodule Queries do
    use AyeSQL, repo: MyRepo

    defqueries("sql/queries.sql")
  end
  ```

  or the macro `defqueries/3`:

  ```
  # file: lib/queries.ex
  import AyeSQL, only: [defqueries: 3]

  defqueries(Queries, "sql/queries.ex", repo: MyRepo)
  ```

  And finally we can inspect the query:

  ```
  iex(1)> Queries.get_user!(username: "some_user")
  {:ok,
    %AyeSQL.Query{
      statement: "SELECT * FROM user WHERE username = $1",
      arguments: ["some_user"]
    }
  }
  ```

  or run it:

  ```
  iex(1)> Queries.get_user!(username: "some_user", run?: true)
  {:ok,
    [
      %{username: ..., ...}
    ]
  }
  ```

  For running it by default, we can set the following in our configuration:

  ```
  config :ayesql, run?: true
  ```
  """
  defmacro defqueries(relative) do
    dirname = Path.dirname(__CALLER__.file)
    filename = Path.expand("#{dirname}/#{relative}")

    [
      quote(do: @external_resource(unquote(filename))),
      Parser.create_queries(filename)
    ]
  end

  @doc """
  Macro to load queries from a `file` and create a module for them.

  Same as `defqueries/1`, but creates a module e.g for the query file
  `lib/sql/queries.sql` we can use this macro as follows:

  ```
  # file: lib/queries.ex
  import AyeSQL, only: [defqueries: 3]

  defqueries(Queries, "sql/queries.sql", repo: MyRepo)
  ```

  This will generate the module `Queries` and it'll contain all the SQL
  statements included in `sql/queries.sql`.
  """
  defmacro defqueries(module, relative, options) do
    quote do
      defmodule unquote(module) do
        @moduledoc """
        This module defines functions for queries in `#{unquote(relative)}`
        """
        use AyeSQL, unquote(options)

        defqueries(unquote(relative))
      end
    end
  end
end
