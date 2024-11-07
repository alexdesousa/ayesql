defmodule AyeSQL.CompilerTest do
  use ExUnit.Case, async: true

  alias AyeSQL.Compiler

  describe "compile_queries/2" do
    test "should raise when there's an unamed query" do
      assert_raise AyeSQL.CompileError, fn ->
        Compiler.compile_queries("SELECT * FROM table")
      end
    end

    test "should succeed when docs are provided after name" do
      contents = """
      -- name: function_name
      -- docs: Documentation
      Query
      """

      [tuple | _rest] = Compiler.compile_queries(contents)
      assert is_tuple(tuple)
      assert elem(tuple, 0) == :def
    end

    test "should succeed when fragment: true is specified" do
      contents = """
      -- name: function_name
      -- docs: Documentation
      -- fragment: true
      Query
      """

      [tuple | _rest] = Compiler.compile_queries(contents)
      assert is_tuple(tuple)
      assert elem(tuple, 0) == :def
    end
  end

  describe "eval_query/2" do
    test "should eval a single query" do
      contents = "SELECT * FROM table WHERE value = :value"

      function = Compiler.eval_query(contents)

      assert {:ok, %AyeSQL.Query{} = query} = function.([value: 42], run: false)
      assert query.arguments == [42]
      assert query.statement == "SELECT * FROM table WHERE value = $1"
    end

    test "should raise when there's a lexer error" do
      assert_raise AyeSQL.CompileError, fn ->
        Compiler.eval_query("'''")
      end
    end

    test "should raise when there's a parser error" do
      assert_raise AyeSQL.CompileError, fn ->
        Compiler.eval_query("""
        -- docs: Documentation
        -- name: function_name
        Query
        """)
      end
    end

    test "should raise when query is named" do
      assert_raise AyeSQL.CompileError, fn ->
        Compiler.eval_query("""
        -- name: function_name
        -- docs: Documentation
        Query
        """)
      end
    end
  end
end
