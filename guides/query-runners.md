# Query Runners

`AyeSQL` can be extended to support more databases than PostgreSQL by implementing
the behaviour `AyeSQL.Runner`. This library ships with three runners already:

- `AyeSQL.Runner.Ecto`, (it's the default and assumes PostgreSQL is the database).
- `AyeSQL.Runner.Postgrex`,
- `AyeSQL.Runner.Duckdbex`.

By default, AyeSQL uses the runner `AyeSQL.Runner.Ecto`. This runner only has
one option which is `:repo` for the repo module. Additionally, it converts the
result to a list of maps.

In order to support your database, you just need to implement the behaviour
e.g. let's say we implement a `MySQL` our queries module would be created using
something like the following:

```elixir
defmodule MyApp.Queries do
  use AyeSQL, runner: MyApp.Runner.MySQL, pool: MyApp.MySQL.Pool

  defqueries("queries.sql")
end
```

or

```elixir
import AyeSQL, only: [defqueries: 3]

defqueries(Queries, "queries.sql",
  runner: MyApp.Runner.MySQL,
  pool: MyApp.MySQL.Pool
)
```

And our runner could be implemented like this:

```elixir
defmodule MyApp.Runner.MySQL do
  use AyeSQL.Runner

  @impl AyeSQL
  def run(%AyeSQL.Query{statement: stmt, arguments: args}, options) do
    query_options = Keyword.frop(options, [:pool, :into])
    stmt = transform_stmt(stmt)

    with {:ok, result} <- MyXQL.query(pool, stmt, args, query_options) do
      result = AyeSQL.Runner.handle_result(result)
      {:ok, result}
    end
  end

  @spec transform_stmt(AyeSQL.Query.statement()) :: AyeSQL.Query.statement()
  defp transform_stmt(stmt) do
    Regex.replace(~r/\$(\d+)/, stmt, "?")
  end
end
```
