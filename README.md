# AyeSQL

![Build status](https://github.com/alexdesousa/ayesql/actions/workflows/checks.yml/badge.svg) [![Hex pm](http://img.shields.io/hexpm/v/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql) [![hex.pm downloads](https://img.shields.io/hexpm/dt/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql) [![Coverage Status](https://coveralls.io/repos/github/alexdesousa/ayesql/badge.svg?branch=master)](https://coveralls.io/github/alexdesousa/ayesql?branch=master)

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
- Working out-of-the-box with PostgreSQL using
  [Ecto](https://github.com/elixir-ecto/ecto_sql) or
  [Postgrex](https://github.com/elixir-ecto/postgrex).
- Working out-of-the-box with any database that has Ecto support
  e.g. MySQL via [MyXQL](https://github.com/elixir-ecto/myxql).
- Being extended to support other databases via the behaviour `AyeSQL.Runner`.

If you want to know more why this project exists:

- [SQL in Elixir](#sql-in-elixir)
- [Why raw SQL?](#why-raw-sql)
- [AyeSQL: Writing Raw SQL in Elixir (External Link)](https://thebroken.link/ayesql-writing-raw-sql-in-elixir/)

If you want to know more about AyeSQL:

- [Small example](#small-example)
- [Syntax](#syntax)

  + [Naming queries](#naming-queries)
  + [Named parameters](#named-parameters)
  + [Mandatory parameters](#mandatory-parameters)
  + [Query composition](#query-composition)
  + [Optional parameters](#optional-parameters)
  + [IN statement](#in-statement)
  + [Subqueries](#subqueries)

- [Query runners](#query-runners)
- [Avoid running queries by default](#avoid-running-queries-by-default)
- [Installation](#installation)

## SQL in Elixir

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

## Why raw SQL

If Ecto is so good for building queries, **why would you use raw SQL?**. Though
Ecto is quite good with simple queries, complex custom queries often require the
use of fragments. Fragments are not pretty though there are workarounds using
macros to make them prettier.

It's easier to see with an example: let's say we have to
[retrieve the click count of a certain type of link every day of the last N days](https://stackoverflow.com/questions/39556763/use-ecto-to-generate-series-in-postgres-and-also-retrieve-null-values-as-0).

With complex queries, developers tend to start writing them in raw SQL:

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

Once we have the raw SQL, it's a bit easier to write our Ecto query. In this
case, this query should be written using fragments:

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

It's not the ideal solution (yet) and it's harder to maintain than the raw SQL
solution that would work out-of-the-box.

Only to get to the previous solution, the developer need to:

- Know the specific SQL dialect of the database they're using.
- Know Ecto's API and its limitations.

For both, raw SQL and Ecto query, the end result for this query would be the
same. With extra effort we found a subpar solution that gives us the same
result as our raw SQL.

The final, and sometimes, optional step would be to transform the Ecto query
into something a bit more maintainable.

```elixir
defmodule CustomDSL do
  defmacro date(date) do
    quote do
      fragment("date(?)", unquote(date))
    end
  end

  defmacro ndays(n) do
    query =
      """
      SELECT generate_series(
               current_date - ?::interval,
               current_date - interval '1 day',
               interval '1 day'
             )::date AS d
      """

    quote do
      fragment(unquote(query), unquote(n))
    end
  end
end

import CustomDSL

from(
  c in "clicks",
  right_join: day in ndays(^days),
  on: day.d == date(c.inserted_at),
  where: c.link_id = ^link_id
  group_by: day.d,
  order_by: day.d,
  select: %{
    day: date(day.d)
    count: count(c.id)
  }
)
```

The previous query is more readable, but requires knowledge of:

- The specific SQL dialect.
- Ecto's API and its limitations.
- Elixir's macros.
- Custom DSL API.

For some problems, getting to this final stage is preferable. However, for
some other problems, the raw SQL query would have been enough.

The raw SQL query was already a good solution to the problem. It only needs a
maintainable way to be parametrized. That's why AyeSQL exists.

## Small Example

In AyeSQL, the equivalent would be to create an SQL file with the query e.g.
`queries.sql`:

```sql
-- file: queries.sql
-- name: get_avg_clicks
-- docs: Gets average click count.
    WITH computed_dates AS (
      SELECT datetime::date AS date
      FROM generate_series(
        current_date - :days::interval, -- Named parameter :days
        current_date - interval '1 day',
        interval '1 day'
      )
    )
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
# file: lib/queries.ex
defmodule Queries do
  use AyeSQL, repo: MyRepo

  defqueries("queries.sql") # File name with relative path to SQL file.
end
```

or using the macro `defqueries/3`:

```elixir
# file: lib/queries.ex
import AyeSQL, only: [defqueries: 3]

defqueries(Queries, "queries.sql", repo: MyRepo)
```

> **Note**: The file name used in `defqueries` macro should be relative to the
> file where the macro is used.

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

Additionally, any query in a file can be accessed with its name adding `:` at
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

### IN Statement

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

### Subqueries

Subqueries can be composed directly, as show before, or via the `:inner` tuple
e.g. let's say we need to get the adults order by name in ascending order and
age in descending order:

```sql
-- name: ascending
ASC

-- name: descending
DESC

-- name: by_age
age :order_direction

-- name: by_name
name :order_direction

-- name: get_adults
-- docs: Gets adults.
SELECT name, age
  FROM person
 WHERE age >= 18
ORDER BY :order_by
```

Then our code in elixir would be:

```elixir
iex> order_by = [
...>   by_name: [order_direction: :ascending],
...>   by_age: [order_direction: :descending]
...> ]
iex> Queries.get_adults(order_by: {:inner, order_by, ", "})
{:ok,
  [
    %{name: "Alice", age: 42},
    %{name: "Bob", age: 21},
    ...
  ]
}
```

> **Note**: If you're using this level of composability, consider using Ecto if
> it fits your problem or stack.

## Query Runners

The purpose of runners is to be able to implement other database adapters.

By default, AyeSQL uses the runner `AyeSQL.Runner.Ecto`. This runner only has
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

## Avoid Running Queries by Default

Queries are run by default. To avoid this and get the `AyeSQL.Query.t()` struct
instead, set the option `run: false` on the top of the module e.g:

```elixir
defmodule Queries do
  use AyeSQL, repo: MyRepo, run: false

  defqueries("myqueries.sql")
end
```

or when running a query:

```elixir
iex> params = [
...>   link_id: 42,
...>   days: %Postgrex.Interval{secs: 864_000} # 10 days
...> ]
iex> Queries.get_avg_clicks(params)
{:ok, %AyeSQL.Query{statement: ..., arguments: ...}}
```

## Installation

AyeSQL is available as a Hex package. To install, add it to your
dependencies in your `mix.exs` file:

```elixir
def deps do
  [{:ayesql, "~> 1.0"}]
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

AyeSQL is released under the MIT License. See the LICENSE file for further
details.
