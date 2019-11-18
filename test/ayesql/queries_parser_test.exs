defmodule AyeSQL.QueriesParserTest do
  use ExUnit.Case, async: true

  setup do
    contents = File.read!("test/support/complex.sql")
    {:ok, tokens, _} = :queries_lexer.tokenize(contents)
    {:ok, ast} = :queries_parser.parse(tokens)
    {:ok, %{ast: ast}}
  end

  test "detects all queries", %{ast: ast} do
    assert length(ast) == 8
  end

  test "all queries have name", %{ast: ast} do
    assert [
             {:get_hostnames, _, _},
             {:get_server_by_hostname, _, _},
             {:get_servers_by_hostnames, _, _},
             {:get_ram_by_hostnames, _, _},
             {:get_interval, _, _},
             {:get_avg_ram, _, _},
             {:by_location, _, _},
             {:get_servers, _, _}
           ] = ast
  end

  test "docs are optional", %{ast: ast} do
    assert [{:get_hostnames, "", _} | _] = ast
  end

  test "named parameters are present as atoms", %{ast: ast} do
    parameters =
      ast
      |> Stream.map(&elem(&1, 2))
      |> Enum.map(&Enum.filter(&1, fn x -> is_atom(x) end))

    assert [
             [],
             [:hostname],
             [:hostnames],
             [:get_servers_by_hostnames],
             [:start, :start, :interval, :step, :step],
             [:get_interval, :servers, :location],
             [:location],
             [:hostname, :_by_location]
           ] = parameters
  end
end
