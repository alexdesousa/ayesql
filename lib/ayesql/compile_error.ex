defmodule AyeSQL.CompileError do
  @moduledoc """
  This module defines an AyeSQL compile error exception.
  """
  alias __MODULE__, as: Error
  alias AyeSQL.Lexer

  @doc """
  A compiler error.
  """
  defexception __metadata__: %{},
               contents: nil,
               filename: "nofile",
               line: 1,
               column: 1,
               header: "Unexpected error",
               context: 2

  @typedoc """
  A compile error.
  """
  @type t :: %Error{
          filename: filename :: binary(),
          line: line_number :: Lexer.line(),
          column: column_number :: Lexer.column(),
          header: header :: binary(),
          context: context :: non_neg_integer()
        }

  @os_type elem(:os.type(), 0)
  @newline if @os_type == :win32, do: "\r\n", else: "\n"

  ###########
  # Callbacks

  @impl true
  def exception(options) do
    {contents, options} = Keyword.pop(options, :contents, "")
    lines = get_lines(contents)

    metadata = %{
      contents: lines,
      length: length(lines)
    }

    options =
      options
      |> Enum.reject(fn {_, value} -> is_nil(value) end)
      |> Keyword.put(:__metadata__, metadata)

    struct(Error, options)
  end

  @impl true
  def message(%Error{filename: filename, header: header, line: line} = error) do
    """
    (#{filename}) #{header} on line #{line}:

    #{get_context(error)}
    """
  end

  #########
  # Helpers

  @spec get_lines(binary()) :: [binary()]
  defp get_lines(contents) do
    String.split(contents, ~r{(\r\n|\r|\n)})
  end

  @spec get_context(t()) :: binary()
  defp get_context(%Error{__metadata__: meta} = error) do
    range = get_range(error)

    1..meta.length
    |> Enum.zip(meta.contents)
    |> Map.new()
    |> Map.take(range)
    |> Stream.map(&highlight_column(error, &1))
    |> Stream.map(&add_line_numbers(error, &1))
    |> Stream.map(&highlight_line(error, &1))
    |> Stream.map(&elem(&1, 1))
    |> Stream.map(&String.trim_trailing/1)
    |> Enum.join(@newline)
  end

  @spec get_range(t()) :: [pos_integer()]
  defp get_range(%Error{} = error) do
    lower = lower_bound(error)
    upper = upper_bound(error)

    Enum.to_list(lower..upper)
  end

  @spec lower_bound(t()) :: pos_integer()
  defp lower_bound(%Error{context: context, line: line}) do
    lower = line - context

    if lower < 1, do: 1, else: lower
  end

  @spec upper_bound(t()) :: pos_integer()
  defp upper_bound(%Error{__metadata__: meta, context: context, line: line}) do
    upper = line + context

    if upper > meta.length, do: meta.length, else: upper
  end

  @spec add_line_numbers(t(), {pos_integer(), binary()}) ::
          {pos_integer(), binary()}
  defp add_line_numbers(%Error{__metadata__: metadata}, {line, contents}) do
    number = String.pad_leading("#{line}", String.length("#{metadata.length}"))

    {line, prefix(contents, "#{number} | ")}
  end

  @spec highlight_line(t(), {pos_integer(), binary()}) ::
          {pos_integer(), binary()}
  defp highlight_line(%Error{line: line}, {line, contents}) do
    {line, prefix(contents, "⮩ ")}
  end

  defp highlight_line(%Error{} = _, {line, contents}) do
    {line, prefix(contents, "  ")}
  end

  @spec highlight_column(t(), {pos_integer(), binary()}) ::
          {pos_integer(), binary()}
  defp highlight_column(%Error{line: line, column: column}, {line, contents}) do
    indicator = String.pad_leading("⮭", column)

    {line, "#{contents}#{@newline}#{indicator}"}
  end

  defp highlight_column(%Error{} = _, {_, _} = line) do
    line
  end

  @spec prefix(binary(), binary()) :: binary()
  defp prefix(contents, prefix) do
    len = String.length("#{prefix}")

    case get_lines(contents) do
      [content, indicator] ->
        "#{prefix}#{content}#{@newline}#{String.pad_leading("", len)}#{indicator}"

      [content | _] ->
        "#{prefix}#{content}"
    end
  end
end
