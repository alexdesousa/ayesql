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
  @spec handle_result(map()) :: [map() | struct() | keyword()]
  @spec handle_result(map(), keyword()) :: [map() | struct() | keyword()]
  def handle_result(result, options \\ [])

  def handle_result(data, options) when is_list(options) do
    handle_result(data, Map.new(options))
  end

  def handle_result(raw_data, %{into: :raw}) do
    raw_data
  end

  def handle_result(%{columns: nil}, _options) do
    []
  end

  def handle_result(%{columns: columns, rows: rows}, options) do
    atom_columns = Stream.map(columns, &String.to_atom/1)

    rows
    |> Stream.map(&Stream.zip(atom_columns, &1))
    |> Enum.map(fn row ->
      case options[:into] do
        struct when is_struct(struct) -> struct(struct, row)
        [] -> Enum.into(row, [])
        _ -> Enum.into(row, %{})
      end
    end)
  end
end
