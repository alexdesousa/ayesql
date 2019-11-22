defmodule AyeSQL.AST.ContextTest do
  use ExUnit.Case, async: true

  alias AyeSQL.AST.Context
  alias AyeSQL.Error
  alias AyeSQL.Query

  describe "new/1" do
    test "creates an empty context" do
      assert %Context{
               index: 1,
               statement: [],
               arguments: [],
               errors: []
             } = Context.new([])
    end

    test "creates a context with a valid index" do
      assert %Context{index: 42} = Context.new(index: 42)
    end

    test "creates a context with a valid statement" do
      assert %Context{statement: []} = Context.new(statement: [])
      assert %Context{statement: ["*"]} = Context.new(statement: ["*"])
    end

    test "fails when statement is invalid" do
      assert_raise ArgumentError, fn -> Context.new(statement: [42]) end
    end

    test "creates a context with a valid arguments" do
      assert %Context{arguments: []} = Context.new(arguments: [])
      assert %Context{arguments: ["*"]} = Context.new(arguments: ["*"])
    end

    test "creates a context with a valid errors" do
      assert %Context{errors: []} = Context.new(errors: [])

      assert %Context{errors: [a: :not_found]} =
               Context.new(errors: [a: :not_found])
    end

    test "fails when errors is invalid" do
      assert_raise ArgumentError, fn -> Context.new(errors: [42]) end
    end
  end

  describe "id/1" do
    test "returns the same context" do
      context = Context.new(index: 42)

      assert ^context = Context.id(context)
    end
  end

  describe "put_statement/2" do
    test "creates new var if value is empty" do
      context = Context.new([])

      assert %Context{statement: ["$1"]} = Context.put_statement(context)
    end

    test "appends at the beginning when value is empty" do
      context = Context.new(statement: ["don't panic"])

      assert %Context{
               statement: ["$1", "don't panic"]
             } = Context.put_statement(context)
    end

    test "appends at the beginning when value is not empty" do
      context = Context.new(statement: ["don't panic"])

      assert %Context{
               statement: ["!", "don't panic"]
             } = Context.put_statement(context, "!")
    end
  end

  describe "put_argument/2" do
    test "appends at the beginning when value is not empty" do
      context = Context.new(arguments: ["don't panic"])

      assert %Context{
               arguments: ["!", "don't panic"]
             } = Context.put_argument(context, "!")
    end
  end

  describe "add_index/2" do
    test "adds one by default to index" do
      context = Context.new([])

      assert %Context{index: 2} = Context.add_index(context)
    end

    test "adds a number by default to index" do
      context = Context.new([])

      assert %Context{index: 42} = Context.add_index(context, 41)
    end
  end

  describe "put_variable/2" do
    test "adds a new variable" do
      context = Context.new(index: 41, statement: ["don't panic"])

      assert %Context{
               index: 42,
               statement: ["$41", "don't panic"],
               arguments: ["!"]
             } = Context.put_variable(context, "!")
    end
  end

  describe "put_variables/2" do
    test "puts several variables in a list" do
      context = Context.new(index: 41, statement: ["don't panic"])

      assert %Context{
               index: 44,
               statement: ["$41,$42,$43", "don't panic"],
               arguments: ["!", ".", "."]
             } = Context.put_variables(context, [".", ".", "!"])
    end
  end

  describe "mege/2" do
    test "merges two contexts" do
      context0 = Context.new(index: 1, statement: ["don't"])
      context1 = Context.new(index: 2, statement: ["panic"], arguments: [42])

      assert %Context{
               index: 2,
               statement: ["panic", "don't"],
               arguments: [42]
             } = Context.merge(context0, context1)
    end
  end

  describe "merge_query/2" do
    test "merges context with a query" do
      context =
        Context.new(
          index: 1,
          statement: ["don't"],
          errors: [a: :not_found]
        )

      query = Query.new(statement: "panic $1,$2,$3", arguments: [".", ".", "!"])

      assert %Context{
               index: 4,
               statement: ["panic $1,$2,$3", "don't"],
               arguments: ["!", ".", "."],
               errors: [a: :not_found]
             } = Context.merge_query(context, query)
    end
  end

  describe "merge_error/2" do
    test "merges context with an error" do
      context =
        Context.new(
          index: 1,
          statement: ["don't"],
          errors: [a: :not_found]
        )

      error =
        Error.new(
          statement: "panic $1,$2,$3",
          arguments: [".", ".", "!"],
          errors: [b: :not_found]
        )

      assert %Context{
               index: 4,
               statement: ["panic $1,$2,$3", "don't"],
               arguments: ["!", ".", "."],
               errors: [a: :not_found, b: :not_found]
             } = Context.merge_error(context, error)
    end
  end

  describe "to_query/1" do
    test "converts to query if there are not errors" do
      context =
        Context.new(
          index: 1,
          statement: [" panic $1,$2,$3", "don't"],
          arguments: ["!", ".", "."]
        )

      assert {:ok, %Query{} = query} = Context.to_query(context)

      assert %Query{
               arguments: [".", ".", "!"],
               statement: "don't panic $1,$2,$3"
             } = query
    end

    test "converts to error if there are errors" do
      context =
        Context.new(
          index: 1,
          statement: [" panic $1,$2,$3", "don't"],
          arguments: ["!", ".", "."],
          errors: [a: :not_found]
        )

      assert {:error, %Error{} = error} = Context.to_query(context)

      assert %Error{
               arguments: [".", ".", "!"],
               statement: "don't panic $1,$2,$3",
               errors: [a: :not_found]
             } = error
    end
  end

  describe "not_found/2" do
    test "adds the error not found" do
      context = Context.new([])
      assert %Context{errors: [a: :not_found]} = Context.not_found(context, :a)
    end

    test "adds missing variable to statement" do
      context = Context.new([])

      assert %Context{
               statement: ["<missing a>"]
             } = Context.not_found(context, :a)
    end
  end
end
