defmodule AyeSQL.CompileErrorTest do
  use ExUnit.Case, async: true

  alias AyeSQL.CompileError

  describe "message/1" do
    test "generates an error message with the defaults" do
      contents = """
      incorrect line
      correct line
      correct_line
      """

      """
      (nofile) Unexpected error on line 1:

      ⮩ 1 | incorrect line
            ⮭
        2 | correct line
        3 | correct_line
      """ =
        [contents: contents]
        |> CompileError.exception()
        |> CompileError.message()
    end

    test "arrow points to right line" do
      contents = """
      correct line
      incorrect line
      correct_line
      """

      """
      (nofile) Unexpected error on line 2:

        1 | correct line
      ⮩ 2 | incorrect line
            ⮭
        3 | correct_line
        4 |
      """ =
        [contents: contents, line: 2]
        |> CompileError.exception()
        |> CompileError.message()
    end

    test "arrow points to right column" do
      contents = """
      correct line
      incorrect line
      correct_line
      """

      """
      (nofile) Unexpected error on line 2:

        1 | correct line
      ⮩ 2 | incorrect line
               ⮭
        3 | correct_line
        4 |
      """ =
        [contents: contents, line: 2, column: 4]
        |> CompileError.exception()
        |> CompileError.message()
    end

    test "context is not exceeded" do
      contents = """
      correct line
      incorrect line
      correct_line
      """

      """
      (nofile) Unexpected error on line 2:

      ⮩ 2 | incorrect line
            ⮭
      """ =
        [contents: contents, line: 2, context: 0]
        |> CompileError.exception()
        |> CompileError.message()
    end
  end
end
