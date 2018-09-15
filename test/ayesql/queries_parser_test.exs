defmodule AyeSQL.QueriesParserTest do
  use ExUnit.Case

  setup do
    contents = File.read!("test/support/queries.sql")
    {:ok, tokens, _} = :queries_lexer.tokenize(contents)
    {:ok, ast} = :queries_parser.parse(tokens)
    {:ok, %{ast: ast}}
  end

  test "detects all queries", %{ast: ast} do
    assert length(ast) == 4
  end

  test "all queries have name", %{ast: ast} do
    assert [
      {:get_servers, _, _},
      {:get_server, _, _},
      {:get_interval, _, _},
      {:get_avg_ram, _, _}
    ] = ast
  end

  test "docs are optional", %{ast: ast} do
    assert [{:get_servers, "", _} | _] = ast
  end

  test "named parameters are present as atoms", %{ast: ast} do
    parameters =
      ast
      |> Stream.map(&elem(&1, 2))
      |> Enum.map(&Enum.filter(&1, fn x -> is_atom(x) end))

    assert [
      [],
      [:hostname],
      [:start, :start, :interval, :step, :step],
      [:get_interval, :servers, :location]
    ] = parameters
  end
end
