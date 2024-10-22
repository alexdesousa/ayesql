defmodule AyeSQL.Runner.DuckdbexTest do
  use ExUnit.Case, async: true
  import Mox

  alias AyeSQL.Query
  alias AyeSQL.Runner.Duckdbex

  describe "run/2" do
    test "should handle result on success" do
      stub(Mock.Duckdbex, :query, fn _, _, _ ->
        result = %{
          rows: [
            [1, "foo"],
            [2, "bar"]
          ],
          columns: ["id", "name"]
        }

        {:ok, result}
      end)

      query = %Query{
        statement: "SELECT id, name FROM table",
        arguments: []
      }

      assert {
               :ok,
               [
                 %{id: 1, name: "foo"},
                 %{id: 2, name: "bar"}
               ]
             } = Duckdbex.run(query, conn: make_ref())
    end

    test "should raise when connection is nil" do
      query = %Query{
        statement: "SELECT id, name FROM table",
        arguments: []
      }

      assert_raise ArgumentError, fn ->
        Duckdbex.run(query, [])
      end
    end
  end
end
