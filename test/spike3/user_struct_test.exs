defmodule Litmus.Spike3.UserStructTest do
  use ExUnit.Case, async: true
  alias Litmus.Spike3.{ProtocolResolver, StructTypes}

  @moduledoc """
  Tests for protocol resolution with user-defined structs.

  Day 2 Morning: Verify that protocol resolution works for custom structs
  beyond built-in types (List, Map, MapSet, Range).
  """

  describe "Spike3.MyList (pure implementation)" do
    test "infers struct type from MyList.new/1 call" do
      # AST: Spike3.MyList.new([1, 2, 3])
      ast = {
        {:., [], [{:__aliases__, [], [:Spike3, :MyList]}, :new]},
        [],
        [[1, 2, 3]]
      }

      type = StructTypes.infer_from_expression(ast)
      assert type == {:struct, Spike3.MyList, %{}}
    end

    test "infers struct type from pattern %Spike3.MyList{}" do
      # Pattern: %Spike3.MyList{items: items}
      pattern = {
        :%,
        [],
        [
          {:__aliases__, [], [:Spike3, :MyList]},
          {:%{}, [], [items: {:items, [], nil}]}
        ]
      }

      {:ok, type} = StructTypes.extract_from_pattern(pattern)
      assert type == {:struct, Spike3.MyList, %{}}
    end

    test "resolves Enumerable implementation for Spike3.MyList" do
      type = {:struct, Spike3.MyList, %{}}

      {:ok, impl_module} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl_module == Enumerable.Spike3.MyList
    end

    test "verifies Spike3.MyList has Enumerable implementation" do
      type = {:struct, Spike3.MyList, %{}}
      assert ProtocolResolver.has_impl?(Enumerable, type)
    end

    test "resolves Enum.map call for Spike3.MyList" do
      type = {:struct, Spike3.MyList, %{}}

      {:ok, {module, function, arity}} =
        ProtocolResolver.resolve_call(Enum, :map, [type, :any])

      assert module == Enumerable.Spike3.MyList
      assert function == :reduce
      assert arity == 3
    end

    test "resolves Enum.filter call for Spike3.MyList" do
      type = {:struct, Spike3.MyList, %{}}

      {:ok, {module, function, arity}} =
        ProtocolResolver.resolve_call(Enum, :filter, [type, :any])

      assert module == Enumerable.Spike3.MyList
      assert function == :reduce
      assert arity == 3
    end

    test "resolves Enum.count call for Spike3.MyList" do
      type = {:struct, Spike3.MyList, %{}}

      {:ok, {module, function, arity}} =
        ProtocolResolver.resolve_call(Enum, :count, [type])

      assert module == Enumerable.Spike3.MyList
      assert function == :count
      assert arity == 1
    end
  end

  describe "Spike3.EffectfulList (effectful implementation)" do
    test "infers struct type from EffectfulList.new/1 call" do
      # AST: Spike3.EffectfulList.new([1, 2, 3])
      ast = {
        {:., [], [{:__aliases__, [], [:Spike3, :EffectfulList]}, :new]},
        [],
        [[1, 2, 3]]
      }

      type = StructTypes.infer_from_expression(ast)
      assert type == {:struct, Spike3.EffectfulList, %{}}
    end

    test "infers struct type from pattern %Spike3.EffectfulList{}" do
      # Pattern: %Spike3.EffectfulList{items: items}
      pattern = {
        :%,
        [],
        [
          {:__aliases__, [], [:Spike3, :EffectfulList]},
          {:%{}, [], [items: {:items, [], nil}]}
        ]
      }

      {:ok, type} = StructTypes.extract_from_pattern(pattern)
      assert type == {:struct, Spike3.EffectfulList, %{}}
    end

    test "resolves Enumerable implementation for Spike3.EffectfulList" do
      type = {:struct, Spike3.EffectfulList, %{}}

      {:ok, impl_module} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl_module == Enumerable.Spike3.EffectfulList
    end

    test "verifies Spike3.EffectfulList has Enumerable implementation" do
      type = {:struct, Spike3.EffectfulList, %{}}
      assert ProtocolResolver.has_impl?(Enumerable, type)
    end

    test "resolves Enum.map call for Spike3.EffectfulList" do
      type = {:struct, Spike3.EffectfulList, %{}}

      {:ok, {module, function, arity}} =
        ProtocolResolver.resolve_call(Enum, :map, [type, :any])

      assert module == Enumerable.Spike3.EffectfulList
      assert function == :reduce
      assert arity == 3
    end

    test "resolves Enum.each call for Spike3.EffectfulList" do
      type = {:struct, Spike3.EffectfulList, %{}}

      {:ok, {module, function, arity}} =
        ProtocolResolver.resolve_call(Enum, :each, [type, :any])

      assert module == Enumerable.Spike3.EffectfulList
      assert function == :reduce
      assert arity == 3
    end
  end

  describe "struct implementation registry" do
    test "finds all Enumerable implementations in protocol corpus" do
      # Expected implementations from protocol_corpus.ex:
      # - Enumerable.Spike3.MyList
      # - Enumerable.Spike3.EffectfulList

      user_struct_types = [
        {:struct, Spike3.MyList, %{}},
        {:struct, Spike3.EffectfulList, %{}}
      ]

      results =
        Enum.map(user_struct_types, fn type ->
          ProtocolResolver.has_impl?(Enumerable, type)
        end)

      # All should have implementations
      assert Enum.all?(results)
    end

    test "distinguishes between structs with and without implementations" do
      # Spike3.MyList has Enumerable
      assert ProtocolResolver.has_impl?(Enumerable, {:struct, Spike3.MyList, %{}})

      # Random struct doesn't have Enumerable
      defmodule RandomStruct do
        defstruct value: 1
      end

      refute ProtocolResolver.has_impl?(Enumerable, {:struct, RandomStruct, %{}})
    end

    test "handles multiple protocols for same struct" do
      # In future, we might have structs implementing multiple protocols
      # For now, just test that we can check multiple protocols separately

      my_list_type = {:struct, Spike3.MyList, %{}}

      # Has Enumerable
      assert ProtocolResolver.has_impl?(Enumerable, my_list_type)

      # Probably doesn't have String.Chars (unless we add it)
      result = ProtocolResolver.has_impl?(String.Chars, my_list_type)
      # Don't assert - just verify it returns true/false without crashing
      assert is_boolean(result)
    end
  end

  describe "accuracy measurement for user structs" do
    test "resolves user struct types with high accuracy" do
      test_cases = [
        {{:struct, Spike3.MyList, %{}}, Enumerable, Enumerable.Spike3.MyList},
        {{:struct, Spike3.EffectfulList, %{}}, Enumerable, Enumerable.Spike3.EffectfulList}
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

      IO.puts("\nUser struct resolution accuracy: #{success_count}/#{total} (#{accuracy}%)")
      assert accuracy >= 80.0
    end
  end

  describe "end-to-end user struct examples" do
    test "example 11: Spike3.MyList with pure lambda" do
      # Spike3.MyList.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
      type = {:struct, Spike3.MyList, %{}}

      {:ok, impl} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl == Enumerable.Spike3.MyList

      {:ok, {module, function, arity}} =
        ProtocolResolver.resolve_call(Enum, :map, [type, :any])

      assert {module, function, arity} == {Enumerable.Spike3.MyList, :reduce, 3}

      # Expected effect: pure struct + pure lambda = pure
      # (Will test in effect tracer)
    end

    test "example 12: Spike3.EffectfulList with pure lambda" do
      # Spike3.EffectfulList.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
      type = {:struct, Spike3.EffectfulList, %{}}

      {:ok, impl} = ProtocolResolver.resolve_impl(Enumerable, type)
      assert impl == Enumerable.Spike3.EffectfulList

      {:ok, {module, function, arity}} =
        ProtocolResolver.resolve_call(Enum, :map, [type, :any])

      assert {module, function, arity} == {Enumerable.Spike3.EffectfulList, :reduce, 3}

      # Expected effect: effectful struct + pure lambda = effectful (from struct's reduce)
      # (Will test in effect tracer)
    end

    test "example 13: user struct pipeline" do
      # Spike3.MyList.new([1, 2, 3, 4, 5])
      # |> Enum.filter(&(&1 > 2))
      # |> Enum.map(&(&1 * 2))

      type = {:struct, Spike3.MyList, %{}}

      # First pipeline stage: Enum.filter
      {:ok, {module1, function1, arity1}} =
        ProtocolResolver.resolve_call(Enum, :filter, [type, :any])

      assert {module1, function1, arity1} == {Enumerable.Spike3.MyList, :reduce, 3}

      # Type propagation through filter (preserves struct type)
      type2 = StructTypes.propagate_through_pipeline(type, {Enum, :filter, 2})
      assert type2 == {:struct, Spike3.MyList, %{}}

      # Second pipeline stage: Enum.map (still resolves to MyList implementation)
      {:ok, {module2, function2, arity2}} =
        ProtocolResolver.resolve_call(Enum, :map, [type2, :any])

      assert {module2, function2, arity2} == {Enumerable.Spike3.MyList, :reduce, 3}
    end

    test "example 14: mixed user struct and built-in" do
      # list1 = Spike3.MyList.new([1, 2, 3])
      # list2 = [4, 5, 6]
      # Enum.map(list1, &(&1 * 2))
      # Enum.map(list2, &(&1 * 2))

      user_type = {:struct, Spike3.MyList, %{}}
      builtin_type = {:list, :integer}

      # User struct call
      {:ok, {module1, function1, arity1}} =
        ProtocolResolver.resolve_call(Enum, :map, [user_type, :any])

      assert {module1, function1, arity1} == {Enumerable.Spike3.MyList, :reduce, 3}

      # Built-in call
      {:ok, {module2, function2, arity2}} =
        ProtocolResolver.resolve_call(Enum, :map, [builtin_type, :any])

      assert {module2, function2, arity2} == {Enumerable.List, :reduce, 3}

      # Both resolve correctly but to different implementations
      refute module1 == module2
    end
  end
end
