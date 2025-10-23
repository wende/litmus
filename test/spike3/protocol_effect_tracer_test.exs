defmodule Litmus.Spike3.ProtocolEffectTracerTest do
  use ExUnit.Case, async: true
  alias Litmus.Spike3.ProtocolEffectTracer

  @moduledoc """
  Tests for Protocol Effect Tracer - the core deliverable for Spike 3.

  Tests three main functions:
  1. trace_protocol_call/4 - End-to-end effect tracing
  2. resolve_implementation_effect/2 - Effect lookup for implementations
  3. combine_effects/2 - Effect composition logic
  """

  describe "trace_protocol_call/4 - end-to-end tracing" do
    test "pure built-in struct + pure lambda = pure" do
      # [1, 2, 3] |> Enum.map(&(&1 * 2))
      type = {:list, :integer}
      lambda_effect = :p

      assert {:ok, :p} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "pure built-in struct + effectful lambda = effectful" do
      # [1, 2, 3] |> Enum.map(&IO.puts/1)
      type = {:list, :integer}
      lambda_effect = :s

      assert {:ok, :s} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "pure user struct + pure lambda = pure" do
      # Spike3.MyList.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
      type = {:struct, Spike3.MyList, %{}}
      lambda_effect = :p

      assert {:ok, :p} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "effectful user struct + pure lambda = effectful" do
      # Spike3.EffectfulList.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
      type = {:struct, Spike3.EffectfulList, %{}}
      lambda_effect = :p

      assert {:ok, :s} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "effectful user struct + effectful lambda = effectful" do
      # Spike3.EffectfulList.new([1, 2, 3]) |> Enum.map(&IO.puts/1)
      type = {:struct, Spike3.EffectfulList, %{}}
      lambda_effect = :s

      assert {:ok, :s} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "Map enumeration with pure lambda" do
      # %{a: 1, b: 2} |> Enum.map(fn {k, v} -> {k, v * 2} end)
      type = {:map, []}
      lambda_effect = :p

      assert {:ok, :p} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "MapSet with pure lambda" do
      # MapSet.new([1, 2, 3]) |> Enum.filter(&(&1 > 1))
      type = {:struct, MapSet, %{}}
      lambda_effect = :p

      assert {:ok, :p} =
               ProtocolEffectTracer.trace_protocol_call(Enum, :filter, type, lambda_effect)
    end

    test "Range with pure lambda" do
      # 1..10 |> Enum.map(&(&1 * 2))
      type = {:struct, Range, %{}}
      lambda_effect = :p

      assert {:ok, :p} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "Enum.count (no lambda)" do
      # [1, 2, 3] |> Enum.count()
      type = {:list, :integer}
      lambda_effect = :p

      # Enum.count doesn't have a lambda, so implementation effect wins
      assert {:ok, :p} =
               ProtocolEffectTracer.trace_protocol_call(Enum, :count, type, lambda_effect)
    end

    test "unknown type returns :unknown" do
      type = :some_unknown_type
      lambda_effect = :p

      assert :unknown = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "unknown function returns :unknown" do
      type = {:list, :integer}
      lambda_effect = :p

      assert :unknown =
               ProtocolEffectTracer.trace_protocol_call(SomeModule, :unknown_func, type, lambda_effect)
    end
  end

  describe "resolve_implementation_effect/2 - effect lookup" do
    test "Enumerable.List.reduce/3 is pure" do
      assert :p = ProtocolEffectTracer.resolve_implementation_effect(Enumerable.List, :reduce, 3)
    end

    test "Enumerable.Map.reduce/3 is pure" do
      assert :p = ProtocolEffectTracer.resolve_implementation_effect(Enumerable.Map, :reduce, 3)
    end

    test "Enumerable.MapSet.count/1 is pure" do
      assert :p = ProtocolEffectTracer.resolve_implementation_effect(Enumerable.MapSet, :count, 1)
    end

    test "Enumerable.Range.reduce/3 is pure" do
      assert :p = ProtocolEffectTracer.resolve_implementation_effect(Enumerable.Range, :reduce, 3)
    end

    test "Enumerable.Spike3.MyList.reduce/3 is pure" do
      assert :p =
               ProtocolEffectTracer.resolve_implementation_effect(
                 Enumerable.Spike3.MyList,
                 :reduce,
                 3
               )
    end

    test "Enumerable.Spike3.EffectfulList.reduce/3 is effectful" do
      assert :s =
               ProtocolEffectTracer.resolve_implementation_effect(
                 Enumerable.Spike3.EffectfulList,
                 :reduce,
                 3
               )
    end

    test "Enumerable.Spike3.EffectfulList.count/1 is effectful" do
      assert :s =
               ProtocolEffectTracer.resolve_implementation_effect(
                 Enumerable.Spike3.EffectfulList,
                 :count,
                 1
               )
    end

    test "unknown implementation returns :u" do
      assert :u =
               ProtocolEffectTracer.resolve_implementation_effect(
                 UnknownModule,
                 :unknown_func,
                 1
               )
    end
  end

  describe "combine_effects/2 - effect composition" do
    test "pure + pure = pure" do
      assert :p = ProtocolEffectTracer.combine_effects(:p, :p)
    end

    test "pure + side effects = side effects" do
      assert :s = ProtocolEffectTracer.combine_effects(:p, :s)
      assert :s = ProtocolEffectTracer.combine_effects(:s, :p)
    end

    test "side effects + side effects = side effects" do
      assert :s = ProtocolEffectTracer.combine_effects(:s, :s)
    end

    test "pure + dependent = dependent" do
      assert :d = ProtocolEffectTracer.combine_effects(:p, :d)
      assert :d = ProtocolEffectTracer.combine_effects(:d, :p)
    end

    test "dependent + side effects = side effects (more severe)" do
      assert :s = ProtocolEffectTracer.combine_effects(:d, :s)
      assert :s = ProtocolEffectTracer.combine_effects(:s, :d)
    end

    test "pure + unknown = unknown" do
      assert :u = ProtocolEffectTracer.combine_effects(:p, :u)
      assert :u = ProtocolEffectTracer.combine_effects(:u, :p)
    end

    test "side effects + unknown = unknown (most conservative)" do
      assert :u = ProtocolEffectTracer.combine_effects(:s, :u)
      assert :u = ProtocolEffectTracer.combine_effects(:u, :s)
    end

    test "pure + NIF = NIF" do
      assert :n = ProtocolEffectTracer.combine_effects(:p, :n)
      assert :n = ProtocolEffectTracer.combine_effects(:n, :p)
    end

    test "NIF + side effects = NIF (more conservative)" do
      assert :n = ProtocolEffectTracer.combine_effects(:n, :s)
      assert :n = ProtocolEffectTracer.combine_effects(:s, :n)
    end

    test "lambda + pure = pure (lambda inherits)" do
      assert :p = ProtocolEffectTracer.combine_effects(:l, :p)
      assert :p = ProtocolEffectTracer.combine_effects(:p, :l)
    end

    test "lambda + side effects = side effects (lambda inherits)" do
      assert :s = ProtocolEffectTracer.combine_effects(:l, :s)
      assert :s = ProtocolEffectTracer.combine_effects(:s, :l)
    end

    test "pure + exception = exception" do
      assert {:e, ["Elixir.ArgumentError"]} =
               ProtocolEffectTracer.combine_effects(:p, {:e, ["Elixir.ArgumentError"]})

      assert {:e, ["Elixir.ArgumentError"]} =
               ProtocolEffectTracer.combine_effects({:e, ["Elixir.ArgumentError"]}, :p)
    end

    test "exception + exception = merged exceptions" do
      result =
        ProtocolEffectTracer.combine_effects(
          {:e, ["Elixir.ArgumentError"]},
          {:e, ["Elixir.KeyError"]}
        )

      assert {:e, exceptions} = result
      assert "Elixir.ArgumentError" in exceptions
      assert "Elixir.KeyError" in exceptions
    end

    test "exception + side effects = side effects (more severe)" do
      assert :s =
               ProtocolEffectTracer.combine_effects({:e, ["Elixir.ArgumentError"]}, :s)

      assert :s =
               ProtocolEffectTracer.combine_effects(:s, {:e, ["Elixir.ArgumentError"]})
    end

    test "duplicate exceptions are merged uniquely" do
      result =
        ProtocolEffectTracer.combine_effects(
          {:e, ["Elixir.ArgumentError"]},
          {:e, ["Elixir.ArgumentError"]}
        )

      assert {:e, ["Elixir.ArgumentError"]} = result
    end
  end

  describe "real-world scenarios from protocol corpus" do
    test "example 1: list map with pure lambda" do
      # [1, 2, 3] |> Enum.map(&(&1 * 2))
      type = {:list, :integer}
      lambda_effect = :p

      assert {:ok, :p} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "example 6: list each with effectful lambda" do
      # [1, 2, 3] |> Enum.each(&IO.puts/1)
      type = {:list, :integer}
      lambda_effect = :s

      assert {:ok, :s} = ProtocolEffectTracer.trace_protocol_call(Enum, :each, type, lambda_effect)
    end

    test "example 10: pure pipeline" do
      # [1, 2, 3] |> Enum.map(&(&1 * 2)) |> Enum.reduce(0, &+/2)
      type = {:list, :integer}
      lambda_effect = :p

      # First: Enum.map
      assert {:ok, :p} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)

      # Second: Enum.reduce (also pure)
      assert {:ok, :p} =
               ProtocolEffectTracer.trace_protocol_call(Enum, :reduce, type, lambda_effect)
    end

    test "example 11: user struct with pure implementation" do
      # Spike3.MyList.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
      type = {:struct, Spike3.MyList, %{}}
      lambda_effect = :p

      assert {:ok, :p} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end

    test "example 12: user struct with effectful implementation" do
      # Spike3.EffectfulList.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
      type = {:struct, Spike3.EffectfulList, %{}}
      lambda_effect = :p

      assert {:ok, :s} = ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect)
    end
  end

  describe "effect composition correctness" do
    test "severity ordering: unknown > NIF > side > dependent > exception > lambda > pure" do
      effects = [:p, :l, {:e, ["Error"]}, :d, :s, :n, :u]

      # Unknown beats everything
      for effect <- effects -- [:u] do
        assert :u = ProtocolEffectTracer.combine_effects(:u, effect)
      end

      # NIF beats everything except unknown
      for effect <- effects -- [:u, :n] do
        assert :n = ProtocolEffectTracer.combine_effects(:n, effect)
      end

      # Side beats everything except unknown/NIF
      for effect <- effects -- [:u, :n, :s] do
        assert :s = ProtocolEffectTracer.combine_effects(:s, effect)
      end
    end

    test "commutative property for symmetric effects" do
      pairs = [
        {:p, :p},
        {:s, :s},
        {:d, :d},
        {:u, :u},
        {:n, :n}
      ]

      for {e1, e2} <- pairs do
        result1 = ProtocolEffectTracer.combine_effects(e1, e2)
        result2 = ProtocolEffectTracer.combine_effects(e2, e1)
        assert result1 == result2, "combine_effects(#{e1}, #{e2}) should be commutative"
      end
    end

    test "idempotence for same effects" do
      effects = [:p, :s, :d, :u, :n, :l]

      for effect <- effects do
        result = ProtocolEffectTracer.combine_effects(effect, effect)
        assert result == effect, "#{effect} + #{effect} should = #{effect}"
      end
    end
  end

  describe "accuracy metrics" do
    test "traces all built-in types correctly" do
      test_cases = [
        {{:list, :integer}, :p, :p},
        {{:map, []}, :p, :p},
        {{:struct, MapSet, %{}}, :p, :p},
        {{:struct, Range, %{}}, :p, :p},
        {{:list, :integer}, :s, :s},
        {{:map, []}, :s, :s}
      ]

      results =
        Enum.map(test_cases, fn {type, lambda_effect, expected} ->
          case ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect) do
            {:ok, ^expected} -> :success
            _ -> :failure
          end
        end)

      success_count = Enum.count(results, &(&1 == :success))
      total = length(results)
      accuracy = success_count / total * 100

      IO.puts("\nBuilt-in type effect tracing accuracy: #{success_count}/#{total} (#{accuracy}%)")
      assert accuracy >= 80.0
    end

    test "traces all user structs correctly" do
      test_cases = [
        {{:struct, Spike3.MyList, %{}}, :p, :p},
        {{:struct, Spike3.MyList, %{}}, :s, :s},
        {{:struct, Spike3.EffectfulList, %{}}, :p, :s},
        {{:struct, Spike3.EffectfulList, %{}}, :s, :s}
      ]

      results =
        Enum.map(test_cases, fn {type, lambda_effect, expected} ->
          case ProtocolEffectTracer.trace_protocol_call(Enum, :map, type, lambda_effect) do
            {:ok, ^expected} -> :success
            _ -> :failure
          end
        end)

      success_count = Enum.count(results, &(&1 == :success))
      total = length(results)
      accuracy = success_count / total * 100

      IO.puts("\nUser struct effect tracing accuracy: #{success_count}/#{total} (#{accuracy}%)")
      assert accuracy >= 80.0
    end
  end
end
