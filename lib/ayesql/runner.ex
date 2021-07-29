defmodule AyeSQL.Runner do
  @moduledoc """
  This module defines an `AyeSQL.Runner`.
  """
  alias AyeSQL.Query

  @doc """
  Callback to initialize the runner.
  """
  @callback run(query :: Query.t(), options :: keyword()) ::
              :ok | {:ok, term()} | {:error, term()}

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
  @spec handle_result(map()) :: {:ok, [map()]}
  def handle_result(result)

  def handle_result(%{columns: nil}) do
    {:ok, []}
  end

  def handle_result(%{columns: columns, rows: rows}) do
    columns = Enum.map(columns, &String.to_atom/1)

    result =
      rows
      |> Stream.map(&Stream.zip(columns, &1))
      |> Enum.map(&Map.new/1)

    {:ok, result}
  end

  def handle_result(result) do
    {:ok, result}
  end

  @doc false
  @spec handle_result_stream(Enumerable.t()) :: Enumerable.t()
  def handle_result_stream(stream) do
    Stream.flat_map(stream, fn batch ->
      {:ok, result} = handle_result(batch)
      result
    end)
  end
end
