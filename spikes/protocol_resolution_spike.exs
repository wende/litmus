#!/usr/bin/env elixir

defmodule ProtocolResolutionSpike do
  @moduledoc """
  Spike 3: Protocol Dispatch Resolution

  Purpose: Determine if we can statically resolve protocol implementations
  at compile-time with sufficient accuracy to support Task 9.

  Research questions:
  1. How are protocols compiled in Elixir?
  2. Where do protocol implementations live?
  3. Can we detect protocol calls in AST?
  4. Can we resolve implementations at compile-time?

  Success Criteria:
  - Resolve built-in types (List, Map, Range) → 100% accuracy
  - Resolve user structs in same project → 80% accuracy
  - Gracefully fall back to :unknown for unresolvable cases
  - Demonstrate effect tracing through Enum.map
  """

  # ============================================================================
  # EXPERIMENT 1: Protocol Compilation Investigation
  # ============================================================================

  def examine_protocol_compilation do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("EXPERIMENT 1: Protocol Compilation Structure")
    IO.puts(String.duplicate("=", 70))

    # Question: What happens when we compile a protocol?
    # - Does Enumerable.beam exist?
    # - Does Enumerable.List.beam exist?
    # - How is __impl__/1 used?

    IO.puts("\n1. Checking Enumerable protocol module:")
    case :code.which(Enumerable) do
      path when is_list(path) ->
        IO.puts("   ✓ Enumerable found at: #{path}")
      :non_existing ->
        IO.puts("   ✗ Enumerable not found")
    end

    # Check for implementations
    IO.puts("\n2. Checking built-in implementations:")
    impls = [
      Enumerable.List,
      Enumerable.Map,
      Enumerable.Range,
      Enumerable.MapSet,
      Enumerable.Function,
      Enumerable.HashDict,
      Enumerable.Stream
    ]

    existing_impls = for impl <- impls do
      case :code.which(impl) do
        path when is_list(path) ->
          IO.puts("   ✓ #{inspect(impl)}")
          impl
        :non_existing ->
          IO.puts("   ✗ #{inspect(impl)} (not found)")
          nil
      end
    end |> Enum.reject(&is_nil/1)

    # Check for impl_for/1 function (protocol consolidation)
    IO.puts("\n3. Checking protocol consolidation:")
    if function_exported?(Enumerable, :impl_for, 1) do
      IO.puts("   ✓ Enumerable.impl_for/1 exists (protocol is consolidated)")
      IO.puts("   This means we can use impl_for/1 for runtime resolution")
    else
      IO.puts("   ✗ Enumerable.impl_for/1 not found (protocol not consolidated)")
    end

    # Check for __protocol__/1 function
    IO.puts("\n4. Checking protocol metadata:")
    if function_exported?(Enumerable, :__protocol__, 1) do
      IO.puts("   ✓ Enumerable.__protocol__/1 exists")
      impls_from_protocol = Enumerable.__protocol__(:impls)
      IO.puts("   Implementations according to protocol: #{inspect(impls_from_protocol)}")
    end

    existing_impls
  end

  def test_runtime_resolution do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("EXPERIMENT 2: Runtime Resolution Tests")
    IO.puts(String.duplicate("=", 70))

    test_data = [
      {[1, 2, 3], "List"},
      {%{a: 1, b: 2}, "Map"},
      {1..10, "Range"},
      {MapSet.new([1, 2]), "MapSet"},
      {Date.range(~D[2024-01-01], ~D[2024-01-10]), "Date.Range"}
    ]

    IO.puts("\nResolving protocol implementations at runtime:")
    for {data, name} <- test_data do
      impl = Enumerable.impl_for(data)
      data_type = if is_map(data) and Map.has_key?(data, :__struct__),
                    do: data.__struct__,
                    else: :builtin_type
      IO.puts("   #{String.pad_trailing(name, 15)} → #{inspect(impl)} (type: #{inspect(data_type)})")
    end
  end

  def detect_protocol_calls_in_ast do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("EXPERIMENT 3: Protocol Call Detection in AST")
    IO.puts(String.duplicate("=", 70))

    code_samples = [
      {"Enum.map([1,2,3], fn x -> x * 2 end)", "Simple Enum.map"},
      {"Enum.filter(%{a: 1}, fn {k, v} -> v > 0 end)", "Enum.filter on map"},
      {"for x <- 1..10, do: x * 2", "for comprehension"},
      {"Enum.reduce(data, 0, fn x, acc -> acc + x end)", "Enum.reduce"},
      {"to_string(123)", "String.Chars protocol"}
    ]

    IO.puts("\nDetecting protocol calls:")
    for {code, description} <- code_samples do
      {:ok, ast} = Code.string_to_quoted(code)
      IO.puts("\n   #{description}:")
      IO.puts("   Code: #{code}")

      # Can we detect that this calls a protocol?
      {protocol, certainty} = analyze_for_protocol_call(ast)
      IO.puts("   Protocol: #{inspect(protocol)} (#{certainty})")
    end
  end

  defp analyze_for_protocol_call(ast) do
    case ast do
      # Enum.* functions (Enumerable protocol)
      {{:., _, [{:__aliases__, _, [:Enum]}, func]}, _, args} ->
        {Enumerable, "high - explicit Enum.#{func}/#{length(args)} call"}

      # for comprehensions (Enumerable protocol)
      {:for, _, _} ->
        {Enumerable, "high - for comprehension uses Enumerable"}

      # to_string/1 (String.Chars protocol)
      {{:., _, [{:__aliases__, _, [:Kernel]}, :to_string]}, _, _} ->
        {String.Chars, "high - explicit to_string/1"}

      {:to_string, _, _} ->
        {String.Chars, "high - to_string/1"}

      # inspect/1,2 (Inspect protocol)
      {{:., _, [{:__aliases__, _, [:Kernel]}, :inspect]}, _, _} ->
        {Inspect, "high - explicit inspect"}

      {:inspect, _, _} ->
        {Inspect, "high - inspect"}

      _ ->
        {:unknown, "none - no protocol detected"}
    end
  end
