defmodule AyeSQLTest do
  use ExUnit.Case, async: true
  use AyeSQL, repo: MyRepo

  alias AyeSQL.Error

  defmodule TestRunner do
    use AyeSQL.Runner

    @impl true
    def run(%AyeSQL.Query{statement: stmt, arguments: args}, options) do
      {:ok, {stmt, args, options}}
    end
  end

  describe "eval_query/2" do
    test "should eval a single query" do
      contents = "SELECT * FROM table WHERE value = :value"

      function = AyeSQL.eval_query(contents)

      assert {:ok, %AyeSQL.Query{} = query} = function.([value: 42], run: false)
      assert query.arguments == [42]
      assert query.statement == "SELECT * FROM table WHERE value = $1"
    end

    test "should raise when there's a lexer error" do
      assert_raise AyeSQL.CompileError, fn ->
        AyeSQL.eval_query("'''")
      end
    end

    test "should raise when there's a parser error" do
      assert_raise AyeSQL.CompileError, fn ->
        AyeSQL.eval_query("""
        -- docs: Documentation
        -- name: function_name
        Query
        """)
      end
    end

    test "should raise when query is named" do
      assert_raise AyeSQL.CompileError, fn ->
        AyeSQL.eval_query("""
        -- name: function_name
        -- docs: Documentation
        Query
        """)
      end
    end
  end

  describe "when file does not exist" do
    test "throws exception" do
      assert_raise File.Error, fn ->
        defmodule Unexistent do
          use AyeSQL, runner: TestRunner

          defqueries("unexistent-file.sql")
        end
      end
    end
  end

  describe "when the parser errors" do
    test "throws exception" do
      assert_raise AyeSQL.CompileError, fn ->
        defmodule Wrong do
          use AyeSQL, runner: TestRunner

          defqueries("support/wrong.sql")
        end
      end
    end
  end

  describe "when file is parseable" do
    defmodule Basic do
      use AyeSQL, runner: TestRunner

      defqueries("support/basic.sql")

      def __external_resource__, do: @external_resource
    end

    test "generates normal functions" do
      functions = Basic.module_info(:functions)

      assert Enum.member?(functions, {:get_hostnames, 1})
      assert Enum.member?(functions, {:get_hostnames, 1})

      assert Enum.member?(functions, {:get_server_by_hostname, 1})
      assert Enum.member?(functions, {:get_server_by_hostname, 1})
    end

    test "generates bang functions" do
      functions = Basic.module_info(:functions)

      assert Enum.member?(functions, {:get_hostnames!, 2})
      assert Enum.member?(functions, {:get_hostnames!, 2})

      assert Enum.member?(functions, {:get_server_by_hostname!, 2})
      assert Enum.member?(functions, {:get_server_by_hostname!, 2})
    end

    test "sets external_resource attribute for recompilation on change" do
      [path] = Basic.__external_resource__()
      assert String.ends_with?(path, "/test/support/basic.sql")
    end
  end

  describe "when query does not need parameters" do
    import AyeSQL, only: [defqueries: 3]

    defqueries(NoParam, "support/no_param.sql", runner: TestRunner)

    test "can expand query with empty params list" do
      stmt = "SELECT hostname FROM server"

      assert {:ok, {^stmt, [], _}} = NoParam.get_hostnames([])
    end
  end

  describe "when query receives mandatory parameters" do
    import AyeSQL, only: [defqueries: 3]

    defqueries(Simple, "support/simple.sql", runner: TestRunner)

    test "can expand a regular param" do
      params = [hostname: "localhost"]
      args = ["localhost"]
      stmt = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^stmt, ^args, _}} = Simple.get_server_by_hostname(params)
    end

    test "can expand a regular param when is nil" do
      params = [hostname: nil]
      args = [nil]
      stmt = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^stmt, ^args, _}} = Simple.get_server_by_hostname(params)
    end

    test "errors on missing parameters" do
      assert {:error, %Error{errors: [hostname: :not_found]}} =
               Simple.get_server_by_hostname([])
    end

    test "ignores undefined params" do
      params = [hostname: "localhost", foo: 42]
      stmt = "SELECT * FROM server WHERE hostname = $1"
      args = ["localhost"]

      assert {:ok, {^stmt, ^args, _}} = Simple.get_server_by_hostname(params)
    end

    test "accepts keyword list as parameters" do
      params = [hostname: "localhost"]
      args = ["localhost"]
      stmt = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^stmt, ^args, _}} = Simple.get_server_by_hostname(params)
    end

    test "accepts map as parameters" do
      params = %{hostname: "localhost"}
      args = ["localhost"]
      stmt = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^stmt, ^args, _}} = Simple.get_server_by_hostname(params)
    end
  end

  describe "when queries receive optional parameters" do
    import AyeSQL, only: [defqueries: 3]

    defqueries(Optional, "support/optional.sql", runner: TestRunner)

    test "can expand optional parameters when not present" do
      params = [hostname: "localhost"]
      stmt = "SELECT * FROM server WHERE hostname = $1"
      args = ["localhost"]

      assert {:ok, {^stmt, ^args, _}} = Optional.get_servers(params)
    end

    test "can expand optional parameters when with function" do
      params = [
        hostname: "localhost",
        _by_location: &Optional.by_location/2,
        location: "Barcelona"
      ]

      stmt = "SELECT * FROM server WHERE hostname = $1 AND location = $2"
      args = ["localhost", "Barcelona"]

      assert {:ok, {^stmt, ^args, _}} = Optional.get_servers(params)
    end

    test "can expand optional parameters when with function name" do
      params = [
        hostname: "localhost",
        _by_location: :by_location,
        location: "Barcelona"
      ]

      stmt = "SELECT * FROM server WHERE hostname = $1 AND location = $2"
      args = ["localhost", "Barcelona"]

      assert {:ok, {^stmt, ^args, _}} = Optional.get_servers(params)
    end
  end

  describe "when in statement is used" do
    import AyeSQL, only: [defqueries: 3]

    defqueries(InStatement, "support/in_statement.sql", runner: TestRunner)

    test "can expand an IN statement" do
      params = [names: {:in, ["Alice", "Bob", "Charlie"]}]
      stmt = "SELECT * FROM people WHERE name IN ( $1,$2,$3 )"
      args = ["Alice", "Bob", "Charlie"]

      assert {:ok, {^stmt, ^args, _}} = InStatement.get_people(params)
    end

    test "can expand with a function" do
      params = [names: &InStatement.get_names/2]
      stmt = "SELECT * FROM people WHERE name IN ( SELECT name FROM people )"

      assert {:ok, {^stmt, [], _}} = InStatement.get_people(params)
    end

    test "can expand with a function name" do
      params = [names: :get_names]
      stmt = "SELECT * FROM people WHERE name IN ( SELECT name FROM people )"

      assert {:ok, {^stmt, [], _}} = InStatement.get_people(params)
    end
  end

  describe "when queries are composed in SQL" do
    import AyeSQL, only: [defqueries: 3]

    defqueries(Composable, "support/composable.sql", runner: TestRunner)

    test "can expand with a function name" do
      stmt = "SELECT * FROM ( SELECT name FROM people )"

      assert {:ok, {^stmt, [], _}} = Composable.get_people([])
    end

    test "errors when inner query errors" do
      assert {:error, %Error{errors: [age: :not_found]}} =
               Composable.get_adults([])
    end
  end

  describe "when queries are composed in elixir" do
    import AyeSQL, only: [defqueries: 3]

    defqueries(Subquery, "support/subqueries.sql", runner: TestRunner)

    test "can expand inner query with local functions" do
      where = [:legal_age, :sql_and, {:name_like, [name: "Alice%"]}]
      params = [where: {:inner, where}]

      stmt = "SELECT name, age FROM person WHERE age >= 18 AND name LIKE $1"
      args = ["Alice%"]

      assert {:ok, {^stmt, ^args, _}} = Subquery.get_adults(params)
    end

    test "can expand inner query with remote functions" do
      where = [
        &Subquery.legal_age/2,
        &Subquery.sql_and/2,
        {&Subquery.name_like/2, [name: "Alice%"]}
      ]

      params = [where: {:inner, where}]

      stmt = "SELECT name, age FROM person WHERE age >= 18 AND name LIKE $1"
      args = ["Alice%"]

      assert {:ok, {^stmt, ^args, _}} = Subquery.get_adults(params)
    end

    test "can use custom separator" do
      order_by = [
        by_age: [order_direction: :descending],
        by_name: [order_direction: :ascending]
      ]

      params = [age: 18, order_by: {:inner, order_by, ", "}]

      stmt =
        "SELECT name, age FROM person WHERE age >= $1 ORDER BY age DESC, name ASC"

      args = [18]

      assert {:ok, {^stmt, ^args, _}} = Subquery.get_people_by_age(params)
    end
  end

  describe "when uses a runner with options" do
    defmodule WithRunner do
      use AyeSQL, runner: TestRunner, repo: MyRepo

      defqueries("support/basic.sql")
    end

    test "gets runner module" do
      assert TestRunner = WithRunner.__db_runner__()
    end

    test "sets repo" do
      assert [repo: MyRepo] = WithRunner.__db_options__()
    end

    test "runs query with the correct module" do
      assert {:ok, {_, [], [repo: MyRepo]}} = WithRunner.get_hostnames([])
    end
  end
end
