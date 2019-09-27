defmodule AyeSQLTest do
  use ExUnit.Case, async: true
  use AyeSQL, repo: MyRepo

  defmodule TestRunner do
    use AyeSQL.Runner

    @impl true
    def run(stmt, args, options) do
      {:ok, {stmt, args, options}}
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
      assert_raise CompileError, fn ->
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

  describe "when functions are generated" do
    import AyeSQL, only: [defqueries: 3]
    defqueries(Complex, "support/complex.sql", runner: TestRunner)

    test "can expand query without params" do
      expected = "SELECT hostname FROM server"

      assert {:ok, {^expected, []}} = Complex.get_hostnames([], run?: false)
    end

    test "can expand a regular param" do
      params = [hostname: "localhost"]

      expected = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^expected, ["localhost"]}} =
               Complex.get_server_by_hostname(params, run?: false)
    end

    test "errors on missing parameters" do
      assert {:error, "Cannot find hostname in parameters"} =
               Complex.get_server_by_hostname([], run?: false)
    end

    test "ignores undefined params" do
      params = [hostname: "localhost", foo: 42]

      expected = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^expected, ["localhost"]}} =
               Complex.get_server_by_hostname(params, run?: false)
    end

    test "accepts keyword list as parameters" do
      params = [hostname: "localhost"]

      expected = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^expected, ["localhost"]}} =
               Complex.get_server_by_hostname(params, run?: false)
    end

    test "accepts map as parameters" do
      params = %{hostname: "localhost"}

      expected = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^expected, ["localhost"]}} =
               Complex.get_server_by_hostname(params, run?: false)
    end

    test "can expand an IN query" do
      params = [hostnames: {:in, ["server0", "server1"]}]

      expected = "SELECT * FROM server WHERE hostname IN ( $1,$2 )"

      assert {:ok, {^expected, ["server0", "server1"]}} =
               Complex.get_servers_by_hostnames(params, run?: false)
    end

    test "can expand with a function" do
      params = [hostnames: &Complex.get_hostnames/2]

      expected =
        "SELECT * FROM server WHERE hostname IN " <>
          "( SELECT hostname FROM server )"

      assert {:ok, {^expected, []}} =
               Complex.get_servers_by_hostnames(params, run?: false)
    end

    test "can expand with a function key" do
      params = [hostnames: {:in, ["server0", "server1"]}]

      expected =
        "SELECT s.hostname, m.ram FROM metrics AS m JOIN server AS s " <>
          "ON s.id = m.server_id WHERE s.hostname IN " <>
          "( SELECT * FROM server WHERE hostname IN ( $1,$2 ) )"

      assert {:ok, {^expected, ["server0", "server1"]}} =
               Complex.get_ram_by_hostnames(params, run?: false)
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
      assert {:ok, {_, [], [repo: MyRepo]}} =
               WithRunner.get_hostnames([], run?: true)
    end
  end
end
