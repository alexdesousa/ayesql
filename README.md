# AyeSQL

![Build status](https://github.com/alexdesousa/ayesql/actions/workflows/checks.yml/badge.svg) [![Hex pm](http://img.shields.io/hexpm/v/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql) [![hex.pm downloads](https://img.shields.io/hexpm/dt/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql) [![Coverage Status](https://coveralls.io/repos/github/alexdesousa/ayesql/badge.svg?branch=master)](https://coveralls.io/github/alexdesousa/ayesql?branch=master)

> **Aye** _/ʌɪ/_ _exclamation (archaic dialect)_: said to express assent; yes.

_AyeSQL_ is a library for using raw SQL.

## Overview

Inspired by Clojure library [Yesql](https://github.com/krisajenkins/yesql),
_AyeSQL_ tries to find a middle ground between strings with raw SQL queries and
SQL DSLs. This library aims to:

- Keep SQL in SQL files.
- Generate easy to use Elixir functions for every query.
- Parameterize queries using maps and keyword lists.
- Allow query composablity.
- Work out-of-the-box with PostgreSQL using
  [Ecto](https://github.com/elixir-ecto/ecto_sql) or
  [Postgrex](https://github.com/elixir-ecto/postgrex).
- Work out-of-the-box with DuckDB using
  [Duckdbex](https://github.com/AlexR2D2/duckdbex).

If you want to know more about AyeSQL:

- [Small example](#small-example)
- [Syntax](#syntax)

  + [Naming queries](#naming-queries)
  + [Parameters](#parameters)
  + [Mandatory parameters](#mandatory-parameters)
  + [Query composition](#query-composition)
  + [Optional fragments](#optional-fragments)
  + [IN statement](#in-statement)
  + [Subqueries and subfragments](#subqueries-and-subfragments)

- [Installation](#installation)

And the following additional links provide more information about the library:

- [Full Documentation](https://hexdocs.pm/ayesql)
- [AyeSQL: Writing Raw SQL in Elixir](https://thebroken.link/ayesql-writing-raw-sql-in-elixir/)
- [Why raw SQL?](https://hexdocs.pm/ayesql/why-raw-sql.html)
- [Dynamic queries with EEx](https://hexdocs.pm/ayesql/dynamic-queries-with-eex.html)
- [Adding support to other databases](https://hexdocs.pm/ayesql/query-runners.html)

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

### Parameters

There are two types of parameters:

- Mandatory: for passing parameters to a query. They start with `:` e.g.
  `:hostname`.
- Optional: for query composability. They start with `:_` e.g. `:_order_by`.

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

### Optional Fragments

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
> iex> params = [architecture: "AMD64", _order_by: &Queries.descending/2]
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

### Subqueries and Subfragments

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

> **Note**: If you're using this level of composability and it fits your use
> case, consider using either:
> - [Ecto](https://hexdocs.pm/ecto/Ecto.html)
> - [EEx templates](https://hexdocs.pm/ayesql/dynamic-queries-with-eex.html)

## Installation

AyeSQL is available as a Hex package. To install, add it to your
dependencies in your `mix.exs` file:

```elixir
def deps do
  [{:ayesql, "~> 1.1"}]
end
```

If you're going to use any of the provided query runners, then you should add
their dependencies as well:

- Add `:ecto_sql` for `AyeSQL.Runner.Ecto` (default runner).
- Add `:postgrex` for `AyeSQL.Runner.Postgrex`.
- Add `duckdbex` for `AyeSQL.Runner.Duckdbex`.
- Add `:ecto_sql` and `:postgrex` for running queries using `Ecto` in a
  `PostgreSQL` database.

## Author

Alexander de Sousa.

## License

AyeSQL is released under the MIT License. See the LICENSE file for further
details.