end

# ============================================================================
# EXPERIMENT 4: Protocol Resolution Prototype
# ============================================================================

defmodule ProtocolResolutionSpike.Resolver do
  @moduledoc """
  Experimental resolver for protocol implementations.

  Tests whether we can map from data types to protocol implementations
  at compile-time.
  """

  def resolve_enumerable(data_type) do
    # Given a data type at compile time,
    # can we determine which Enumerable implementation?

    case data_type do
      # Built-in types - should be 100% accurate
      :list -> {:ok, Enumerable.List}
      {:list, _elem_type} -> {:ok, Enumerable.List}

      :map -> {:ok, Enumerable.Map}
      {:map, _key_type, _val_type} -> {:ok, Enumerable.Map}

      :range -> {:ok, Enumerable.Range}
      {:range, _from, _to} -> {:ok, Enumerable.Range}

      # MapSet is a struct but common enough to special-case
      MapSet -> {:ok, Enumerable.MapSet}
      {:struct, MapSet} -> {:ok, Enumerable.MapSet}

      # Structs - more challenging
      {:struct, module} when is_atom(module) ->
        resolve_struct_impl(module)

      # Atom indicating a module (struct)
      module when is_atom(module) and module not in [:list, :map, :range] ->
        resolve_struct_impl(module)

      # Unknown
      _ -> {:unknown, :cannot_resolve_type}
    end
  end

  defp resolve_struct_impl(module) do
    # Key challenge: Struct defined in another module
    # Can we check if an implementation exists?

    impl_module = Module.concat(Enumerable, module)

    # Try to load the implementation module
    case Code.ensure_compiled(impl_module) do
      {:module, ^impl_module} ->
        {:ok, impl_module}

      {:error, _reason} ->
        # Implementation doesn't exist
        {:unknown, :no_implementation}
    end
  end

  def trace_effects_through_protocol(enumerable_type, mapper_effect) do
    # Can we trace: Enum.map(list, fn x -> IO.puts(x) end)
    # to detect the IO.puts effect?

    # Resolution strategy:
    # 1. Resolve protocol implementation
    case resolve_enumerable(enumerable_type) do
      {:ok, impl_module} ->
        # 2. Check if implementation is pure
        impl_effect = check_impl_purity(impl_module)

        # 3. Combine with mapper effect
        combined = combine_effects(impl_effect, mapper_effect)

        {:ok, impl_module, impl_effect, combined}

      {:unknown, reason} ->
        {:unknown, reason}
    end
  end

  defp check_impl_purity(impl_module) do
    # Most Enumerable implementations are pure and lambda-dependent
    # (they depend on the function passed to reduce/3)

    case impl_module do
      Enumerable.List -> :lambda    # Pure but depends on reducer
      Enumerable.Map -> :lambda     # Pure but depends on reducer
      Enumerable.Range -> :lambda   # Pure but depends on reducer
      Enumerable.MapSet -> :lambda  # Pure but depends on reducer
      Enumerable.Stream -> :lambda  # Lazy, depends on underlying enumerable
      _ -> :lambda                  # Conservative: assume lambda-dependent
    end
  end

  defp combine_effects(:lambda, mapper_effect) do
    # If implementation is lambda-dependent,
    # result depends on mapper effect
    mapper_effect
  end

  defp combine_effects(impl_effect, mapper_effect) do
    # Otherwise, union of effects
    merge_effects(impl_effect, mapper_effect)
  end

  defp merge_effects(:p, :p), do: :p
  defp merge_effects(:p, other), do: other
  defp merge_effects(other, :p), do: other
  defp merge_effects(:lambda, other), do: other
  defp merge_effects(other, :lambda), do: other
  defp merge_effects(_, _), do: :s  # Conservative: side effects
