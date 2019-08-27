defmodule AyeSQLTest do
  use ExUnit.Case, async: true

  describe "when file does not exist" do
    test "throws exception" do
      assert_raise File.Error, fn ->
        defmodule Unexistent do
          use AyeSQL, repo: MyRepo

          defqueries("unexistent-file.sql")
        end
      end
    end
  end

  describe "when the parser errors" do
    test "throws exception" do
      assert_raise CompileError, fn ->
        defmodule Wrong do
          use AyeSQL, repo: MyRepo

          defqueries("support/wrong.sql")
        end
      end
    end
  end

  describe "when file is parseable" do
    defmodule Basic do
      use AyeSQL, repo: MyRepo

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
    defmodule Complex do
      use AyeSQL, repo: MyRepo

      defqueries("support/complex.sql")
    end

    test "can expand query without params" do
      expected = "SELECT hostname FROM server"

      assert {:ok, {^expected , []}} = Complex.get_hostnames([])
    end

    test "can expand a regular param" do
      params = [hostname: "localhost"]

      expected = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^expected, ["localhost"]}} =
               Complex.get_server_by_hostname(params)
    end

    test "errors on missing parameters" do
      assert {:error, "Cannot find hostname in parameters"} =
                Complex.get_server_by_hostname([])
    end

    test "ignores undefined params" do
      params = [hostname: "localhost", foo: 42]

      expected = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^expected, ["localhost"]}} =
                Complex.get_server_by_hostname(params)
    end

    test "accepts keyword list as parameters" do
      params = [hostname: "localhost"]

      expected = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^expected, ["localhost"]}} =
               Complex.get_server_by_hostname(params)
    end

    test "accepts map as parameters" do
      params = %{hostname: "localhost"}

      expected = "SELECT * FROM server WHERE hostname = $1"

      assert {:ok, {^expected, ["localhost"]}} =
               Complex.get_server_by_hostname(params)
    end

    test "can expand an IN query" do
      params = [hostnames: {:in, ["server0", "server1"]}]

      expected = "SELECT * FROM server WHERE hostname IN ( $1,$2 )"

      assert {:ok, {^expected, ["server0", "server1"]}} =
               Complex.get_servers_by_hostnames(params)
    end

    test "can expand with a function" do
      params = [hostnames: &Complex.get_hostnames/2]

      expected =
        "SELECT * FROM server WHERE hostname IN " <>
        "( SELECT hostname FROM server )"

      assert {:ok, {^expected, []}} =
               Complex.get_servers_by_hostnames(params)
    end

    test "can expand with a function key" do
      params = [hostnames: {:in, ["server0", "server1"]}]

      expected =
        "SELECT s.hostname, m.ram FROM metrics AS m JOIN server AS s " <>
        "ON s.id = m.server_id WHERE s.hostname IN " <>
        "( SELECT * FROM server WHERE hostname IN ( $1,$2 ) )"

      assert {:ok, {^expected, ["server0", "server1"]}} =
               Complex.get_ram_by_hostnames(params)
    end
  end

  describe "when app is ecto" do
    defmodule Elixir.Ecto.Adapters.SQL do
      def query(MyRepo, _, _) do
        {:ok, :ecto}
      end
    end

    defmodule WithEcto do
      use AyeSQL, app: :ecto, repo: MyRepo

      defqueries("support/basic.sql")
    end

    test "accepts :ecto" do
      assert Ecto.Adapters.SQL = WithEcto.__db_module__()
    end

    test "sets repo" do
      assert MyRepo = WithEcto.__db_conn_name__()
    end

    test "fails when there is no repo" do
      assert_raise ArgumentError, fn ->
        defmodule NoRepo do
          use AyeSQL, app: :ecto

          defqueries("support/basic.sql")
        end
      end
    end

    test "runs query with the correct module" do
      assert {:ok, :ecto} = WithEcto.get_hostnames([], run?: true)
    end
  end

  describe "when app is postgrex" do
    defmodule Elixir.Postgrex do
      def query(MyConn, _, _) do
        {:ok, :postgrex}
      end
    end

    defmodule WithPostgrex do
      use AyeSQL, app: :postgrex, conn: MyConn

      defqueries("support/basic.sql")
    end

    test "accepts :postgrex" do
      assert Postgrex = WithPostgrex.__db_module__()
    end

    test "sets conn" do
      assert MyConn = WithPostgrex.__db_conn_name__()
    end

    test "fails when there is no conn" do
      assert_raise ArgumentError, fn ->
        defmodule NoConn do
          use AyeSQL, app: :postgrex

          defqueries("support/basic.sql")
        end
      end
    end

    test "runs query with the correct module" do
      assert {:ok, :postgrex} = WithPostgrex.get_hostnames([], run?: true)
    end
  end
end
