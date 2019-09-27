defmodule AyeSQL.QueriesLexerTest do
  use ExUnit.Case, async: true

  test "ignores comment" do
    comment = "-- Some comment"
    assert {:ok, [], _} = :queries_lexer.tokenize(comment)
  end

  test "detects name at the beginning of the file" do
    name = "-- name: some_name"
    assert {:ok, [{:name, _, :some_name}], _} = :queries_lexer.tokenize(name)
  end

  test "detects name" do
    name = "\n-- name: some_name"
    assert {:ok, [{:name, _, :some_name}], _} = :queries_lexer.tokenize(name)
  end

  test "detects docs" do
    docs = "\n-- docs: Some docs"
    assert {:ok, [{:docs, _, "Some docs"}], _} = :queries_lexer.tokenize(docs)
  end

  test "detects named param" do
    query = "SELECT * FROM user WHERE username = :username;"

    assert {:ok, tokens, _} = :queries_lexer.tokenize(query)

    assert [
             {:fragment, _, "SELECT"},
             {:fragment, _, " "},
             {:fragment, _, "*"},
             {:fragment, _, " "},
             {:fragment, _, "FROM"},
             {:fragment, _, " "},
             {:fragment, _, "user"},
             {:fragment, _, " "},
             {:fragment, _, "WHERE"},
             {:fragment, _, " "},
             {:fragment, _, "username"},
             {:fragment, _, " "},
             {:fragment, _, "="},
             {:fragment, _, " "},
             {:named_param, _, :username},
             {:fragment, _, ";"}
           ] = tokens
  end

  test "string is part of a fragment" do
    query = "SELECT * FROM user WHERE username = 'user';"

    assert {:ok, tokens, _} = :queries_lexer.tokenize(query)

    assert [
             {:fragment, _, "SELECT"},
             {:fragment, _, " "},
             {:fragment, _, "*"},
             {:fragment, _, " "},
             {:fragment, _, "FROM"},
             {:fragment, _, " "},
             {:fragment, _, "user"},
             {:fragment, _, " "},
             {:fragment, _, "WHERE"},
             {:fragment, _, " "},
             {:fragment, _, "username"},
             {:fragment, _, " "},
             {:fragment, _, "="},
             {:fragment, _, " "},
             {:fragment, _, "'user';"}
           ] = tokens
  end

  test "cast is part of a fragment" do
    query = "SELECT * FROM user WHERE username = :username::text;"

    assert {:ok, tokens, _} = :queries_lexer.tokenize(query)

    assert [
             {:fragment, _, "SELECT"},
             {:fragment, _, " "},
             {:fragment, _, "*"},
             {:fragment, _, " "},
             {:fragment, _, "FROM"},
             {:fragment, _, " "},
             {:fragment, _, "user"},
             {:fragment, _, " "},
             {:fragment, _, "WHERE"},
             {:fragment, _, " "},
             {:fragment, _, "username"},
             {:fragment, _, " "},
             {:fragment, _, "="},
             {:fragment, _, " "},
             {:named_param, _, :username},
             {:fragment, _, "::text;"}
           ] = tokens
  end
end
