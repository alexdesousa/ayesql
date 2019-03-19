defmodule AyeSQLTest do
  use ExUnit.Case

  describe "join_fragments/2" do
    test "joins the binaries and keeps the atoms separated" do
      values =
        [:foo, "word", "(", :bar, ")", "other_word", :baz]
        |> AyeSQL.join_fragments([])
      assert ["", :foo, "word (", :bar, ") other_word", :baz] = values
    end
  end

  describe "expand_binary_fn/1" do
    test "expands a binary" do
      function = AyeSQL.expand_binary_fn("foo")

      assert is_function(function)
      assert {:ok, {1, ["foo"], []}} = function.({1, [], []}, %{})
    end
  end

  describe "expand_function_fn/2" do
    test "expands a function" do
      stmt =
        "SELECT (datetime::date) AS date, (datetime::time) AS time " <>
        "FROM generate_series( $1::timestamp, $2::timestamp + " <>
        "$3::interval - $4::interval, $5::interval ) AS datetime"
      arguments = ["step", "step", "interval", "start", "start"]

      params = %{
        start: "start",
        step: "step",
        interval: "interval"
      }
      function = AyeSQL.expand_function_fn(Queries, :get_interval)

      assert is_function(function)
      assert {:ok, {6, [^stmt], ^arguments}} = function.({1, [], []}, params)
    end
  end

  describe "expand_params_fn/1" do
    test "expands a normal param" do
      params = %{server: "hostname"}
      function = AyeSQL.expand_param_fn(:server)

      assert is_function(function)
      assert {:ok, {2, ["$1"], ["hostname"]}} = function.({1, [], []}, params)
    end

    test "expands a query function closure" do
      stmt =
        "SELECT (datetime::date) AS date, (datetime::time) AS time " <>
        "FROM generate_series( $1::timestamp, $2::timestamp + " <>
        "$3::interval - $4::interval, $5::interval ) AS datetime"
      arguments = ["step", "step", "interval", "start", "start"]

      params = %{
        run_interval: &Queries.get_interval/2,
        start: "start",
        step: "step",
        interval: "interval"
      }
      function = AyeSQL.expand_param_fn(:run_interval)

      assert is_function(function)
      assert {:ok, {6, [^stmt], ^arguments}} = function.({1, [], []}, params)
    end

    test "expands an in tuple" do
      params = %{servers: {:in, [1, 2, 3]}}
      function = AyeSQL.expand_param_fn(:servers)

      assert is_function(function)
      assert {:ok, {4, ["$1,$2,$3"], [3, 2, 1]}} =
             function.({1, [], []}, params)
    end
  end

  describe "do_expand/2" do
    test "expands a binary" do
      function = AyeSQL.do_expand(Queries, "foo")

      assert is_function(function)
      assert {:ok, {1, ["foo"], []}} = function.({1, [], []}, %{})
    end

    test "expands a function" do
      stmt =
        "SELECT (datetime::date) AS date, (datetime::time) AS time " <>
        "FROM generate_series( $1::timestamp, $2::timestamp + " <>
        "$3::interval - $4::interval, $5::interval ) AS datetime"
      arguments = ["step", "step", "interval", "start", "start"]

      params = %{
        start: "start",
        step: "step",
        interval: "interval"
      }
      function = AyeSQL.do_expand(Queries, :get_interval)

      assert is_function(function)
      assert {:ok, {6, [^stmt], ^arguments}} = function.({1, [], []}, params)
    end

    test "expands a param" do
      params = %{server: "hostname"}
      function = AyeSQL.do_expand(Queries, :server)

      assert is_function(function)
      assert {:ok, {2, ["$1"], ["hostname"]}} = function.({1, [], []}, params)
    end
  end

  describe "evaluate/3" do
    test "evaluates the functions" do
      stmt =
        "WITH computed_dates AS (SELECT (datetime::date) AS date, " <>
        "(datetime::time) AS time FROM generate_series( $1::timestamp, " <>
        "$2::timestamp + $3::interval - $4::interval, $5::interval ) " <>
        "AS datetime) SELECT dates.date AS data FROM computed_dates AS dates"
      args = ["start", "start", "interval", "step", "step"]

      params = %{
        start: "start",
        step: "step",
        interval: "interval"
      }
      contents = [
        "WITH computed_dates AS (",
        :get_interval,
        ") SELECT dates.date AS data ",
        "FROM computed_dates AS dates"
      ]
      functions = AyeSQL.expand(Queries, contents)

      base = {1, [], []}

      assert {:ok, {^stmt, ^args}} = AyeSQL.evaluate(functions, base, params)
    end
  end

  describe "defqueries/1" do
    test "defines all the functions" do
      functions = Queries.module_info(:functions)

      assert Enum.member?(functions, {:get_servers, 1})
      assert Enum.member?(functions, {:get_servers!, 2})
      assert Enum.member?(functions, {:get_servers, 1})
      assert Enum.member?(functions, {:get_servers!, 2})

      assert Enum.member?(functions, {:get_server, 1})
      assert Enum.member?(functions, {:get_server!, 2})
      assert Enum.member?(functions, {:get_server, 1})
      assert Enum.member?(functions, {:get_server!, 2})

      assert Enum.member?(functions, {:get_interval, 1})
      assert Enum.member?(functions, {:get_interval!, 2})
      assert Enum.member?(functions, {:get_interval, 1})
      assert Enum.member?(functions, {:get_interval!, 2})

      assert Enum.member?(functions, {:get_avg_ram, 1})
      assert Enum.member?(functions, {:get_avg_ram!, 2})
      assert Enum.member?(functions, {:get_avg_ram, 1})
      assert Enum.member?(functions, {:get_avg_ram!, 2})
    end

    test "substitutes all params" do
      stmt =
        "WITH computed_dates AS ( SELECT (datetime::date) AS date, "
        <> "(datetime::time) AS time FROM generate_series( $1::timestamp, "
        <> "$2::timestamp + $3::interval - $4::interval, $5::interval ) AS "
        <> "datetime ) SELECT dates.date AS date, dates.time AS time, "
        <> "metrics.hostname AS hostname, AVG((metrics.metrics->>'ram')"
        <> "::numeric) AS ram FROM computed_dates AS dates LEFT JOIN "
        <> "server_metrics AS metrics USING(date, time) WHERE "
        <> "metrics.hostname IN (SELECT hostname FROM server) AND "
        <> "metrics.location = $6 GROUP BY dates.date, dates.time, "
        <> "metrics.hostname"
      args = ["start", "start", "interval", "step", "step", "location"]

      params = %{
        start: "start",
        interval: "interval",
        step: "step",
        servers: &Queries.get_servers/2,
        location: "location"
      }
      assert {:ok, {^stmt, ^args}} = Queries.get_avg_ram(params)
    end

    test "throws exception if .sql file not found" do
      assert_raise File.Error, fn ->
        defmodule Queries do
          use AyeSQL

          defqueries("no-existing-file.sql")
        end
      end
    end
  end
end
