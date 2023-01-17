defmodule AyeSQL.RunnerTest do
  use ExUnit.Case, async: true

  alias AyeSQL.Runner

  defmodule User do
    defstruct [:username, :email]
  end

  describe "handle_result/1" do
    test "when columns are nil, returns empty list" do
      data = %{columns: nil}

      assert [] = Runner.handle_result(data)
    end

    test "when rows are not empty, returns a list of map rows by default" do
      data = %{
        columns: ["username", "email"],
        rows: [
          ["bob", "bob@example.com"],
          ["alice", "alice@example.com"]
        ]
      }

      expected = [
        %{username: "bob", email: "bob@example.com"},
        %{username: "alice", email: "alice@example.com"}
      ]

      assert ^expected = Runner.handle_result(data)
    end

    test "when rows are not empty, returns a list of map rows" do
      data = %{
        columns: ["username", "email"],
        rows: [
          ["bob", "bob@example.com"],
          ["alice", "alice@example.com"]
        ]
      }

      expected = [
        %{username: "bob", email: "bob@example.com"},
        %{username: "alice", email: "alice@example.com"}
      ]

      assert ^expected = Runner.handle_result(data, into: Map)
    end

    test "when rows are not empty, returns a list of keyword rows" do
      data = %{
        columns: ["username", "email"],
        rows: [
          ["bob", "bob@example.com"],
          ["alice", "alice@example.com"]
        ]
      }

      expected = [
        [username: "bob", email: "bob@example.com"],
        [username: "alice", email: "alice@example.com"]
      ]

      assert expected == Runner.handle_result(data, into: Keyword)
    end

    test "when rows are not empty, returns a list of structs rows" do
      data = %{
        columns: ["username", "email"],
        rows: [
          ["bob", "bob@example.com"],
          ["alice", "alice@example.com"]
        ]
      }

      expected = [
        %User{username: "bob", email: "bob@example.com"},
        %User{username: "alice", email: "alice@example.com"}
      ]

      assert expected == Runner.handle_result(data, into: User)
    end

    test "when rows are not empty, returns a raw result with columns and rows" do
      data = %{
        columns: ["username", "email"],
        rows: [
          ["bob", "bob@example.com"],
          ["alice", "alice@example.com"]
        ]
      }

      assert data == Runner.handle_result(data, into: :raw)
    end
  end
end