end

# ============================================================================
# EXPERIMENT 5: Built-in Type Resolution Tests
# ============================================================================

defmodule ProtocolResolutionSpike.BuiltinTests do
  alias ProtocolResolutionSpike.Resolver

  def run_builtin_tests do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("EXPERIMENT 4: Built-in Type Resolution Tests")
    IO.puts(String.duplicate("=", 70))
    IO.puts("Target: 100% accuracy\n")

    test_cases = [
      {:list, Enumerable.List, "List type"},
      {{:list, :integer}, Enumerable.List, "List with element type"},
      {:map, Enumerable.Map, "Map type"},
      {{:map, :atom, :any}, Enumerable.Map, "Map with key/value types"},
      {:range, Enumerable.Range, "Range type"},
      {{:range, 1, 10}, Enumerable.Range, "Range with bounds"},
      {MapSet, Enumerable.MapSet, "MapSet module"},
      {{:struct, MapSet}, Enumerable.MapSet, "MapSet struct type"}
    ]

    results = for {type, expected, description} <- test_cases do
      case Resolver.resolve_enumerable(type) do
        {:ok, ^expected} ->
          IO.puts("   ✓ #{String.pad_trailing(description, 30)} → #{inspect(expected)}")
          :pass
        {:ok, actual} ->
          IO.puts("   ✗ #{String.pad_trailing(description, 30)} → #{inspect(actual)} (expected #{inspect(expected)})")
          :fail
        {:unknown, reason} ->
          IO.puts("   ✗ #{String.pad_trailing(description, 30)} → unknown (#{reason})")
          :fail
      end
    end

    passed = Enum.count(results, &(&1 == :pass))
    total = length(results)
    accuracy = if total > 0, do: passed / total * 100, else: 0

    IO.puts("\n   Result: #{passed}/#{total} tests passed")
    IO.puts("   Accuracy: #{Float.round(accuracy, 1)}%")
    IO.puts("   Target: 100%")
    IO.puts("   Status: #{if accuracy >= 100, do: "✓ PASS", else: "✗ FAIL"}")

    accuracy
  end
end

# ============================================================================
# EXPERIMENT 6: User Struct Resolution Tests
# ============================================================================

