defmodule AyeSQL.Runner do
  @moduledoc """
  This module defines an `AyeSQL.Runner`.
  """
  alias AyeSQL.Query

  @doc """
  Callback to initialize the runner.
  """
  @callback run(query :: Query.t(), options :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Uses the `AyeSQL.Runner` behaviour.
  """
  defmacro __using__(_options) do
    quote do
      @behaviour AyeSQL.Runner
    end
  end

  # Handles the result.
  @doc false
  @spec handle_result(map()) :: [map() | struct()]
  @spec handle_result(map(), keyword()) :: [map() | struct()]
  def handle_result(result, options \\ [])

  def handle_result(%{columns: nil}, _options) do
    []
  end

  def handle_result(%{columns: columns, rows: rows}, options) do
    struct = options[:into]
    columns = Enum.map(columns, &String.to_atom/1)

    rows
    |> Stream.map(&Stream.zip(columns, &1))
    |> Enum.map(fn row ->
      if struct, do: struct(struct, row), else: Map.new(row)
    end)
  end
end
