defmodule Litmus.Analyzer.FunctionPatternTest do
  use ExUnit.Case

  alias Litmus.Analyzer.ASTWalker

  import Test.AnalysisHelpers
  import Test.Factories

  describe "function definition pattern matching" do
    test "function with simple variable parameters" do
      source = create_module_source(Test, function_pattern_definitions().simple_vars)
      result = assert_analysis_completes(source)
      assert get_function_analysis(result, {Test, :add, 2})
    end

    test "function with tuple pattern parameter" do
      source = create_module_source(Test, function_pattern_definitions().tuple_param)
      result = assert_analysis_completes(source)
      assert get_function_analysis(result, {Test, :process_tuple, 1})
    end

    test "function with nested tuple pattern" do
      source = create_module_source(Test, function_pattern_definitions().nested_tuple)
      result = assert_analysis_completes(source)
      assert get_function_analysis(result, {Test, :deep, 1})
    end

    test "function with list pattern parameter" do
      source = create_module_source(Test, function_pattern_definitions().list_param)
      result = assert_analysis_completes(source)
      assert get_function_analysis(result, {Test, :head_tail, 1})
    end

    test "function with map pattern parameter" do
      source = create_module_source(Test, function_pattern_definitions().map_param)
      result = assert_analysis_completes(source)
      assert get_function_analysis(result, {Test, :extract_name, 1})
    end

    test "function with multiple pattern parameters" do
      source = """
      defmodule Test do
        def combine({a, b}, {c, d}) do
          a + b + c + d
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :combine, 2}]
      assert func != nil
    end

    test "function with mixed pattern and simple parameters" do
      source = """
      defmodule Test do
        def mixed({a, b}, x, [h|t]) do
          a + b + x + h
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :mixed, 3}]
      assert func != nil
    end

    test "function with underscore patterns" do
      source = """
      defmodule Test do
        def ignore_second({a, _}) do
          a
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :ignore_second, 1}]
      assert func != nil
    end
  end

  describe "function pattern matching with effects" do
    test "function with pattern parameter and I/O effects" do
      source = """
      defmodule Test do
        def log_tuple({x, y}) do
          IO.puts(x)
          x + y
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :log_tuple, 1}]
      assert func != nil
      # Should detect IO effect
    end

    test "function with pattern parameter and exceptions" do
      source = """
      defmodule Test do
        def validate({a, b}) do
          if a < 0, do: raise ArgumentError, message: "negative"
          a + b
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :validate, 1}]
      assert func != nil
      # Should detect ArgumentError exception
    end

    test "function with pattern parameter and file operations" do
      source = """
      defmodule Test do
        def write_to_file({filename, content}) do
          File.write(filename, content)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :write_to_file, 1}]
      assert func != nil
      # Should detect file effect
    end
  end

  describe "multiple clause functions with patterns" do
    test "function with multiple clauses using different patterns" do
      source = """
      defmodule Test do
        def process({:ok, value}) do
          value
        end

        def process({:error, msg}) do
          msg
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :process, 1}]
      assert func != nil
    end

    test "function with atom and pattern clause variants" do
      source = """
      defmodule Test do
        def handle(:ok) do
          true
        end

        def handle({:error, code}) do
          code
        end

        def handle(_) do
          false
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :handle, 1}]
      assert func != nil
    end

    test "function with list patterns in multiple clauses" do
      source = """
      defmodule Test do
        def sum([]) do
          0
        end

        def sum([h|t]) do
          h + sum(t)
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :sum, 1}]
      assert func != nil
    end
  end

  describe "pattern matching with guards" do
    test "function with pattern and guard" do
      source = """
      defmodule Test do
        def positive({a, b}) when a > 0 and b > 0 do
          a + b
        end

        def positive(_) do
          0
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :positive, 1}]
      assert func != nil
    end

    test "function with simple parameter and guard" do
      source = """
      defmodule Test do
        def absolute(x) when x >= 0 do
          x
        end

        def absolute(x) do
          -x
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :absolute, 1}]
      assert func != nil
    end

    test "function with pattern guard using pattern variable" do
      source = """
      defmodule Test do
        def check({x, y}) when x + y > 0 do
          :positive
        end

        def check(_) do
          :non_positive
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :check, 1}]
      assert func != nil
    end
  end

  describe "complex pattern scenarios" do
    test "function with deeply nested patterns" do
      source = """
      defmodule Test do
        def deep({a, {b, {c, d}}}) do
          a + b + c + d
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :deep, 1}]
      assert func != nil
    end

    test "function with mixed list and tuple patterns" do
      source = """
      defmodule Test do
        def mixed({[h|t], x}) do
          h + x
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :mixed, 1}]
      assert func != nil
    end

    test "zero-arity function" do
      source = """
      defmodule Test do
        def constant do
          42
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :constant, 0}]
      assert func != nil
    end

    test "function with catch-all pattern" do
      source = """
      defmodule Test do
        def generic(_) do
          :ok
        end
      end
      """

      {:ok, ast} = Code.string_to_quoted(source)
      {:ok, result} = ASTWalker.analyze_ast(ast)

      func = result.functions[{Test, :generic, 1}]
      assert func != nil
    end
  end
end