defmodule ProtocolResolutionSpike.UserStructTests do
  alias ProtocolResolutionSpike.Resolver

  # Test struct 1: Custom list implementation
  defmodule CustomList do
    defstruct [:items]

    def new(items \\ []), do: %__MODULE__{items: items}
  end

  defimpl Enumerable, for: ProtocolResolutionSpike.UserStructTests.CustomList do
    def count(%{items: items}), do: {:ok, length(items)}
    def member?(%{items: items}, val), do: {:ok, val in items}
    def slice(_), do: {:error, __MODULE__}
    def reduce(%{items: items}, acc, fun), do: Enumerable.List.reduce(items, acc, fun)
  end

  # Test struct 2: No Enumerable implementation
  defmodule NonEnumerable do
    defstruct [:data]
  end

  # Test struct 3: Another custom implementation
  defmodule CustomRange do
    defstruct [:from, :to]
  end

  defimpl Enumerable, for: ProtocolResolutionSpike.UserStructTests.CustomRange do
    def count(%{from: from, to: to}), do: {:ok, to - from + 1}
    def member?(%{from: from, to: to}, val), do: {:ok, val >= from and val <= to}
    def slice(_), do: {:error, __MODULE__}
    def reduce(%{from: from, to: to}, acc, fun) do
      Enumerable.Range.reduce(from..to, acc, fun)
    end
  end

  def run_user_struct_tests do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("EXPERIMENT 5: User Struct Resolution Tests")
    IO.puts(String.duplicate("=", 70))
    IO.puts("Target: 80% accuracy\n")

    test_cases = [
      {{:struct, CustomList},
       {:ok, Enumerable.ProtocolResolutionSpike.UserStructTests.CustomList},
       "Custom list with Enumerable impl"},

      {CustomList,
       {:ok, Enumerable.ProtocolResolutionSpike.UserStructTests.CustomList},
       "Custom list module"},

      {{:struct, CustomRange},
       {:ok, Enumerable.ProtocolResolutionSpike.UserStructTests.CustomRange},
       "Custom range with Enumerable impl"},

      {{:struct, NonEnumerable},
       {:unknown, :no_implementation},
       "Struct without Enumerable impl"},

      {NonEnumerable,
       {:unknown, :no_implementation},
       "Module without Enumerable impl"},

      {{:struct, MapSet},
       {:ok, Enumerable.MapSet},
       "Standard library struct (MapSet)"},

      {{:struct, Date.Range},
       {:ok, Enumerable.Date.Range},
       "Standard library struct (Date.Range)"},

      {{:struct, :"Elixir.NonExistent"},
       {:unknown, :no_implementation},
       "Non-existent module"}
    ]

    results = for {type, expected, description} <- test_cases do
      actual = Resolver.resolve_enumerable(type)

      match = case {actual, expected} do
        {{:ok, impl}, {:ok, impl}} -> true
        {{:unknown, _}, {:unknown, _}} -> true
        _ -> false
      end

      if match do
        case actual do
          {:ok, impl} ->
            IO.puts("   ✓ #{String.pad_trailing(description, 45)} → #{inspect(impl)}")
          {:unknown, reason} ->
            IO.puts("   ✓ #{String.pad_trailing(description, 45)} → unknown (#{reason})")
        end
        :pass
      else
        IO.puts("   ✗ #{String.pad_trailing(description, 45)} → #{inspect(actual)} (expected #{inspect(expected)})")
        :fail
      end
    end

    passed = Enum.count(results, &(&1 == :pass))
    total = length(results)
    accuracy = if total > 0, do: passed / total * 100, else: 0

    IO.puts("\n   Result: #{passed}/#{total} tests passed")
    IO.puts("   Accuracy: #{Float.round(accuracy, 1)}%")
    IO.puts("   Target: 80%")
    IO.puts("   Status: #{if accuracy >= 80, do: "✓ PASS", else: "✗ FAIL"}")

    accuracy
  end
end

# ============================================================================
# EXPERIMENT 7: Effect Tracing Test
# ============================================================================

defmodule ProtocolResolutionSpike.EffectTracingTest do
  alias ProtocolResolutionSpike.Resolver

  def run_effect_tracing_test do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("EXPERIMENT 6: Effect Tracing Through Protocols")
    IO.puts(String.duplicate("=", 70))

    test_cases = [
      {:list, :p, :p, "Enum.map([1,2,3], fn x -> x * 2 end) - pure mapper"},
      {:list, :s, :s, "Enum.map([1,2,3], &IO.puts/1) - side-effectful mapper"},
      {:map, :p, :p, "Enum.map(%{a: 1}, fn {k,v} -> {k, v*2} end) - pure mapper"},
      {:range, :s, :s, "Enum.map(1..10, &File.write!/2) - effectful mapper"}
    ]

    IO.puts("\nTracing effects through protocol calls:")
    results = for {enum_type, mapper_effect, expected_effect, description} <- test_cases do
      case Resolver.trace_effects_through_protocol(enum_type, mapper_effect) do
        {:ok, impl, impl_effect, combined} ->
          match = combined == expected_effect
          status = if match, do: "✓", else: "✗"
          IO.puts("\n   #{status} #{description}")
          IO.puts("      Resolved to: #{inspect(impl)}")
          IO.puts("      Implementation effect: #{inspect(impl_effect)}")
          IO.puts("      Mapper effect: #{inspect(mapper_effect)}")
          IO.puts("      Combined effect: #{inspect(combined)}")
          if not match do
            IO.puts("      Expected: #{inspect(expected_effect)}")
          end
          if match, do: :pass, else: :fail

        {:unknown, reason} ->
          IO.puts("\n   ✗ #{description}")
          IO.puts("      Failed to resolve: #{reason}")
          :fail
      end
    end

    passed = Enum.count(results, &(&1 == :pass))
    total = length(results)

    IO.puts("\n   Result: #{passed}/#{total} tests passed")
    IO.puts("   Status: #{if passed == total, do: "✓ PASS", else: "✗ FAIL"}")

    if passed == total, do: :pass, else: :fail
  end
end

# ============================================================================
# EXPERIMENT 8: Comprehensive Report
# ============================================================================

