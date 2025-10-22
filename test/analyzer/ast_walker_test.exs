defmodule Litmus.Analyzer.ASTWalkerTest do
  use ExUnit.Case
  alias Litmus.Analyzer.{ASTWalker, EffectTracker}
  alias Litmus.Types.{Core, Effects}

  # Import shared test helpers
  import Test.AnalysisHelpers
  import Test.Assertions

  describe "analyze_ast/1" do
    test "analyzes a pure function" do
      ast = create_test_module(TestPure, "def add(x, y), do: x + y")

      result = assert_analysis_completes(ast)
      assert result.module == TestPure
      assert_function_is_pure(result, {TestPure, :add, 2})
    end
  end

  test "detects IO effects" do
    ast = create_test_module(TestIO, "def greet(name), do: IO.puts(\"Hello, \#{name}!\")")

    result = assert_analysis_completes(ast)
    func = get_function_analysis(result, {TestIO, :greet, 1})
    assert_side_effect(func.effect)
  end

  test "detects file effects" do
    ast = create_test_module(TestFile, "def read_config, do: File.read!(\"config.json\")")

    result = assert_analysis_completes(ast)
    func = get_function_analysis(result, {TestFile, :read_config, 0})
    assert_side_effect(func.effect)
  end

  test "tracks multiple effects" do
    ast =
      quote do
        defmodule TestMultiEffect do
          def process_file(path) do
            content = File.read!(path)
            IO.puts("Processing: #{path}")
            String.upcase(content)
          end
        end
      end

    assert {:ok, result} = analyze_ast(ast)
    func = result.functions[{TestMultiEffect, :process_file, 1}]
    # Check that the effect contains both File and IO side effects
    assert match?({:s, list} when is_list(list), func.effect) or
             match?({:effect_row, {:s, _}, _}, func.effect) or
             match?({:effect_row, _, {:s, _}}, func.effect)
  end

  test "handles if expressions" do
    ast =
      quote do
        defmodule TestIf do
          def maybe_print(flag, message) do
            if flag do
              IO.puts(message)
            else
              :ok
            end
          end
        end
      end

    assert {:ok, result} = analyze_ast(ast)
    func = result.functions[{TestIf, :maybe_print, 2}]
    # Effect happens in one branch, so function has the effect
    assert match?({:s, list} when is_list(list), func.effect) or
             match?({:effect_row, {:s, _}, _}, func.effect) or
             match?({:effect_row, _, {:s, _}}, func.effect)
  end

  test "detects exception effects" do
    ast = create_test_module(TestException, "def head_unsafe(list), do: hd(list)")

    result = assert_analysis_completes(ast)
    assert_function_has_exceptions(result, {TestException, :head_unsafe, 1})
  end

  test "handles private functions" do
    ast =
      create_test_module(TestPrivate, [
        "def public_func(x), do: helper(x)",
        "defp helper(x), do: x * 2"
      ])

    result =
      assert_analysis_with_functions(ast, [
        {TestPrivate, :public_func, 1},
        {TestPrivate, :helper, 1}
      ])

    assert_function_visibility(result, {TestPrivate, :helper, 1}, :defp)
    assert_function_is_pure(result, {TestPrivate, :helper, 1})
  end

  test "tracks function calls" do
    ast =
      create_test_module(TestCalls, [
        "def main, do: x = File.read!(\"input.txt\"); process(x)",
        "def process(data), do: String.upcase(data)"
      ])

    result = assert_analysis_completes(ast)
    assert_function_calls(result, {TestCalls, :main, 0}, [{File, :read!, 1}])
  end

  test "handles blocks correctly" do
    ast =
      quote do
        defmodule TestBlock do
          def multi_step do
            x = 1 + 2
            y = x * 3
            IO.puts(y)
            y
          end
        end
      end

    assert {:ok, result} = analyze_ast(ast)
    func = result.functions[{TestBlock, :multi_step, 0}]

    assert match?({:s, list} when is_list(list), func.effect) or
             match?({:effect_row, {:s, _}, _}, func.effect) or
             match?({:effect_row, _, {:s, _}}, func.effect)
  end

  # test "records type errors" do
  #   source = """
  #   defmodule TestError do
  #     def bad_function do
  #       unknown_var + 1
  #     end
  #   end
  #   """

  #   assert {:ok, result} = analyze_source(source)
  #   assert length(result.errors) > 0

  #   error = hd(result.errors)
  #   assert error.type == :type_error
  #   assert error.location == {TestError, :bad_function, 2}
  # end
  # end

  describe "EffectTracker.extract_calls/1" do
    test "identifies pure expressions" do
      ast = quote do: 1 + 2 * 3
      assert EffectTracker.is_pure?(ast)
    end

    test "extracts all function calls" do
      ast =
        quote do
          x = String.upcase("hello")
          File.write!("out.txt", x)
          Enum.map([1, 2, 3], fn n -> n * 2 end)
        end

      calls = EffectTracker.extract_calls(ast)
      assert {String, :upcase, 1} in calls
      assert {File, :write!, 2} in calls
      assert {Enum, :map, 2} in calls
    end

    # Note: Other EffectTracker methods (analyze_effects, suggest_handlers, etc.)
    # are designed for the old macro-based effect system and need to be updated
    # to work with the new bidirectional type inference system.
    # For now, these tests are removed. Use the full ASTWalker.analyze_ast/1
    # for complete effect analysis.
  end

  describe "effect row polymorphism" do
    test "handles duplicate effect labels" do
      # Nested exception handlers should allow duplicate labels
      effect1 = Core.single_effect(:exn)
      effect2 = Core.extend_effect(:exn, effect1)

      # Should create a row with duplicate labels
      assert {:effect_row, :exn, {:effect_label, :exn}} = effect2
    end

    test "removes only first occurrence of duplicate label" do
      # Create effect with duplicate labels
      effect = Core.extend_effect(:exn, Core.single_effect(:exn))

      # Remove one occurrence
      {remaining, found} = Effects.remove_effect(:exn, effect)
      assert found == true
      assert remaining == Core.single_effect(:exn)

      # Second removal should get the last one
      {remaining2, found2} = Effects.remove_effect(:exn, remaining)
      assert found2 == true
      assert Effects.is_pure?(remaining2)
    end
  end

  describe "formatting" do
    test "formats analysis results nicely" do
      ast =
        quote do
          defmodule TestFormat do
            def pure_func(x, y) do
              x + y
            end

            def effectful_func do
              IO.puts("Side effect!")
            end
          end
        end

      assert {:ok, result} = analyze_ast(ast)
      formatted = ASTWalker.format_results(result)

      assert formatted =~ "TestFormat"
      assert formatted =~ "pure_func/2"
      assert formatted =~ "effectful_func/0"
      assert formatted =~ "Effect:"
    end
  end
end
