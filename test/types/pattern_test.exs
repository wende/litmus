defmodule Litmus.Types.PatternTest do
  use ExUnit.Case
  alias Litmus.Types.Pattern

  describe "extract_variables/1" do
    test "extracts simple variable" do
      pattern = {:x, :_, nil}
      assert Pattern.extract_variables(pattern) == [:x]
    end

    test "extracts multiple variables from tuple" do
      pattern = {:tuple, :_, [{:a, :_, nil}, {:b, :_, nil}]}
      variables = Pattern.extract_variables(pattern)
      assert variables == [:a, :b]
    end

    test "ignores underscore" do
      assert Pattern.extract_variables(:_) == []
    end

    test "ignores underscore tuple" do
      pattern = {:_, :_, nil}
      assert Pattern.extract_variables(pattern) == []
    end

    test "ignores atoms and numbers" do
      assert Pattern.extract_variables(:ok) == []
      assert Pattern.extract_variables(42) == []
      assert Pattern.extract_variables("string") == []
    end

    test "extracts variables from list pattern" do
      pattern = [{:x, :_, nil}, {:y, :_, nil}]
      variables = Pattern.extract_variables(pattern)
      assert Enum.sort(variables) == [:x, :y]
    end

    test "extracts variables from map pattern" do
      pattern = {:%, :_, [Map, [{:key, {:x, :_, nil}}]]}
      assert Pattern.extract_variables(pattern) == [:x]
    end

    test "extracts variables from struct pattern" do
      pattern = {:%, :_, [{:__aliases__, :_, [:MyStruct]}, [{:field, {:x, :_, nil}}]]}
      assert Pattern.extract_variables(pattern) == [:x]
    end

    test "extracts variables from cons pattern" do
      pattern = {:cons, :_, [{:head, :_, nil}, {:tail, :_, nil}]}
      variables = Pattern.extract_variables(pattern)
      assert Enum.sort(variables) == [:head, :tail]
    end

    test "extracts variables from when pattern" do
      pattern = {:when, :_, [{:x, :_, nil}, {:guard, :_, nil}]}
      assert Pattern.extract_variables(pattern) == [:x]
    end

    test "extracts variables from binary pattern" do
      pattern = {:<<>>, :_, [{:x, :_, nil}]}
      assert Pattern.extract_variables(pattern) == [:x]
    end

    test "removes duplicate variables" do
      pattern = {:tuple, :_, [{:x, :_, nil}, {:x, :_, nil}]}
      variables = Pattern.extract_variables(pattern)
      assert variables == [:x]
    end

    test "handles nested patterns" do
      pattern = {:tuple, :_, [{:tuple, :_, [{:a, :_, nil}, {:b, :_, nil}]}, {:c, :_, nil}]}
      variables = Pattern.extract_variables(pattern)
      assert Enum.sort(variables) == [:a, :b, :c]
    end

    test "handles empty tuple pattern" do
      pattern = {:tuple, :_, []}
      assert Pattern.extract_variables(pattern) == []
    end

    test "handles mixed variable and literal patterns" do
      pattern = {:tuple, :_, [{:x, :_, nil}, :ok, 42]}
      assert Pattern.extract_variables(pattern) == [:x]
    end
  end

  describe "infer_pattern_types/2" do
    test "infers type for simple variable" do
      pattern = {:x, :_, nil}
      scrutinee_type = {:integer, []}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      assert bindings[:x] == {:integer, []}
    end

    test "infers types for tuple pattern" do
      pattern = {:tuple, :_, [{:a, :_, nil}, {:b, :_, nil}]}
      scrutinee_type = {:tuple, :_, [{:integer, []}, {:atom, []}]}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      assert bindings[:a] == {:integer, []}
      assert bindings[:b] == {:atom, []}
    end

    test "ignores underscore in type inference" do
      pattern = :_
      scrutinee_type = {:integer, []}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      assert bindings == %{}
    end

    test "ignores underscore tuple in type inference" do
      pattern = {:_, :_, nil}
      scrutinee_type = {:integer, []}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      assert bindings == %{}
    end

    test "infers types for list pattern with cons" do
      pattern = [{:head, :_, nil}]
      scrutinee_type = {:list, [{:integer, []}]}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      assert bindings[:head] == {:integer, []}
    end

    test "infers types for map pattern" do
      pattern = {:%, :_, [Map, [{:key, {:x, :_, nil}}]]}
      scrutinee_type = {:map, []}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      # Map patterns get fresh type variables
      assert Map.has_key?(bindings, :x)
    end

    test "infers type variables for unknown types" do
      pattern = {:x, :_, nil}
      scrutinee_type = {:unknown_type, []}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      # Should assign fresh type variable
      assert Map.has_key?(bindings, :x)
    end

    test "handles nested tuple patterns" do
      pattern = {:tuple, :_, [{:tuple, :_, [{:a, :_, nil}]}, {:b, :_, nil}]}
      scrutinee_type = {:tuple, :_, [{:tuple, :_, [{:integer, []}]}, {:atom, []}]}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      assert bindings[:a] == {:integer, []}
      assert bindings[:b] == {:atom, []}
    end

    test "handles mismatched pattern and type" do
      pattern = {:x, :_, nil}
      scrutinee_type = {:tuple, :_, []}
      bindings = Pattern.infer_pattern_types(pattern, scrutinee_type)
      # Should assign type variable
      assert Map.has_key?(bindings, :x)
    end
  end

  describe "simple_pattern?/1" do
    test "identifies simple variable pattern" do
      assert Pattern.simple_pattern?({:x, :_, nil})
    end

    test "identifies simple atom pattern" do
      assert Pattern.simple_pattern?(:ok)
    end

    test "identifies simple number pattern" do
      assert Pattern.simple_pattern?(42)
    end

    test "identifies simple binary pattern" do
      assert Pattern.simple_pattern?("hello")
    end

    test "rejects tuple pattern" do
      refute Pattern.simple_pattern?({:tuple, :_, [{:x, :_, nil}]})
    end

    test "rejects list pattern" do
      refute Pattern.simple_pattern?([{:x, :_, nil}])
    end

    test "rejects map pattern" do
      refute Pattern.simple_pattern?({:%, :_, [Map, []]})
    end

    test "rejects cons pattern" do
      refute Pattern.simple_pattern?({:cons, :_, [{:x, :_, nil}, {:y, :_, nil}]})
    end

    test "rejects complex structures" do
      refute Pattern.simple_pattern?({:%, :_, [{:__aliases__, :_, [:Struct]}, []]})
    end

    test "handles underscore" do
      assert Pattern.simple_pattern?({:_, :_, nil})
    end
  end

  describe "complex_pattern?/1" do
    test "identifies complex tuple pattern" do
      assert Pattern.complex_pattern?({:tuple, :_, [{:x, :_, nil}]})
    end

    test "identifies complex map pattern" do
      assert Pattern.complex_pattern?({:%, :_, [Map, []]})
    end

    test "identifies complex list pattern" do
      assert Pattern.complex_pattern?([{:x, :_, nil}])
    end

    test "rejects simple variable pattern" do
      refute Pattern.complex_pattern?({:x, :_, nil})
    end

    test "rejects simple atom pattern" do
      refute Pattern.complex_pattern?(:ok)
    end

    test "rejects simple number pattern" do
      refute Pattern.complex_pattern?(42)
    end

    test "is opposite of simple_pattern" do
      patterns = [
        {:x, :_, nil},
        :ok,
        42,
        "string",
        {:tuple, :_, [{:x, :_, nil}]},
        [{:x, :_, nil}]
      ]

      Enum.each(patterns, fn pattern ->
        simple = Pattern.simple_pattern?(pattern)
        complex = Pattern.complex_pattern?(pattern)
        assert simple != complex
      end)
    end
  end

  describe "extract_variables_from_list/1" do
    test "extracts variables from list of patterns" do
      patterns = [{:x, :_, nil}, {:y, :_, nil}]
      variables = Pattern.extract_variables_from_list(patterns)
      assert Enum.sort(variables) == [:x, :y]
    end

    test "extracts variables from nested patterns" do
      patterns = [{:tuple, :_, [{:a, :_, nil}, {:b, :_, nil}]}, {:c, :_, nil}]
      variables = Pattern.extract_variables_from_list(patterns)
      assert Enum.sort(variables) == [:a, :b, :c]
    end

    test "removes duplicates" do
      patterns = [{:x, :_, nil}, {:x, :_, nil}]
      variables = Pattern.extract_variables_from_list(patterns)
      assert variables == [:x]
    end

    test "handles empty list" do
      assert Pattern.extract_variables_from_list([]) == []
    end

    test "handles mixed simple and complex patterns" do
      patterns = [{:x, :_, nil}, {:tuple, :_, [{:y, :_, nil}]}, :ok]
      variables = Pattern.extract_variables_from_list(patterns)
      assert Enum.sort(variables) == [:x, :y]
    end
  end

  describe "pattern_name/1" do
    test "names simple variable pattern" do
      assert Pattern.pattern_name({:x, :_, nil}) == "x"
    end

    test "names tuple pattern" do
      assert Pattern.pattern_name({:tuple, :_, [{:x, :_, nil}]}) == "tuple"
    end

    test "names map pattern" do
      assert Pattern.pattern_name({:%, :_, [Map, []]}) == "map"
    end

    test "names struct pattern" do
      assert Pattern.pattern_name({:%, :_, [{:__aliases__, :_, [:MyStruct]}, []]}) == "MyStruct"
    end

    test "names generic struct pattern" do
      # pattern_name only uses the last part of the module path
      assert Pattern.pattern_name({:%, :_, [{:__aliases__, :_, [:A, :B, :C]}, []]}) == "C"
    end

    test "names cons pattern" do
      assert Pattern.pattern_name({:cons, :_, [{:x, :_, nil}, {:y, :_, nil}]}) == "list"
    end

    test "names list pattern" do
      assert Pattern.pattern_name([{:x, :_, nil}]) == "list"
    end

    test "names binary pattern" do
      assert Pattern.pattern_name({:<<>>, :_, []}) == "binary"
    end

    test "names atom pattern" do
      assert Pattern.pattern_name(:ok) == "ok"
    end

    test "names number pattern" do
      assert Pattern.pattern_name(42) == "42"
    end

    test "names string pattern" do
      assert Pattern.pattern_name("hello") == "\"hello\""
    end

    test "names underscore pattern" do
      assert Pattern.pattern_name({:_, :_, nil}) == "_"
    end
  end

  describe "edge cases" do
    test "handles deeply nested patterns" do
      pattern = {:tuple, :_, [{:tuple, :_, [{:tuple, :_, [{:x, :_, nil}]}]}]}
      variables = Pattern.extract_variables(pattern)
      assert variables == [:x]
    end

    test "handles patterns with mixed atoms and variables" do
      pattern = {:tuple, :_, [{:x, :_, nil}, :ok, {:y, :_, nil}, 42]}
      variables = Pattern.extract_variables(pattern)
      assert Enum.sort(variables) == [:x, :y]
    end

    test "handles cons patterns with nested structures" do
      pattern = {:cons, :_, [{:tuple, :_, [{:a, :_, nil}, {:b, :_, nil}]}, {:tail, :_, nil}]}
      variables = Pattern.extract_variables(pattern)
      assert Enum.sort(variables) == [:a, :b, :tail]
    end

    test "handles map patterns with multiple fields" do
      pattern = {:%, :_, [Map, [{:key1, {:x, :_, nil}}, {:key2, {:y, :_, nil}}]]}
      variables = Pattern.extract_variables(pattern)
      assert Enum.sort(variables) == [:x, :y]
    end

    test "handles when patterns with complex inner pattern" do
      pattern = {:when, :_, [{:tuple, :_, [{:x, :_, nil}]}, {:guard, :_, nil}]}
      variables = Pattern.extract_variables(pattern)
      assert variables == [:x]
    end

    test "handles binary patterns with multiple segments" do
      pattern = {:<<>>, :_, [{:a, :_, nil}, {:b, :_, nil}, {:c, :_, nil}]}
      variables = Pattern.extract_variables(pattern)
      assert Enum.sort(variables) == [:a, :b, :c]
    end

    test "pattern_name handles unrecognized patterns" do
      # Should not crash on unknown patterns
      result = Pattern.pattern_name({:unknown, :_, nil})
      assert is_binary(result)
    end

    test "extract_variables handles recursive data structures" do
      # Pattern with repeated variables
      pattern = {:tuple, :_, [{:x, :_, nil}, {:x, :_, nil}, {:x, :_, nil}]}
      variables = Pattern.extract_variables(pattern)
      # Should only have unique variables
      assert variables == [:x]
    end
  end
end
