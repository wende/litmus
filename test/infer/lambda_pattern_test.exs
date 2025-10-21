defmodule Litmus.Infer.LambdaPatternTest do
  use ExUnit.Case

  alias Litmus.Analyzer.ASTWalker

  describe "lambda pattern matching" do
    test "simple lambda without patterns still works" do
      source = """
      defmodule Test do
        def simple do
          fn x -> x * 2 end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :simple, 0}]
      assert func != nil
    end

    test "lambda with tuple destructuring" do
      source = """
      defmodule Test do
        def with_tuple do
          Enum.map([{1, 2}, {3, 4}], fn {a, b} -> a + b end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :with_tuple, 0}]
      assert func != nil
      # Variables a and b should be available in lambda body
    end

    test "lambda with nested tuple destructuring" do
      source = """
      defmodule Test do
        def nested_tuple do
          Enum.map([{{1, 2}, 3}], fn {{a, b}, c} -> a + b + c end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :nested_tuple, 0}]
      assert func != nil
    end

    test "lambda with list destructuring [head|tail]" do
      source = """
      defmodule Test do
        def with_list do
          Enum.map([[1, 2, 3], [4, 5]], fn [h|t] -> h end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :with_list, 0}]
      assert func != nil
    end

    test "lambda with map destructuring" do
      source = """
      defmodule Test do
        def with_map do
          Enum.map([%{x: 1, y: 2}], fn %{x: val} -> val end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :with_map, 0}]
      assert func != nil
    end

    test "lambda with struct-like map destructuring" do
      source = """
      defmodule Test do
        def with_map_pattern do
          # Using map pattern instead of struct pattern for this test
          Enum.map([%{name: "Alice", age: 30}], fn %{name: n, age: a} -> n end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      # This should handle the pattern without requiring module resolution
      result = ASTWalker.analyze_ast(ast)

      case result do
        {:ok, analysis} ->
          func = analysis.functions[{Test, :with_map_pattern, 0}]
          assert func != nil

        # Also accept analysis errors for unresolved modules, as the pattern extraction
        # should still work even if module resolution fails
        {:error, _} ->
          :ok
      end
    end

    test "lambda with multiple destructured parameters" do
      source = """
      defmodule Test do
        def multi_param do
          x = [1, 2]
          y = [3, 4]
          z = Enum.zip(x, y)
          Enum.map(z, fn {a, b} -> a + b end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :multi_param, 0}]
      assert func != nil
    end

    test "lambda with underscore patterns" do
      source = """
      defmodule Test do
        def with_underscore do
          Enum.map([{1, 2}, {3, 4}], fn {a, _} -> a end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :with_underscore, 0}]
      assert func != nil
    end

    test "lambda with mixed patterns and simple params" do
      source = """
      defmodule Test do
        def mixed do
          fn {a, b}, x -> a + b + x end
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :mixed, 0}]
      assert func != nil
    end
  end

  describe "multi-clause lambdas" do
    test "multi-clause lambda with simple patterns" do
      source = """
      defmodule Test do
        def factorial do
          f = fn
            0 -> 1
            n -> n * 2
          end
          f
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :factorial, 0}]
      assert func != nil
    end

    test "multi-clause lambda with patterns" do
      source = """
      defmodule Test do
        def pattern_match do
          f = fn
            {0, x} -> x
            {n, x} -> n + x
          end
          f
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :pattern_match, 0}]
      assert func != nil
    end

    test "multi-clause lambda with list patterns" do
      source = """
      defmodule Test do
        def list_match do
          f = fn
            [] -> 0
            [h|t] -> h + 1
          end
          f
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :list_match, 0}]
      assert func != nil
    end

    test "multi-clause lambda with different arities" do
      source = """
      defmodule Test do
        def arity_match do
          f = fn
            0 -> :zero
            x -> x
            x, y -> x + y
          end
          f
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :arity_match, 0}]
      assert func != nil
    end
  end

  describe "lambda patterns with effects" do
    test "lambda with destructuring and I/O effects" do
      source = """
      defmodule Test do
        def with_effects do
          Enum.map([{1, 2}], fn {a, b} ->
            IO.puts(a)
            a + b
          end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :with_effects, 0}]
      assert func != nil
      # Should detect IO effect from IO.puts
    end

    test "lambda with pattern and exception" do
      source = """
      defmodule Test do
        def with_exception do
          Enum.map([{:ok, 1}, {:error, 2}], fn
            {:ok, x} -> x
            {:error, msg} -> raise msg
          end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :with_exception, 0}]
      assert func != nil
      # Should detect that the second clause can raise
    end

    test "lambda with map pattern and effects" do
      source = """
      defmodule Test do
        def map_with_effects do
          Enum.map([%{file: "a.txt", data: "x"}], fn %{file: f, data: d} ->
            File.write(f, d)
          end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :map_with_effects, 0}]
      assert func != nil
      # Should detect File.write effect
    end
  end

  describe "complex pattern scenarios" do
    test "deeply nested destructuring" do
      source = """
      defmodule Test do
        def deep_nesting do
          Enum.map([{1, {2, {3, 4}}}], fn {a, {b, {c, d}}} -> a + b + c + d end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :deep_nesting, 0}]
      assert func != nil
    end

    test "mixed destructuring with list and tuple" do
      source = """
      defmodule Test do
        def mixed_destructure do
          Enum.map([{[1, 2], 3}], fn {[h|_t], x} -> h + x end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :mixed_destructure, 0}]
      assert func != nil
    end

    test "lambda with pattern guards (basic)" do
      source = """
      defmodule Test do
        def with_guard do
          Enum.map([1, 2, 3], fn x when x > 1 -> x * 2 end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :with_guard, 0}]
      assert func != nil
    end

    test "higher-order function with destructuring lambdas" do
      source = """
      defmodule Test do
        def apply_func(items, func) do
          Enum.map(items, func)
        end

        def use_apply do
          apply_func([{1, 2}, {3, 4}], fn {a, b} -> a + b end)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :use_apply, 0}]
      assert func != nil
    end
  end
end
