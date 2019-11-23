# AyeSQL

[![Build Status](https://travis-ci.org/alexdesousa/ayesql.svg?branch=master)](https://travis-ci.org/alexdesousa/ayesql) [![Hex pm](https://img.shields.io/hexpm/v/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql) [![hex.pm downloads](https://img.shields.io/hexpm/dt/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql)

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

## Why raw SQL?

Writing and running raw SQL in Elixir is not pretty. Not only the lack of
syntax highlighting is horrible, but also substituting parameters into the
query string can be unmaintainable e.g:

```elixir
query =
  """
    SELECT hostname, AVG(ram_usage) AS avg_ram
      FROM server
     WHERE hostname IN ($1, $2, $3)
           AND location = $4
  GROUP BY hostname
  """
arguments = ["server_0", "server_1", "server_2", "Barcelona"]
Postgrex.query(conn, query, arguments)
```

Adding more hostnames to the previous query would be a nightmare. If
the `arguments` are generated dynamically, then editing this query would be
a challenging task.

Thankfully, we have [Ecto](https://github.com/elixir-ecto/ecto), which provides
a great DSL for generating database queries at runtime. The same query in Ecto
would be the following:

```elixir
servers = ["server_0", "server_1", "server_2"]
location = "Barcelona"

from s in "server",
  where: s.location == ^location and s.hostname in ^servers,
  select: %{hostname: s.hostname, avg_ram: avg(s.ram_usage)}
```

Pretty straightforward and maintainable.

If Ecto is so good for building queries, **why would you use raw SQL?**. Though
Ecto is quite good with simple queries, complex queries often require the use
of fragments, ruining the abstraction and making the code harder to read e.g:

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

Where `$1` is the interval (`%Postgrex.Interval{}` struct) and `$2` is some
link ID. The query is easy to understand and easy to maintain.

The same query in Ecto could be written as:

```elixir
dates =
  """
  SELECT generate_series(
           current_date - ?::interval,
           current_date - interval '1 day',
           interval '1 day'
         )::date AS d
  """

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

The previous code is hard to read and hard to maintain:

- Not only knowledge of SQL is required, but also knowledge of the
intricacies of using Ecto fragments.
- Queries using fragments cannot use aliases defined in schemas, so the
code becomes inconsistent.

## Small Example

In AyeSQL, the equivalent would be to create an SQL file with the query e.g.
`queries.sql`:

```sql
-- name: get_day_interval
-- This query do not have docs, so it's private.
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

## Syntax

An SQL file can have as many queries as you want as long as they are named.

For the following sections we'll assume we have:

- `lib/my_repo.ex` which is an `Ecto` repo called `MyRepo`.
- `lib/queries.sql` with SQL queries.
- `lib/queries.ex` with the following structure:

    ```elixir
    import AyeSQL, only: [defqueries: 3]

    defqueries(Queries, "queries.sql", repo: MyRepo)
    ```
- Running the queries by default by adding the following in `config/config.exs`:

    ```elixir
    config ayesql, run?: true
    ```

### Naming Queries

For naming queries, we add a comment with the keyword `-- name: ` followed by
the name of the function e.g the following query would generate the function
`Queries.get_hostnames/2`:

```sql
-- name: get_hostnames
SELECT hostname FROM server
```

Additionally, we could also add documentation for the query by adding a comment
with the keyword `-- docs: ` followed by the query's documentation e.g:

```sql
-- name: get_hostnames
-- docs: Gets hostnames from the servers.
SELECT hostname FROM server
```

> Important: if the function does not have `-- docs: ` it won't have
> documentation e.g. `@doc false`.

### Named Parameters

There are two types of named parameters:

- Mandatory: for passing parameters to a query. They start with `:` e.g.
  `:hostname`.
- Optional: for query composability. The start with `:_` e.g. `:_order_by`.

Additionaly, any query in a file can be accessed with its name adding `:` at
the front e.g `:get_hostnames`.

### Mandatory Parameters

Let's say we want to get the name of an operative system by architecture:

```sql
-- name: get_os_by_architecture
-- docs: Gets operative system's name by a given architecture.
SELECT name
  FROM operative_system
 WHERE architecture = :architecture
```

The previous query would generate the function
`Queries.get_os_by_architecture/2` that can be called as:

```elixir
iex> Queries.get_os_by_architecture(architecture: "AMD64")
{:ok,
  [
    %{name: "Debian Buster"},
    %{name: "Windows 10"},
    ...
  ]
}
```

### Query Composition

Now if we would like to get hostnames by architecture we could compose queries
by doing the following:

```sql
-- name: get_os_by_architecture
-- docs: Gets operative system's name by a given architecture.
SELECT name
  FROM operative_system
 WHERE architecture = :architecture

-- name: get_hostnames_by_architecture
-- docs: Gets hostnames by architecture.
SELECT hostname
  FROM servers
 WHERE os_name IN ( :get_os_by_architecture )
```

The previous query would generate the function
`Queries.get_hostnames_by_architecture/2` that can be called as:

```elixir
iex> Queries.get_hostnames_by_architecture(architecture: "AMD64")
{:ok,
  [
    %{hostname: "server0"},
    %{hostname: "server1"},
    ...
  ]
}
```

### Optional Parameters

Let's say that now we need to order ascending or descending by hostname by
using an optional `:_order_by` parameter e.g:

```sql
-- name: get_os_by_architecture
-- docs: Gets operative system's name by a given architecture.
SELECT name
  FROM operative_system
 WHERE architecture = :architecture

-- name: get_hostnames_by_architecture
-- docs: Gets hostnames by architecture.
SELECT hostname
  FROM servers
 WHERE os_name IN ( :get_os_by_architecture )
 :_order_by

-- name: ascending
ORDER BY hostname ASC

-- name: descending
ORDER BY hostname DESC
```

The previous query could be called as before:

```elixir
iex> Queries.get_hostnames_by_architecture(architecture: "AMD64")
{:ok,
  [
    %{hostname: "Barcelona"},
    %{hostname: "Granada"},
    %{hostname: "Madrid"},
    ...
  ]
}
```

or by order ascending:

```elixir
iex> params = [architecture: "AMD64", _order_by: :ascending]
iex> Queries.get_hostnames_by_architecture(params)
{:ok,
  [
    %{hostname: "Barcelona"},
    %{hostname: "Madrid"},
    %{hostname: "Granada"},
    ...
  ]
}
```

or descending:

```elixir
iex> params = [architecture: "AMD64", _order_by: :descending]
iex> Queries.get_hostnames_by_architecture(params)
{:ok,
  [
    %{hostname: "Zaragoza"},
    %{hostname: "Madrid"},
    %{hostname: "Granada"},
    ...
  ]
}
```

> Important: A query can be called by name e.g. `:descending` if it's defined
> in the same SQL file. Otherwise, we need to pass the function instead e.g.
> `Queries.descending/2`
>
> ```elixir
> iex> params = [architecture: "AMD64", _order_by: Queries.descending/2]
> iex> Queries.get_hostnames_by_architecture(params)
> {:ok,
>   [
>     %{hostname: "Zaragoza"},
>     %{hostname: "Madrid"},
>     %{hostname: "Granada"},
>     ...
>   ]
> }
> ```

### `IN` Statement

Lists in SQL might be tricky. That's why AyeSQL supports a special type for
them e.g:

Let's say we have the following query:

```sql
-- name: get_os_by_hostname
-- docs: Gets hostnames and OS names given a list of hostnames.
SELECT hostname, os_name
  FROM servers
 WHERE hostname IN (:hostnames)
```

It is possible to do the following:

```elixir
iex> params = [hostnames: {:in, ["server0", "server1", "server2"]}]
iex> Server.get_os_by_hostname(params)
{:ok,
  [
    %{hostname: "server0", os_name: "Debian Buster"},
    %{hostname: "server1", avg_ram: "Windows 10"},
    %{hostname: "server2", avg_ram: "Minix 3"}
  ]
}
```

## Query Runners

The purpose of runners is to be able to implement other database adapters.

By default, `AyeSQL` uses the runner `AyeSQL.Runner.Ecto`. This runner only has
one option which is `:repo` for the repo module. Additionally, it converts the
result to a list of maps.

Using other runners is as easy as setting them in the module definition as
follows:

```elixir
defmodule Queries do
  use AyeSQL, runner: IdemRunner, repository: MyRepo

  defqueries("queries.sql")
end
```

or

```elixir
import AyeSQL, only: [defqueries: 3]

defqueries(Queries, "queries.sql", runner: IdemRunner, repository: MyRepo)
```

For runners, there is only one callback to be implemented.

- `run/2`: which receives a `AyeSQL.Query.t()` and a `keyword()` list with
  extra options for the runner.

The following would be a runner for `Ecto` that does nothing to the result
(returns `Postgrex.Result.t()` and `Postgrex.Error.t()` structs):

```elixir
defmodule IdemRunner do
  use AyeSQL.Runner

  alias AyeSQL.Query

  @impl true
  def run(%Query{statement: stmt, arguments: args}, options) do
    repo = options[:repository] || raise ArgumentError, "No repo defined"

    Ecto.Adapters.SQL.query(repo, stmt, args)
  end
end
```

## Running Queries by Default

Queries are not run by default, but the `AyeSQL.Query.t()` struct is returned
instead. For running queries by default, we can add the following to the
config:

```elixir
use Mix.Config

config :ayesql,
  run?: true
```

And then we don't need to specify the `[run?: true]` options for every query.

## Installation

`AyeSQL` is available as a Hex package. To install, add it to your
dependencies in your `mix.exs` file:

```elixir
def deps do
  [{:ayesql, "~> 0.5"}]
end
```

If you're going to use any of the provided query runners, then you should add
their dependencies as well:

- Add `:ecto_sql` for `AyeSQL.Runner.Ecto` (default runner).
- Add `:postgrex` for `AyeSQL.Runner.Postgrex`.
- Add `:ecto_sql` and `:postgrex` for running queries using `Ecto` in a
  `PostgreSQL` database.

## Author

Alexander de Sousa.

## License

`AyeSQL` is released under the MIT License. See the LICENSE file for further
details.
