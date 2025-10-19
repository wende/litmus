defmodule Support.HigherOrderDemo do
  @moduledoc """
  Demonstrates effect analysis for higher-order functions.
  """

  # Pure: Enum.map with a pure lambda
  def map_pure(list) do
    Enum.map(list, fn x -> x * 2 end)
  end

  # Effectful: Enum.map with an effectful lambda (IO)
  def map_with_io(list) do
    Enum.map(list, fn x ->
      IO.puts("Processing: #{x}")
      x * 2
    end)
  end

  # Effectful: Enum.each always has side effects because it's used for side effects
  def each_with_io(list) do
    Enum.each(list, fn x ->
      IO.puts("Item: #{x}")
    end)
  end

  # Pure: Enum.filter with pure predicate
  def filter_pure(list) do
    Enum.filter(list, fn x -> x > 5 end)
  end

  # Effectful: Enum.filter with effectful predicate
  def filter_with_io(list) do
    Enum.filter(list, fn x ->
      IO.puts("Checking: #{x}")
      x > 5
    end)
  end

  # Pure: Enum.reduce with pure accumulator function
  def reduce_pure(list) do
    Enum.reduce(list, 0, fn x, acc -> x + acc end)
  end

  # Effectful: Enum.reduce with effectful accumulator function
  def reduce_with_io(list) do
    Enum.reduce(list, 0, fn x, acc ->
      IO.puts("Adding #{x} to #{acc}")
      x + acc
    end)
  end

  # Effectful: Task.async with lambda (spawns process)
  def async_task(value) do
    Task.async(fn -> value * 2 end)
  end

  # Effectful: Process.spawn with lambda
  def spawn_process(value) do
    spawn(fn -> IO.puts("Spawned with: #{value}") end)
  end

  # Pure: Nested higher-order - pure lambda in pure function
  def nested_pure(list) do
    list
    |> Enum.map(fn x -> x * 2 end)
    |> Enum.filter(fn x -> x > 10 end)
    |> Enum.reduce(0, fn x, acc -> x + acc end)
  end

  # Effectful: Nested higher-order - one effectful lambda makes all effectful
  def nested_effectful(list) do
    list
    |> Enum.map(fn x ->
      IO.puts("Mapping: #{x}")
      x * 2
    end)
    |> Enum.filter(fn x -> x > 10 end)
    |> Enum.reduce(0, fn x, acc -> x + acc end)
  end

  # Pure: Higher-order returning a function (pure construction)
  def create_multiplier(factor) do
    fn x -> x * factor end
  end

  # Effectful: Using the created function doesn't make this effectful by itself,
  # but if we use it with IO...
  def use_multiplier_with_io(list, factor) do
    multiplier = create_multiplier(factor)
    Enum.map(list, fn x ->
      result = multiplier.(x)
      IO.puts("Result: #{result}")
      result
    end)
  end
end