defmodule ProtocolResolutionSpike.Report do
  def run_full_spike do
    IO.puts("\n\n")
    IO.puts(String.duplicate("=", 70))
    IO.puts("  SPIKE 3: PROTOCOL DISPATCH RESOLUTION")
    IO.puts(String.duplicate("=", 70))
    IO.puts("\nGoal: Determine if we can statically resolve protocol implementations")
    IO.puts("      with sufficient accuracy to support Task 9.\n")

    # Phase 1: Understanding
    _existing_impls = ProtocolResolutionSpike.examine_protocol_compilation()
    ProtocolResolutionSpike.test_runtime_resolution()
    ProtocolResolutionSpike.detect_protocol_calls_in_ast()

    # Phase 2: Testing
    builtin_accuracy = ProtocolResolutionSpike.BuiltinTests.run_builtin_tests()
    struct_accuracy = ProtocolResolutionSpike.UserStructTests.run_user_struct_tests()
    effect_tracing = ProtocolResolutionSpike.EffectTracingTest.run_effect_tracing_test()

    # Phase 3: Decision
    IO.puts("\n\n")
    IO.puts(String.duplicate("=", 70))
    IO.puts("  SPIKE RESULTS")
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n✓ Built-in Type Resolution: #{Float.round(builtin_accuracy, 1)}% (target: 100%)")
    IO.puts("#{if builtin_accuracy >= 100, do: "  ", else: "✗ "}User Struct Resolution: #{Float.round(struct_accuracy, 1)}% (target: 80%)")
    IO.puts("#{if effect_tracing == :pass, do: "✓", else: "✗"} Effect Tracing: #{if effect_tracing == :pass, do: "PASS", else: "FAIL"}")

    # Decision logic
    success = builtin_accuracy >= 100 and struct_accuracy >= 80 and effect_tracing == :pass

    IO.puts("\n" <> String.duplicate("=", 70))
    if success do
      IO.puts("✓✓✓ SPIKE SUCCESS ✓✓✓")
      IO.puts(String.duplicate("=", 70))
      IO.puts("\nRECOMMENDATION: Proceed with Task 9 (Dynamic Dispatch Analysis)")
      IO.puts("\nImplementation Plan:")
      IO.puts("  1. Create lib/litmus/analyzer/protocol_detector.ex")
      IO.puts("     - Detect protocol calls in AST (Enum.*, for, to_string, etc.)")
      IO.puts("     - Extract data type from first argument")
      IO.puts("")
      IO.puts("  2. Create lib/litmus/analyzer/protocol_resolver.ex")
      IO.puts("     - Map data types to protocol implementations")
      IO.puts("     - Handle built-in types with 100% accuracy")
      IO.puts("     - Handle user structs with 80%+ accuracy")
      IO.puts("     - Graceful fallback to :unknown")
      IO.puts("")
      IO.puts("  3. Extend lib/litmus/analyzer/ast_walker.ex")
      IO.puts("     - Integrate protocol detection")
      IO.puts("     - Resolve protocol implementations during analysis")
      IO.puts("     - Track effects through protocol layers")
      IO.puts("")
      IO.puts("  4. Add protocol registry to lib/litmus/effects/registry.ex")
      IO.puts("     - Cache protocol implementation effects")
      IO.puts("     - Track lambda-dependent protocol functions")
      IO.puts("")
      IO.puts("Key Insights:")
      IO.puts("  • Protocol consolidation makes impl_for/1 available")
      IO.puts("  • Most Enumerable impls are lambda-dependent (:lambda)")
      IO.puts("  • Effect = union(implementation_effect, mapper_effect)")
      IO.puts("  • Code.ensure_compiled/1 works for checking implementations")
    else
      IO.puts("✗✗✗ SPIKE FAILED ✗✗✗")
      IO.puts(String.duplicate("=", 70))
      IO.puts("\nRECOMMENDATION: Use conservative fallback for Task 9")
      IO.puts("\nFallback Strategy:")
      IO.puts("  1. Mark all protocol calls as :unknown or new :protocol_dispatch effect")
      IO.puts("  2. Allow developers to annotate protocol implementations explicitly")
      IO.puts("  3. Document common protocol patterns in .effects.explicit.json")
      IO.puts("  4. Consider runtime effect checking for protocol dispatch")
      IO.puts("  5. Focus Task 9 on apply/3 dynamic dispatch instead")
      IO.puts("")
      IO.puts("Reasons for failure:")
      if builtin_accuracy < 100 do
        IO.puts("  • Built-in type resolution below 100%")
      end
      if struct_accuracy < 80 do
        IO.puts("  • User struct resolution below 80%")
      end
      if effect_tracing != :pass do
        IO.puts("  • Effect tracing through protocols failed")
      end
    end
    IO.puts(String.duplicate("=", 70))
    IO.puts("\n")

    success
  end
end

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Run the full spike when executed as a script
ProtocolResolutionSpike.Report.run_full_spike()
