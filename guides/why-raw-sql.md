# Why Raw SQL

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
maintainable way to be parameterized. That's why AyeSQL exists.
