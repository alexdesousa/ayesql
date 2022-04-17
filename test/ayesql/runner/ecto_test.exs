defmodule AyeSQL.Runner.EctoTest do
  use ExUnit.Case, async: true
  import Mox

  alias AyeSQL.Query
  alias AyeSQL.Runner.Ecto

  describe "run/2" do
    defmodule Mock.Repo do
    end

    test "should handle result on success" do
      stub(Elixir.Mock.Ecto, :query, fn _, _, _, _ ->
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
             } = Ecto.run(query, repo: Mock.Repo)
    end

    test "should raise when repo is not loaded" do
      query = %Query{
        statement: "SELECT id, name FROM table",
        arguments: []
      }

      assert_raise ArgumentError, fn ->
        Ecto.run(query, repo: NotLoaded)
      end
    end
  end
end
