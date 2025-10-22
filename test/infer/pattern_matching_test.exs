defmodule Litmus.Infer.PatternMatchingTest do
  use ExUnit.Case
  doctest Litmus.Types.Pattern

  alias Litmus.Types.Pattern

  import Test.AnalysisHelpers
  import Test.Factories

  describe "extract_variables/1" do
    test "extracts variable from simple variable pattern" do
      pattern = {:x, :_, nil}
      assert Pattern.extract_variables(pattern) == [:x]
    end

    test "extracts multiple variables from tuple pattern" do
      # {a, b}
      pattern = {:tuple, [2], [{:a, :_, nil}, {:b, :_, nil}]}
      assert Pattern.extract_variables(pattern) == [:a, :b]
    end

    test "extracts variables from nested tuple pattern" do
      # {a, {b, c}}
      inner = {:tuple, [2], [{:b, :_, nil}, {:c, :_, nil}]}
      pattern = {:tuple, [2], [{:a, :_, nil}, inner]}
      assert Enum.sort(Pattern.extract_variables(pattern)) == [:a, :b, :c]
    end

    test "extracts variables from list pattern" do
      # [h|t]
      pattern = [{:h, :_, nil}, {:t, :_, nil}]
      assert Enum.sort(Pattern.extract_variables(pattern)) == [:h, :t]
    end

    test "returns empty list for underscore" do
      assert Pattern.extract_variables(:_) == []
    end

    test "returns empty list for underscore with context" do
      assert Pattern.extract_variables({:_, :_, nil}) == []
    end

    test "returns empty list for atom literals" do
      assert Pattern.extract_variables(:ok) == []
      assert Pattern.extract_variables(:error) == []
    end

    test "returns empty list for number literals" do
      assert Pattern.extract_variables(42) == []
      assert Pattern.extract_variables(3.14) == []
    end

    test "returns empty list for string literals" do
      assert Pattern.extract_variables("hello") == []
    end

    test "extracts variables from map pattern" do
      # %{key: value}
      pattern = {:%, :_, [Map, [{:key, {:value, :_, nil}}]]}
      assert Pattern.extract_variables(pattern) == [:value]
    end

    test "extracts variables from struct pattern" do
      # %User{name: n, age: a}
      pattern =
        {:%, :_, [{:__aliases__, :_, [:User]}, [{:name, {:n, :_, nil}}, {:age, {:a, :_, nil}}]]}

      assert Enum.sort(Pattern.extract_variables(pattern)) == [:a, :n]
    end

    test "deduplicates repeated variables" do
      # {a, a} - variable appears twice
      pattern = {:tuple, [2], [{:a, :_, nil}, {:a, :_, nil}]}
      assert Pattern.extract_variables(pattern) == [:a]
    end

    test "extracts variables from cons pattern" do
      # {:cons, _, [head, tail]}
      pattern = {:cons, :_, [{:head, :_, nil}, {:tail, :_, nil}]}
      assert Enum.sort(Pattern.extract_variables(pattern)) == [:head, :tail]
    end

    test "extracts variables from guard pattern" do
      # x when x > 0
      pattern = {:when, :_, [{:x, :_, nil}, {:>, :_, [{:x, :_, nil}, 0]}]}
      assert Pattern.extract_variables(pattern) == [:x]
    end
  end

  describe "extract_variables_from_list/1" do
    test "extracts variables from multiple patterns" do
      patterns = [{:x, :_, nil}, {:y, :_, nil}]
      assert Pattern.extract_variables_from_list(patterns) == [:x, :y]
    end

    test "extracts from mix of simple and complex patterns" do
      patterns = [
        {:x, :_, nil},
        {:tuple, [2], [{:a, :_, nil}, {:b, :_, nil}]}
      ]

      assert Enum.sort(Pattern.extract_variables_from_list(patterns)) == [:a, :b, :x]
    end

    test "deduplicates across patterns" do
      patterns = [
        {:x, :_, nil},
        {:tuple, [2], [{:x, :_, nil}, {:y, :_, nil}]}
      ]

      assert Enum.sort(Pattern.extract_variables_from_list(patterns)) == [:x, :y]
    end
  end

  describe "simple_pattern?/1" do
    test "returns true for simple variable" do
      assert Pattern.simple_pattern?({:x, :_, nil})
    end

    test "returns true for underscore" do
      assert Pattern.simple_pattern?({:_, :_, nil})
    end

    test "returns true for atom" do
      assert Pattern.simple_pattern?(:ok)
    end

    test "returns true for number" do
      assert Pattern.simple_pattern?(42)
    end

    test "returns true for string" do
      assert Pattern.simple_pattern?("hello")
    end

    test "returns false for tuple pattern" do
      refute Pattern.simple_pattern?({:tuple, :_, [{:a, :_, nil}]})
    end

    test "returns false for list pattern" do
      refute Pattern.simple_pattern?([{:x, :_, nil}])
    end

    test "returns false for map pattern" do
      refute Pattern.simple_pattern?({:%, :_, [Map, []]})
    end

    test "returns false for cons pattern" do
      refute Pattern.simple_pattern?({:cons, :_, [{:a, :_, nil}]})
    end
  end

  describe "complex_pattern?/1" do
    test "returns true for tuple pattern" do
      assert Pattern.complex_pattern?({:tuple, :_, [{:a, :_, nil}, {:b, :_, nil}]})
    end

    test "returns true for list pattern" do
      assert Pattern.complex_pattern?([{:h, :_, nil}])
    end

    test "returns true for map pattern" do
      assert Pattern.complex_pattern?({:%, :_, [Map, []]})
    end

    test "returns false for simple variable" do
      refute Pattern.complex_pattern?({:x, :_, nil})
    end

    test "returns false for atom" do
      refute Pattern.complex_pattern?(:ok)
    end
  end

  describe "pattern_name/1" do
    test "returns variable name" do
      assert Pattern.pattern_name({:x, :_, nil}) == "x"
    end

    test "returns 'tuple' for tuple pattern" do
      assert Pattern.pattern_name({:tuple, :_, [{:a, :_, nil}]}) == "tuple"
    end

    test "returns 'list' for list pattern" do
      assert Pattern.pattern_name({:cons, :_, [{:a, :_, nil}]}) == "list"
    end

    test "returns 'map' for map pattern" do
      assert Pattern.pattern_name({:%, :_, [Map, []]}) == "map"
    end

    test "returns struct name for struct pattern" do
      pattern = {:%, :_, [{:__aliases__, :_, [:User]}, []]}
      assert Pattern.pattern_name(pattern) == "User"
    end

    test "returns atom name" do
      assert Pattern.pattern_name(:ok) == "ok"
    end

    test "returns number as string" do
      assert Pattern.pattern_name(42) == "42"
    end

    test "returns string with quotes" do
      assert Pattern.pattern_name("hello") == "\"hello\""
    end
  end

  # Integration tests with actual lambda analysis
  describe "lambda pattern matching integration" do
    test "simple lambda works (baseline)" do
      source =
        create_module_source(
          Test,
          "def map_simple(items), do: Enum.map(items, fn x -> x * 2 end)"
        )

      result = assert_analysis_completes(source)
      assert get_function_analysis(result, {Test, :map_simple, 1})
    end

    test "lambda with tuple destructuring should work after enhancement" do
      source =
        create_module_source(
          Test,
          "def map_tuple(items), do: Enum.map(items, fn {a, b} -> a + b end)"
        )

      assert_analysis_completes(source)
    end

    test "lambda with list destructuring should work after enhancement" do
      source =
        create_module_source(Test, "def map_list(items), do: Enum.map(items, fn [h|t] -> h end)")

      assert_analysis_completes(source)
    end

    test "lambda with map destructuring should work after enhancement" do
      source =
        create_module_source(
          Test,
          "def map_map(items), do: Enum.map(items, fn %{key: val} -> val end)"
        )

      assert_analysis_completes(source)
    end

    test "multi-clause lambda should work after enhancement" do
      source =
        create_module_source(Test, """
        def factorial(n) do
          f = fn
            0 -> 1
            n -> n * factorial(n - 1)
          end
          f.(n)
        end
        """)

      assert_analysis_completes(source)
    end
  end

  # Edge cases
  describe "edge cases" do
    test "empty tuple pattern" do
      pattern = {:tuple, [0], []}
      assert Pattern.extract_variables(pattern) == []
    end

    test "empty list pattern" do
      pattern = []
      assert Pattern.extract_variables(pattern) == []
    end

    test "pattern with multiple underscores" do
      pattern = {:tuple, [3], [{:_, :_, nil}, {:_, :_, nil}, {:x, :_, nil}]}
      assert Pattern.extract_variables(pattern) == [:x]
    end

    test "deeply nested pattern" do
      # {a, {b, {c, d}}}
      inner_inner = {:tuple, [2], [{:c, :_, nil}, {:d, :_, nil}]}
      inner = {:tuple, [2], [{:b, :_, nil}, inner_inner]}
      pattern = {:tuple, [2], [{:a, :_, nil}, inner]}

      variables = Pattern.extract_variables(pattern)
      assert Enum.sort(variables) == [:a, :b, :c, :d]
    end
  end
end
