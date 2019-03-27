defmodule AyeSQL do
  @moduledoc """
  [![Build Status](https://travis-ci.org/alexdesousa/ayesql.svg?branch=master)](https://travis-ci.org/alexdesousa/ayesql) [![Hex pm](http://img.shields.io/hexpm/v/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql) [![hex.pm downloads](https://img.shields.io/hexpm/dt/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql)

  > **Aye** _/ʌɪ/_ _exclamation (archaic dialect)_: said to express assent; yes.

  _AyeSQL_ is a small Elixir library for using raw SQL.

  ## Why raw SQL?

  Writing and running raw SQL in Elixir is not pretty. Not only the lack of
  syntax highlighting is horrible, but also substituting parameters into the
  query string can be unmaintainable e.g:

  ```elixir
  query =
    \"\"\"
      SELECT hostname, AVG(ram_usage) AS avg_ram
        FROM server
       WHERE hostname IN ($1, $2, $3)
             AND location = $4
    GROUP BY hostname
    \"\"\"
  arguments = ["server_0", "server_1", "server_2", "Barcelona"]
  Postgrex.query(conn, query, arguments)
  ```

  Adding more `hostname`s to the previous query is a nightmare, involving
  `binary()` manipulation to add the correct index to the query.

  Thankfully, we have [Ecto](https://github.com/elixir-ecto/ecto), which provides
  a great DSL for generating database queries at runtime. The same query in Ecto
  e.g:

  ```elixir
  servers = ["server_0", "server_1", "server_2"]
  location = "Barcelona"

  from s in "server",
    where: s.location == ^location and s.hostname in ^servers,
    select: %{hostname: s.hostname, avg_ram: avg(s.ram_usage)}
  ```

  Pretty straightforward and maintainable.

  So, **why raw SQL?**. Though Ecto is quite good with simple queries, complex
  queries often require the use of fragments, ruining the abstraction and making
  the code harder to read e.g:

  Let's say we have the following
  [SQL query](https://stackoverflow.com/questions/39556763/use-ecto-to-generate-series-in-postgres-and-also-retrieve-null-values-as-0)
  to retrieve the click count of a certain type of link every day of the last `X`
  days. In raw SQL this could be written as:

  ```sql
      WITH computed_dates AS (
            SELECT generate_series(
                     current_date - $1::interval,
                     current_date - interval '1 day',
                     interval '1 day'
                   )::date AS date
           )
    SELECT dates.date AS day, count(clicks.id) AS count
      FROM computed_dates AS dates
           LEFT JOIN clicks AS clicks ON date(clicks.inserted_at) = dates.date
     WHERE clicks.link_id = $2
  GROUP BY dates.date
  ORDER BY dates.date;
  ```

  Where `$1` is the interval (`%Postgrex.Interval{}` struct) and `$2` is some
  link ID. The query is easy to understand and easy to maintain.

  The same query in Ecto could be written as:

  ```elixir
  dates =
    \"\"\"
    SELECT generate_series(
            current_date - ?::interval,
            current_date - interval '1 day',
            interval '1 day'
          )::date AS d
    \"\"\"
  from(
    c in "clicks",
    right_join: day in fragment(dates, ^days),
    on: day.d == fragment("date(?)", c.inserted_at),
    where: c.link_id == ^link_id,
    group_by: day.d,
    order_by: day.d,
    select: %{
      day: fragment("date(?)", day.d),
      count: count(c.id)
    }
  )
  ```

  The previous code is hard to read and hard to maintain:

  - Not only knowledge of SQL is required, but also knowledge of the
  intricacies of using Ecto fragments.
  - Queries using fragments cannot use aliases defined in schemas, so the
  code becomes inconsistent.

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
  iex(1)> params = %{
  iex(1)>   link_id: 42,
  iex(1)>   days: %Postgrex.Interval{secs: 864000} # 10 days
  iex(1)> }
  iex(2)> Queries.get_avg_clicks(params, run? true)
  {:ok, %Postgrex.Result{...}}
  ```

  ## Basic syntax

  A SQL file can have as many queries as you want as long as:

  1. They are separated by `;`
  2. They are named: Before the query, add a comment with the keyword `name:`.
    This name will be used for the functions' names e.g
    ```sql
    -- Generates the functions get_servers/1 and get_servers/2
    -- name: get_servers
    SELECT hostname
      FROM server;
    ```

  And optionally they can have:

  1. Named parameters: Identified by a `:` followed by the name of the
    parameter e.g:
    ```sql
    -- These functions receive a map or a Keyword with the parameter :hostname.
    -- name: get_server
    SELECT * FROM server WHERE hostname = :hostname
    ```
  2. SQL queries calls: Identified by a `:` followed by the name of the query in
    the same file e.g:
    ```sql
    -- name: get_locations
    SELECT id
      FROM location
     WHERE region = :region;

    -- This will compose :get_locations with get_servers_by_location.
    -- The function will receive a map or a Keyword with the parameter :region.
    -- name: get_servers_by_location
    SELECT *
      FROM servers
     WHERE location_id IN ( :get_locations );
    ```
  3. Documentation: Before the query, add a comment with the keyword `docs:`.
    This string will be used as documentation for the function e.g:
    ```sql
    -- name: get_servers
    -- docs: Gets all the servers hostnames.
    SELECT hostname
      FROM server;
    ```

  ## `IN` statement

  Let's say we have the following query loaded in the module `Server`:

  ```sql
  -- name: get_avg_ram
    SELECT hostname, AVG(ram_usage) AS avg_ram
      FROM server
     WHERE hostname IN (:hostnames)
           AND location = :location
  GROUP BY hostname;
  ```

  It is possible to do the following:

  ```elixir
  iex(1)> hosts = ["server_0", "server_1", "server_2"]
  iex(2)> params = %{hostnames: {:in, hosts}, location: "Barcelona"}
  iex(3)> Server.get_avg_ram(params, run?: true)
  {:ok, %Postgrex.Result{...}}
  ```

  ## Query composability at runtime

  Let's say we have the following query loaded in the module `Server`:

  ```sql
  -- name: get_servers
    SELECT hostname
      FROM server
     WHERE region = :region;
  ```

  It is possible to do the following:

  ```elixir
  iex(1)> query = &Server.get_server/2
  iex(2)> params = %{hostnames: query, location: "Barcelona", region: "Spain"}
  iex(3)> Server.get_avg_ram(params, run?: true)
  {:ok, %Postgrex.Result{...}}
  ```

  ## Installation

  `AyeSQL` is available as a Hex package. To install, add it to your
  dependencies in your `mix.exs` file:

  ```elixir
  def deps do
    [{:ayesql, "~> 0.1"}]
  end
  ```
  """

  @doc """
  Uses `AyeSQL` for loading queries.

  The available options are:

  - `app` - The app that will run the query. Defaults to `:ecto`, but it
  can also be `:postgrex`.
  - `repo` - Database repo name. Used by `:ecto` app.
  - `conn` - Connection with the database. Used by `:postgrex` app.
  """
  defmacro __using__(options) do
    quote do
      import AyeSQL, only: [defqueries: 1]

      @ayesql_db_app unquote(options[:app] || :ecto)
      @ayesql_db_conn unquote(options[:conn])
      @ayesql_db_repo unquote(options[:repo])

      @doc """
      Runs the `query`. On error, fails.
      """
      def run!(query) do
        case run(query) do
          {:ok, result} ->
            result
          {:error, reason} ->
            raise reason
        end
      end

      @doc """
      Runs the `query`.
      """
      @spec run({binary(), list()}) :: {:ok, term()} | {:error, term()}
      def run(query)

      def run({stmt, args}) when is_binary(stmt) and is_list(args) do
        run(@ayesql_db_app, stmt, args)
      end
      def run(_) do
        {:error, "Bad query"}
      end

      @doc false
      def run(:ecto, stmt, args) do
        apply(Ecto.Adapters.SQL, :query, [@ayesql_db_repo, stmt, args])
      end
      def run(:postgrex, stmt, args) do
        apply(Postgrex, :query, [@ayesql_db_conn, stmt, args])
      end
    end
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

    defqueries("path/to/sql/file.sql")
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
      functions =
        ast
        |> Enum.map(&AyeSQL.create_query/1)
      functions_macro = for function <- functions do
        quote do
          unquote(function)
        end
      end
      external_resource_macro = quote do
        @external_resource unquote(file)
      end

      [functions_macro, external_resource_macro]
    end
  end

  #########
  # Helpers

  @doc false
  # Creates quoted query functions (with and without bang).
  def create_query({name, docs, content}) do
    content =
      content
      |> join_fragments([])
      |> Macro.escape()

    quote do
      unquote(create_query(name, docs, content))

      unquote(create_query!(name, docs))
    end
  end

  @doc false
  # Creates query function with bang.
  def create_query!(name, docs) do
    bang = String.to_atom("#{name}!")

    quote do
      @doc "#{unquote(docs)}. On error, fails."
      @spec unquote(bang)(map())
              :: {binary(), list()} | no_return()
      @spec unquote(bang)(map(), Keyword.t())
              :: {binary(), list()} | no_return()
      def unquote(bang)(params, options \\ []) do
        case unquote(name)(params, options) do
          {:ok, result} ->
            result
          {:error, reason} ->
            raise reason
        end
      end
    end
  end

  @doc false
  # Creates query function without bang.
  def create_query(name, docs, content) do
    quote do
      @doc "#{unquote(docs)}"
      @spec unquote(name)(map())
              :: {:ok, {binary(), list()}} | {:error, term()}
      @spec unquote(name)(map(), Keyword.t())
              :: {:ok, {binary(), list()}} | {:error, term()}
      def unquote(name)(params, options \\ []) do
        index = options[:index] || 1

        content = AyeSQL.expand(__MODULE__, unquote(content))

        base = {index, [], []}

        with {:ok, result} <- AyeSQL.evaluate(content, base, params) do
          if options[:run?], do: run(result), else: {:ok, result}
        end
      end
    end
  end

  @doc false
  # Joins string fragments.
  def join_fragments([], acc) do
    Enum.reverse(acc)
  end
  def join_fragments(values, acc) do
    case Enum.split_while(values, &is_binary/1) do
      {new_values, [diff | rest]} ->
        new_acc = [diff, Enum.join(new_values, " ") | acc]
        join_fragments(rest, new_acc)

      {new_values, []} ->
        new_acc = [Enum.join(new_values, " ") | acc]
        join_fragments([], new_acc)

    end
  end

  @doc false
  # Fetches values from a map or a Keyword list.
  def fetch(values, atom, default \\ nil)

  def fetch(values, atom, default) when is_map(values) do
    Map.get(values, atom, default)
  end
  def fetch(values, atom, default) when is_list(values) do
    Keyword.get(values, atom, default)
  end

  @doc false
  # Expands tokens to functions.
  def expand(module, content) when is_list(content) do
    Enum.map(content, fn value -> do_expand(module, value) end)
  end

  @doc false
  # Expands a token to a function
  def do_expand(_, value) when is_binary(value) do
    expand_binary_fn(value)
  end
  def do_expand(module, key) when is_atom(key) do
    functions =
      :functions
       |> module.module_info()
       |> Enum.filter(fn {param, value} -> param == key and value == 2 end)
    if functions == [] do
      expand_param_fn(key)
    else
      expand_function_fn(module, key)
    end
  end

  @doc false
  # Function to process binaries.
  def expand_binary_fn(value) do
    fn {index, stmt, args}, _ ->
      {:ok, {index, [value | stmt], args}}
    end
  end

  @doc false
  # Function to process parameters.
  def expand_param_fn(key) do
    fn acc, params ->
      case fetch(params, key) do
        nil ->
          {:error, "Cannot find #{key} in parameters"}
        value ->
          expand_value(value, acc, params)
      end
    end
  end

  @doc false
  # Expands values
  def expand_value({:in, vals}, {index, stmt, args}, _) when is_list(vals) do
    {next_index, variables} = expand_list(index, vals)
    new_stmt = [variables | stmt]
    new_args = Enum.reverse(vals) ++ args
    {:ok, {next_index, new_stmt, new_args}}
  end
  def expand_value(fun, {index, stmt, args}, params) when is_function(fun) do
    with {:ok, {new_stmt, new_args}} <- fun.(params, [index: index]) do
      new_index = index + length(new_args)
      new_stmt = [new_stmt | stmt]
      new_args = Enum.reverse(new_args) ++ args
      {:ok, {new_index, new_stmt, new_args}}
    end
  end
  def expand_value(value, {index, stmt, args}, _) do
    variable = "$#{inspect index}"
    {:ok, {index + 1, [variable | stmt], [value | args]}}
  end

  @doc false
  # Expands a list to a list of variables.
  def expand_list(index, list) do
    {next_index, variables} =
      Enum.reduce(
        list,
        {index, []},
        fn _, {index, acc} -> {index + 1, ["$#{inspect index}" | acc]} end
      )
    variables =
      variables
      |> Enum.reverse()
      |> Enum.join(",")
    {next_index, "#{variables}"}
  end

  @doc false
  # Function to process function calls.
  def expand_function_fn(module, key) do
    fn {index, stmt, args}, params ->
      fun_args = [params, [index: index]]
      with {:ok, {new_stmt, new_args}} <- apply(module, key, fun_args) do
        new_index = index + length(new_args)
        new_stmt = [new_stmt | stmt]
        new_args = Enum.reverse(new_args) ++ args
        {:ok, {new_index, new_stmt, new_args}}
      end
    end
  end

  @doc false
  # Evaluates the functions.
  def evaluate([], {_, stmt, acc}, _) do
    new_stmt =
      stmt
      |> Enum.reverse()
      |> Enum.join()
      |> String.replace(~r/ +/, " ")
      |> String.trim()
    new_acc =
      acc
      |> Enum.reverse()
    {:ok, {new_stmt, new_acc}}
  end
  def evaluate([fun | funs], acc, params) do
    with {:ok, new_acc} <- fun.(acc, params) do
      evaluate(funs, new_acc, params)
    end
  end
end
