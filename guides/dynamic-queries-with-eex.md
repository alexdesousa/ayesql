# Dynamic Queries With EEx

When AyeSQL syntax for dynamic query generation falls short, we can leverage
`EEx` templates for generating them.

> Note: It's not possible to use `defqueries/1` and `defqueries/3` macros when
> using `EEx` templates. We'll need to use the function `AyeSQL.eval_query/2`
> instead. This function will generate an anonymous function with the query.

One of such cases is when the identifiers in the query are not constant (table
names, aliases, etc). The following `EEx` template has a query with dynamic
tables, aliases, fragments and even joins:

```sql
-- File: queries.sql.eex
<% [%{name: name, as: as} | rest] = @tables %>
SELECT
  <%= as %>.datetime AS datetime,
  <%= @calculation %> AS calculation
FROM
  <%= name %> AS <%= as %>
  <%= for table <- rest do %>
  INNER JOIN <%= table.name %> AS <%= table.as %>
    ON <%= table.as %>.datetime = <%= as %>.datetime
  <% end %>
WHERE
  <%= as %>.datetime BETWEEN :start_date AND :end_date
```

With the previous template, we can generate a valid AyeSQL query with the
following:

```elixir
iex> assigns = [
...>   calculation: "(a.value / b.value)",
...>   tables: [
...>     %{name: "table_a", as: "a"},
...>     %{name: "table_b", as: "b"}
...>    ]
...> ]
iex> dynamic_query =
...>   "queries.sql.eex"
...>   |> File.read!()
...>   |> EEx.eval_string(assigns: assigns)
```

so, the variable `dynamic_query` contains the following query:

```sql
SELECT
  a.datetime AS datetime,
  (a.value / b.value) AS calculation
FROM
  table_a AS a
  INNER JOIN table_b AS b
    ON b.datetime = a.datetime
WHERE
  a.datetime BETWEEN :start_date AND :end_date
```

This query is then compatible with `AyeSQL`, so we can compile it into a
function using the following:

```elixir
iex> function = AyeSQL.eval_query(dynamic_query)
```

And finally use the function as any other `AyeSQL` function:

```elixir
iex> {:ok, start_date, _} = DateTime.from_iso8601("2022-04-17T00:00:00Z")
iex> function.([start_date: start_date, end_date: DateTime.utc_now()], repo: MyApp.Repo)
{:ok, [%{datetime: ..., calculation: ...}, ...]}
```
