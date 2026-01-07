defmodule AyeSQL do
  @moduledoc """
  _AyeSQL_ is a library for using raw SQL.

  > **Aye** _/ʌɪ/_ _exclamation (archaic dialect)_: said to express assent; yes.

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
  - Being extended to support other databases using the behaviour
    `AyeSQL.Runner`.

  ## Small Example

  Let's say we have a
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
  iex> Queries.get_avg_clicks(params)
  {:ok,
    [
      %{day: ..., count: ...},
      %{day: ..., count: ...},
      %{day: ..., count: ...},
      ...
    ]
  }
  ```
  AyeSQL also allows you to choose the type of returned data structures.
  Instead of the default map you can also pass an `into` option to your query
  possible values are:
  - an empty map: `Map.new()` or `%{}`
  - an empty list: `Keyword.new()` or `[]`
  - a struct
  - `:raw` which returns the unmodified Postgrex result

  ```elixir
  iex> Queries.get_avg_clicks(params, into: [])
  {:ok,
    [
      [day: ..., count: ...],
      [day: ..., count: ...],
      [day: ..., count: ...],
      ...
    ]
  }
  ```

  ```elixir
  iex> defmodule AvgClicks do defstruct [:day, :count] end
  iex> Queries.get_avg_clicks(params, into: AvgClicks)
  {:ok,
    [
      %AvgClicks{day: ..., count: ...},
      %AvgClicks{day: ..., count: ...},
      %AvgClicks{day: ..., count: ...},
      ...
    ]
  }
  ```
  """
  alias AyeSQL.Compiler
  alias AyeSQL.Query

  @doc """
  Uses `AyeSQL` for loading queries.

  By default, supports the option `runner` (see `AyeSQL.Runner` behaviour).

  Any other option will be passed to the runner.
  """
  @spec __using__(keyword()) :: Macro.t()
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
        AyeSQL.run(@__db_runner__, query, options)
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

  @doc """
  Evaluates the `contents` of a string with a query and generates an anonyous
  function that receives parameters and options.
  """
  @spec eval_query(binary()) ::
          (AyeSQL.Core.parameters(), AyeSQL.Core.options() ->
             {:ok, AyeSQL.Query.t() | term()}
             | {:error, AyeSQL.Error.t() | term()})
          | no_return()
  @spec eval_query(binary(), AyeSQL.Lexer.options()) ::
          (AyeSQL.Core.parameters(), AyeSQL.Core.options() ->
             {:ok, AyeSQL.Query.t() | term()}
             | {:error, AyeSQL.Error.t() | term()})
          | no_return()
  defdelegate eval_query(contents, options \\ []), to: AyeSQL.Compiler

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

  ## Multi-file Support

  You can load queries from multiple files using a list or glob patterns:

  ```
  # file: lib/queries.ex
  defmodule Queries do
    use AyeSQL, repo: MyRepo

    # List of files
    defqueries(["sql/users.sql", "sql/posts.sql", "sql/comments.sql"])

    # Or using glob patterns
    defqueries("sql/**/*.sql")
  end
  ```

  **Important notes for multi-file usage:**
  - Files matched by glob patterns are processed in alphabetical order
  - All query names must be unique across all files
  - Each file is tracked as an `@external_resource` for recompilation
  - Queries can reference other queries from any file using `:query_name` syntax

  or the macro `defqueries/3`:

  ```
  # file: lib/queries.ex
  import AyeSQL, only: [defqueries: 3]

  defqueries(Queries, "sql/queries.ex", repo: MyRepo)

  # Multi-file examples
  defqueries(Queries, ["sql/users.sql", "sql/posts.sql"], repo: MyRepo)
  defqueries(Queries, "sql/**/*.sql", repo: MyRepo)
  ```

  And finally we can inspect the query:

  ```
  iex(1)> Queries.get_user(username: "some_user", run: false)
  {:ok,
    %AyeSQL.Query{
      statement: "SELECT * FROM user WHERE username = $1",
      arguments: ["some_user"]
    }
  }
  ```

  or run it:

  ```
  iex(1)> Queries.get_user(username: "some_user")
  {:ok,
    [
      %{username: ..., ...}
    ]
  }
  ```
  """

  ####################
  # Helper Functions #
  ####################

  # Resolves input to list of absolute file paths
  @spec resolve_files(Path.t(), Path.t() | [Path.t()]) :: [Path.t()]
  defp resolve_files(dirname, path) when is_binary(path) do
    cond do
      String.contains?(path, ["*", "?", "["]) ->
        expand_glob(dirname, path)

      true ->
        [Path.expand("#{dirname}/#{path}")]
    end
  end

  defp resolve_files(dirname, paths) when is_list(paths) do
    paths
    |> Enum.map(&Path.expand("#{dirname}/#{&1}"))
    |> Enum.sort()
  end

  # Expands glob pattern to sorted list
  @spec expand_glob(Path.t(), Path.t()) :: [Path.t()]
  defp expand_glob(dirname, pattern) do
    full_pattern = "#{dirname}/#{pattern}"

    case Path.wildcard(full_pattern) do
      [] ->
        raise AyeSQL.CompileError,
          contents: "",
          line: 1,
          header: "No files matched pattern: #{pattern}",
          filename: "defqueries"

      files ->
        Enum.sort(files)
    end
  end

  # Loads all files with metadata
  @spec load_files([Path.t()]) :: [{Path.t(), binary()}]
  defp load_files([]) do
    raise AyeSQL.CompileError,
      contents: "",
      line: 1,
      header: "No files provided to defqueries",
      filename: "defqueries"
  end

  defp load_files(files) do
    Enum.map(files, fn file ->
      {file, File.read!(file)}
    end)
  end

  # Merges contents from multiple files
  @spec merge_contents([{Path.t(), binary()}]) :: binary()
  defp merge_contents(contents_with_metadata) do
    contents_with_metadata
    |> Enum.map(fn {_file, contents} -> contents end)
    |> Enum.join("\n\n")
  end

  # Checks for duplicate query names
  @spec check_duplicates!([{Path.t(), binary()}]) :: :ok
  defp check_duplicates!(contents_with_metadata) do
    name_to_files =
      contents_with_metadata
      |> Enum.flat_map(fn {file, contents} ->
        extract_query_names(contents)
        |> Enum.map(fn name -> {name, file} end)
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    duplicates =
      name_to_files
      |> Enum.filter(fn {_name, files} -> length(files) > 1 end)
      |> Enum.into(%{})

    unless Enum.empty?(duplicates) do
      raise_duplicate_error!(duplicates)
    end

    :ok
  end

  # Extracts query names from SQL contents
  @spec extract_query_names(binary()) :: [atom()]
  defp extract_query_names(contents) do
    case AyeSQL.Lexer.tokenize(contents) |> :ayesql_parser.parse() do
      {:ok, queries} ->
        queries
        |> Enum.map(fn {name, _docs, _fragments} -> name end)
        |> Enum.reject(&is_nil/1)

      {:error, _} ->
        []
    end
  end

  # Raises error for duplicates
  @spec raise_duplicate_error!(%{atom() => [Path.t()]}) :: no_return()
  defp raise_duplicate_error!(duplicates) do
    details =
      duplicates
      |> Enum.map(fn {name, files} ->
        file_list = Enum.map_join(files, ", ", &Path.basename/1)
        "  - #{name}: found in #{file_list}"
      end)
      |> Enum.join("\n")

    raise AyeSQL.CompileError,
      contents: "",
      line: 1,
      header: """
      Duplicate query names found across multiple files:

      #{details}

      Each query name must be unique across all loaded files.
      """,
      filename: "defqueries"
  end

  @spec defqueries(Path.t() | [Path.t()]) :: [Macro.t()]
  defmacro defqueries(path_or_paths) do
    dirname = Path.dirname(__CALLER__.file)

    # Resolve to list of absolute paths
    files = resolve_files(dirname, path_or_paths)

    # Load all files
    contents_with_metadata = load_files(files)

    # Check for duplicates
    check_duplicates!(contents_with_metadata)

    # Merge contents
    combined_contents = merge_contents(contents_with_metadata)

    # Track all files as external resources
    external_resources =
      Enum.map(files, fn file ->
        quote(do: @external_resource(unquote(file)))
      end)

    # Compile queries
    compiled = Compiler.compile_queries(combined_contents)

    # Return both external resources and compiled queries
    external_resources ++ [compiled]
  end

  @doc """
  Macro to load queries from one or more files and create a module for them.

  Same as `defqueries/1`, but creates a module e.g for the query file
  `lib/sql/queries.sql` we can use this macro as follows:

  ```
  # file: lib/queries.ex
  import AyeSQL, only: [defqueries: 3]

  defqueries(Queries, "sql/queries.sql", repo: MyRepo)
  ```

  ## Multi-file Support

  You can also load from multiple files or glob patterns:

  ```
  # List of files
  defqueries(Queries, ["sql/users.sql", "sql/posts.sql"], repo: MyRepo)

  # Glob pattern
  defqueries(Queries, "sql/**/*.sql", repo: MyRepo)
  ```

  This will generate the module `Queries` and it'll contain all the SQL
  statements included in the specified file(s). See `defqueries/1` for more
  details on multi-file behavior.
  """
  @spec defqueries(module(), Path.t() | [Path.t()], keyword()) :: Macro.t()
  defmacro defqueries(module, path_or_paths, options) do
    quote do
      defmodule unquote(module) do
        @moduledoc """
        This module defines functions for queries in `#{unquote(path_or_paths)}`
        """
        use AyeSQL, unquote(options)

        defqueries(unquote(path_or_paths))
      end
    end
  end
end
