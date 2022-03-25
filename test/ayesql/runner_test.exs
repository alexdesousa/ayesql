defmodule AyeSQL.RunnerTest do
  use ExUnit.Case, async: true

  alias AyeSQL.Runner

  describe "handle_result/1" do
    test "when columns are nil, returns empty list" do
      data = %{columns: nil}

      assert [] = Runner.handle_result(data)
    end

    test "when rows are not empty, returns a list of rows with columns" do
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
  end
end
