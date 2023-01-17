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

  def handle_result(%{columns: columns, rows: rows} = raw_data, options) do
    if options[:into] == :raw do
      raw_data
    else
      atom_columns = Stream.map(columns, &String.to_atom/1)

      rows
      |> Stream.map(&Stream.zip(atom_columns, &1))
      |> Enum.map(fn row ->
        case options[:into] do
          nil -> Enum.into(row, %{})
          Map -> Enum.into(row, %{})
          Keyword -> Enum.into(row, [])
          enum when enum == [] or enum == %{} -> Enum.into(row, enum)
          struct -> struct(struct, row)
        end
      end)
    end
  end
end
