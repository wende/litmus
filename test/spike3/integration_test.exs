defmodule Litmus.Spike3.IntegrationTest do
  use ExUnit.Case, async: true
  alias Litmus.Spike3.{ProtocolResolver, StructTypes}

  @moduledoc """
  Integration tests demonstrating end-to-end protocol resolution.

  These tests simulate the complete workflow:
  1. Infer type from AST expression
  2. Resolve protocol implementation
  3. Determine which function will be called
  """

  describe "end-to-end protocol resolution" do
    test "list literal through Enum.map" do
      # Step 1: Infer type from literal
      list_literal = [1, 2, 3]
      type = StructTypes.infer_from_expression(list_literal)
      assert type == {:list, :integer}

      # Step 2: Resolve protocol implementation
      {:ok, impl_module} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl_module == Enumerable.List

      # Step 3: Resolve function call
      {:ok, {module, function, arity}} = ProtocolResolver.resolve_call(Enum, :map, [type, :any])
      assert module == Enumerable.List
      assert function == :reduce
      assert arity == 3
    end

    test "map literal through Enum.filter" do
      # Step 1: Infer type from AST
      map_ast = {:%{}, [], [a: 1, b: 2]}
      type = StructTypes.infer_from_expression(map_ast)
      assert type == {:map, []}

      # Step 2: Resolve protocol implementation
      {:ok, impl_module} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl_module == Enumerable.Map

      # Step 3: Resolve function call
      {:ok, {module, function, arity}} = ProtocolResolver.resolve_call(Enum, :filter, [type, :any])
      assert module == Enumerable.Map
      assert function == :reduce
      assert arity == 3
    end

    test "MapSet through Enum.count" do
      # Step 1: Infer type from constructor
      mapset_ast = {{:., [], [{:__aliases__, [], [:MapSet]}, :new]}, [], [[1, 2, 3]]}
      type = StructTypes.infer_from_expression(mapset_ast)
      assert type == {:struct, MapSet, %{}}

      # Step 2: Resolve protocol implementation
      {:ok, impl_module} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl_module == Enumerable.MapSet

      # Step 3: Resolve function call
      {:ok, {module, function, arity}} = ProtocolResolver.resolve_call(Enum, :count, [type])
      assert module == Enumerable.MapSet
      assert function == :count
      assert arity == 1
    end

    test "Range through Enum.reduce" do
      # Step 1: Infer type from range expression
      range_ast = {:.., [], [1, 10]}
      type = StructTypes.infer_from_expression(range_ast)
      assert type == {:struct, Range, %{}}

      # Step 2: Resolve protocol implementation
      {:ok, impl_module} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl_module == Enumerable.Range

      # Step 3: Resolve function call
      {:ok, {module, function, arity}} = ProtocolResolver.resolve_call(Enum, :reduce, [type, :any, :any])
      assert module == Enumerable.Range
      assert function == :reduce
      assert arity == 3
    end

    test "struct literal through pattern matching" do
      # Step 1: Extract type from pattern
      pattern_ast = {:%, [], [{:__aliases__, [], [:MapSet]}, {:%{}, [], []}]}
      {:ok, type} = StructTypes.extract_from_pattern(pattern_ast)
      assert type == {:struct, MapSet, %{}}

      # Step 2: Resolve protocol implementation
      {:ok, impl_module} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl_module == Enumerable.MapSet

      # Step 3: Check implementation exists
      assert ProtocolResolver.has_impl?(Enumerable, type)
    end

    test "pipeline type propagation" do
      # Simulate: [1,2,3] |> Enum.map(&(&1 * 2)) |> Enum.filter(&(&1 > 5))

      # Step 1: Initial type
      type1 = {:list, :integer}

      # Step 2: After Enum.map (preserves list type)
      type2 = StructTypes.propagate_through_pipeline(type1, {Enum, :map, 2})
      assert type2 == {:list, :any}

      # Step 3: After Enum.filter (still a list)
      type3 = StructTypes.propagate_through_pipeline(type2, {Enum, :filter, 2})
      assert type3 == {:list, :any}

      # Step 4: Verify we can still resolve protocol
      {:ok, impl_module} = ProtocolResolver.resolve_impl(Enumerable, type3)
      assert impl_module == Enumerable.List
    end
  end

  describe "accuracy measurement" do
    test "resolves built-in types with high accuracy" do
      test_cases = [
        {{:list, :integer}, Enumerable, Enumerable.List},
        {{:map, []}, Enumerable, Enumerable.Map},
        {{:struct, MapSet, %{}}, Enumerable, Enumerable.MapSet},
        {{:struct, Range, %{}}, Enumerable, Enumerable.Range},
        {:integer, String.Chars, String.Chars.Integer},
        {:atom, String.Chars, String.Chars.Atom},
        {{:list, :any}, String.Chars, String.Chars.List}
      ]

      results =
        Enum.map(test_cases, fn {type, protocol, expected_impl} ->
          case ProtocolResolver.resolve_impl(protocol, type) do
            {:ok, ^expected_impl} -> :success
            _ -> :failure
          end
        end)

      success_count = Enum.count(results, &(&1 == :success))
      total = length(results)
      accuracy = success_count / total * 100

      IO.puts("\nBuilt-in type resolution accuracy: #{success_count}/#{total} (#{accuracy}%)")
      assert accuracy >= 80.0
    end

    test "handles unknown types gracefully" do
      unknown_cases = [
        :any,
        {:type_var, :t},
        {:union, [:integer, :string]},
        :some_unknown_type
      ]

      results =
        Enum.map(unknown_cases, fn type ->
          ProtocolResolver.resolve_impl(Enumerable, type)
        end)

      # All should return :unknown
      assert Enum.all?(results, &(&1 == :unknown))
    end
  end

  describe "real-world examples" do
    test "example 1: list map from protocol corpus" do
      # [1, 2, 3] |> Enum.map(&(&1 * 2))
      type = {:list, :integer}
      {:ok, impl} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl == Enumerable.List

      {:ok, {module, function, arity}} = ProtocolResolver.resolve_call(Enum, :map, [type, :any])
      assert {module, function, arity} == {Enumerable.List, :reduce, 3}
    end

    test "example 2: map enumeration" do
      # %{a: 1, b: 2} |> Enum.map(fn {k, v} -> {k, v * 2} end)
      type = {:map, []}
      {:ok, impl} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl == Enumerable.Map

      {:ok, {module, function, arity}} = ProtocolResolver.resolve_call(Enum, :map, [type, :any])
      assert {module, function, arity} == {Enumerable.Map, :reduce, 3}
    end

    test "example 3: pipeline with type preservation" do
      # [1, 2, 3, 4, 5] |> Enum.map(&(&1 * 2)) |> Enum.filter(&(&1 > 5)) |> Enum.sum()

      # Start with list
      type1 = {:list, :integer}

      # Through map
      type2 = StructTypes.propagate_through_pipeline(type1, {Enum, :map, 2})
      assert ProtocolResolver.has_impl?(Enumerable, type2)

      # Through filter
      type3 = StructTypes.propagate_through_pipeline(type2, {Enum, :filter, 2})
      assert ProtocolResolver.has_impl?(Enumerable, type3)

      # Can still resolve to Enumerable.List
      {:ok, impl} = ProtocolResolver.resolve_impl(Enumerable, type3)
      assert impl == Enumerable.List
    end
  end
end
