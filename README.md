# AyeSQL

[![Build Status](https://travis-ci.org/alexdesousa/ayesql.svg?branch=master)](https://travis-ci.org/alexdesousa/ayesql) [![Hex pm](http://img.shields.io/hexpm/v/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql) [![hex.pm downloads](https://img.shields.io/hexpm/dt/ayesql.svg?style=flat)](https://hex.pm/packages/ayesql)

> **Aye** _/ʌɪ/_ _exclamation (archaic dialect)_: said to express assent; yes.

_AyeSQL_ is a small Elixir library for using raw SQL.

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

Adding more `hostname`s to the previous query is a nightmare, editing strings
to add the correct index to the query.

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
SELECT datetime::date AS date
  FROM generate_series(
        current_date - :days::interval, -- Named parameter :days
        current_date - interval '1 day',
        interval '1 day'
      );

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
iex(1)>   days: %Postgrex.Interval{secs: 864_000} # 10 days
iex(1)> }
iex(2)> Queries.get_avg_clicks(params, run?: true)
{:ok, %Postgrex.Result{...}}
```

## Syntax

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
   SELECT * FROM server WHERE hostname = :hostname;
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
iex(1)> query = &Server.get_servers/2
iex(2)> params = %{hostnames: query, location: "Barcelona", region: "Spain"}
iex(3)> Server.get_avg_ram(params, run?: true)
{:ok, %Postgrex.Result{...}}
```

## Installation

`AyeSQL` is available as a Hex package. To install, add it to your
dependencies in your `mix.exs` file:

```elixir
def deps do
  [{:ayesql, "~> 0.2"}]
end
```

## Author

Alexander de Sousa.

## License

`AyeSQL` is released under the MIT License. See the LICENSE file for further
details.
