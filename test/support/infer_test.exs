defmodule Support.InferTest do
  @moduledoc """
  Test cases for effect inference, including lambda effect propagation
  and function capture.
  """

  # ============================================================================
  # Basic Pure Functions
  # ============================================================================

  def pure_arithmetic(x, y) do
    x + y * 2
  end

  def pure_string_ops(str) do
    str
    |> String.upcase()
    |> String.trim()
  end

  def pure_list_ops(list) do
    list
    |> Enum.reverse()
    |> Enum.take(5)
  end

  # ============================================================================
  # Lambda Effect Propagation - Pure Lambdas
  # ============================================================================

  def map_with_pure_lambda(list) do
    Enum.map(list, fn x -> x * 2 end)
  end

  def filter_with_pure_lambda(list) do
    Enum.filter(list, fn x -> x > 10 end)
  end

  def reduce_with_pure_lambda(list) do
    Enum.reduce(list, 0, fn x, acc -> x + acc end)
  end

  def nested_pure_lambdas(list) do
    list
    |> Enum.map(fn x -> x * 2 end)
    |> Enum.filter(fn x -> x > 5 end)
    |> Enum.reduce(0, fn x, acc -> x + acc end)
  end

  # ============================================================================
  # Lambda Effect Propagation - Effectful Lambdas
  # ============================================================================

  def map_with_io_lambda(list) do
    Enum.map(list, fn x ->
      IO.puts("Processing: #{x}")
      x * 2
    end)
  end

  def filter_with_io_lambda(list) do
    Enum.filter(list, fn x ->
      IO.inspect(x, label: "Checking")
      x > 10
    end)
  end

  def each_always_effectful(list) do
    Enum.each(list, fn x ->
      IO.puts("Item: #{x}")
    end)
  end

  def mixed_pure_and_effectful(list) do
    # First map is pure
    list
    |> Enum.map(fn x -> x * 2 end)
    # Filter has IO, making the whole pipeline effectful
    |> Enum.filter(fn x ->
      IO.puts("Checking: #{x}")
      x > 10
    end)
  end

  # ============================================================================
  # Function Capture - Pure Functions
  # ============================================================================

  def map_with_pure_capture(list) do
    Enum.map(list, &String.upcase/1)
  end

  def filter_with_capture_operator(list) do
    Enum.filter(list, &(&1 > 10))
  end

  def reduce_with_operator_capture(list) do
    Enum.reduce(list, 0, &+/2)
  end

  def pipe_with_captures(list) do
    list
    |> Enum.map(&String.upcase/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.reduce("", &<>/2)
  end

  # ============================================================================
  # Function Capture - Effectful Functions
  # ============================================================================

  def map_with_io_capture(list) do
    Enum.map(list, &IO.inspect/1)
  end

  def each_with_io_capture(list) do
    Enum.each(list, &IO.puts/1)
  end

  # ============================================================================
  # Mixed: Lambdas and Captures
  # ============================================================================

  def mixed_lambda_and_capture(list) do
    list
    # Pure lambda
    |> Enum.map(fn x -> x * 2 end)
    # Pure capture
    |> Enum.filter(&(&1 > 10))
    # Pure capture
    |> Enum.map(&Integer.to_string/1)
  end

  def mixed_with_effectful_lambda(list) do
    list
    # Pure capture
    |> Enum.map(&String.upcase/1)
    # Effectful lambda
    |> Enum.each(fn x ->
      IO.puts("Result: #{x}")
    end)
  end

  # ============================================================================
  # Higher-Order Functions with Side Effects Always
  # ============================================================================

  def spawn_with_pure_lambda(value) do
    spawn(fn -> value * 2 end)
  end

  def spawn_with_io_lambda(value) do
    spawn(fn -> IO.puts("Spawned: #{value}") end)
  end

  def task_async_pure(list) do
    Task.async(fn -> Enum.sum(list) end)
  end

  def task_async_effectful(list) do
    Task.async(fn ->
      IO.puts("Processing list")
      Enum.sum(list)
    end)
  end

  # ============================================================================
  # Side Effects
  # ============================================================================

  def write_to_file(path, content) do
    File.write!(path, content)
  end

  def read_from_file(path) do
    File.read!(path)
  end

  def log_message(msg) do
    IO.puts(msg)
  end

  def modify_ets(table, key, value) do
    :ets.insert(table, {key, value})
  end

  # ============================================================================
  # Exceptions
  # ============================================================================

  def may_raise_list_error(list) do
    hd(list)
  end

  def may_raise_division(x, y) do
    div(x, y)
  end

  def explicit_raise(msg) do
    raise msg
  end

  # ============================================================================
  # Complex Nested Cases
  # ============================================================================

  def complex_pipeline(list) do
    list
    |> Enum.map(fn x -> x * 2 end)
    |> Enum.filter(&(&1 > 5))
    |> Enum.group_by(&rem(&1, 2))
    |> Enum.map(fn {k, v} -> {k, Enum.sum(v)} end)
    |> Enum.sort_by(&elem(&1, 1))
  end

  def complex_pipeline_pure(list) do
    list
    |> Enum.map(fn x -> x * 2 end)
    |> Enum.filter(&(&1 > 5))
    |> Enum.map(fn {k, v} -> {k, Enum.sum(v)} end)
  end

  def complex_with_io(list) do
    list
    |> Enum.map(fn x ->
      result = x * 2
      IO.inspect(result, label: "Doubled")
      result
    end)
    |> Enum.filter(&(&1 > 10))
  end

  def nested_higher_order(data) do
    Enum.map(data, fn item ->
      Enum.filter(item, fn x -> x > 0 end)
    end)
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  def empty_lambda_body do
    Enum.map([1, 2, 3], fn _x -> nil end)
  end

  def capture_with_multiple_clauses(list) do
    # This might fail if multi-arity captures aren't supported
    Enum.reduce(list, %{}, &Map.put(&2, &1, true))
  end

  def lambda_with_pattern_match(list) do
    Enum.map(list, fn {k, v} -> {k, v * 2} end)
  end
end
