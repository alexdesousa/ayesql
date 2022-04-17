# Debugging Queries

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
iex> Queries.get_avg_clicks(params, run: false)
{:ok, %AyeSQL.Query{statement: ..., arguments: ...}}
```
