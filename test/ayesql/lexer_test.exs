defmodule AyeSQL.LexerTest do
  use ExUnit.Case, async: true

  alias AyeSQL.Lexer

  describe "function name" do
    test "gets function name" do
      target = "-- name: function_name"

      assert [
               {:"$name", 1, {"function_name", ^target, {1, 1}}}
             ] = Lexer.tokenize(target)
    end
  end

  describe "function docs" do
    test "gets function docs" do
      target = "-- docs: Function documentation"

      assert [
               {:"$docs", 1, {"Function documentation", ^target, {1, 1}}}
             ] = Lexer.tokenize(target)
    end
  end

  describe "fragment boolean" do
    test "gets fragment metadata" do
      target = "-- fragment: true"

      assert [
               {:"$query_fragment_metadata", 1, {"true", ^target, {1, 1}}}
             ] = Lexer.tokenize(target)
    end
  end

  describe "comments" do
    test "ignores comments" do
      target = """
      ----------------------------
      -- This is a comment      -- sss
         -- This is also a comment
      ----------------------------
      """

      assert [
               {:"$fragment", 1, {" ", " ", {1, 1}}},
               {:"$fragment", 2, {" ", " ", {2, 1}}},
               {:"$fragment", 3, {" ", " ", {3, 1}}},
               {:"$fragment", 3, {" ", " ", {3, 4}}},
               {:"$fragment", 4, {" ", " ", {4, 1}}}
             ] = Lexer.tokenize(target)
    end
  end

  describe "query fragment" do
    test "gets query fragment" do
      target = "SELECT * FROM table"

      assert [
               {:"$fragment", 1, {"SELECT", "SELECT", {1, 1}}},
               {:"$fragment", 1, {" ", " ", {1, 7}}},
               {:"$fragment", 1, {"*", "*", {1, 8}}},
               {:"$fragment", 1, {" ", " ", {1, 9}}},
               {:"$fragment", 1, {"FROM", "FROM", {1, 10}}},
               {:"$fragment", 1, {" ", " ", {1, 14}}},
               {:"$fragment", 1, {"table", "table", {1, 15}}}
             ] = Lexer.tokenize(target)
    end

    test "accepts any fragment that starts with colon and it's not a named params" do
      assert [{:"$fragment", 1, {"::INT", "::INT", {1, 1}}}] =
               Lexer.tokenize("::INT")

      assert [{:"$fragment", 1, {":=", ":=", {1, 1}}}] = Lexer.tokenize(":=")
    end

    test "ignores named params inside strings" do
      target = "':named_param'"

      assert [
               {:"$fragment", 1, {"':named_param'", "':named_param'", {1, 1}}}
             ] = Lexer.tokenize(target)
    end

    test "preserve spaces inside strings" do
      target = "'Spaces preserved'"

      assert [
               {:"$fragment", 1,
                {"'Spaces preserved'", "'Spaces preserved'", {1, 1}}}
             ] = Lexer.tokenize(target)
    end
  end

  describe "named parameters" do
    test "gets named parameter" do
      target = """
      SELECT *
        FROM table
       WHERE value = :named_param
      ORDER BY value :_order_by
      """

      assert [
               {:"$fragment", 1, {"SELECT", "SELECT", {1, 1}}},
               {:"$fragment", 1, {" ", " ", {1, 7}}},
               {:"$fragment", 1, {"*", "*", {1, 8}}},
               {:"$fragment", 1, {" ", " ", {1, 9}}},
               {:"$fragment", 2, {" ", " ", {2, 1}}},
               {:"$fragment", 2, {"FROM", "FROM", {2, 3}}},
               {:"$fragment", 2, {" ", " ", {2, 7}}},
               {:"$fragment", 2, {"table", "table", {2, 8}}},
               {:"$fragment", 2, {" ", " ", {2, 13}}},
               {:"$fragment", 3, {" ", " ", {3, 1}}},
               {:"$fragment", 3, {"WHERE", "WHERE", {3, 2}}},
               {:"$fragment", 3, {" ", " ", {3, 7}}},
               {:"$fragment", 3, {"value", "value", {3, 8}}},
               {:"$fragment", 3, {" ", " ", {3, 13}}},
               {:"$fragment", 3, {"=", "=", {3, 14}}},
               {:"$fragment", 3, {" ", " ", {3, 15}}},
               {:"$named_param", 3, {"named_param", ":named_param", {3, 16}}},
               {:"$fragment", 3, {" ", " ", {3, 28}}},
               {:"$fragment", 4, {"ORDER", "ORDER", {4, 1}}},
               {:"$fragment", 4, {" ", " ", {4, 6}}},
               {:"$fragment", 4, {"BY", "BY", {4, 7}}},
               {:"$fragment", 4, {" ", " ", {4, 9}}},
               {:"$fragment", 4, {"value", "value", {4, 10}}},
               {:"$fragment", 4, {" ", " ", {4, 15}}},
               {:"$named_param", 4, {"_order_by", ":_order_by", {4, 16}}},
               {:"$fragment", 4, {" ", " ", {4, 26}}}
             ] = Lexer.tokenize(target)
    end
  end

  describe "lexer errors" do
    test "when there's an unexpected error, raises" do
      assert_raise AyeSQL.CompileError, fn ->
        Lexer.tokenize("'''")
      end
    end
  end
end
