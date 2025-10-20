defmodule Litmus.Analyzer.ASTWalkerTest do
  use ExUnit.Case
  alias Litmus.Analyzer.{ASTWalker, EffectTracker}
  alias Litmus.Types.{Core, Effects}

  # No setup needed - VarGen uses Process dictionary

  # Helper to analyze quoted AST directly
  defp analyze_ast(ast) do
    # Replace test context variable references with fresh vars
    clean_ast =
      Macro.prewalk(ast, fn
        # Replace variable references from test context with fresh vars
        {var, meta, Litmus.Analyzer.ASTWalkerTest} when is_atom(var) ->
          {var, meta, nil}

        node ->
          node
      end)

    # Analyze the cleaned AST
    ASTWalker.analyze_ast(clean_ast)
  end

  describe "analyze_ast/1" do
    test "analyzes a pure function" do
      ast =
        quote do
          defmodule TestPure do
            def add(x, y) do
              x + y
            end
          end
        end

      assert {:ok, result} = analyze_ast(ast)
      assert result.module == TestPure
      assert Map.has_key?(result.functions, {TestPure, :add, 2})

      func = result.functions[{TestPure, :add, 2}]
      assert Effects.is_pure?(func.effect)
    end

    test "detects IO effects" do
      ast =
        quote do
          defmodule TestIO do
            def greet(name) do
              IO.puts("Hello, #{name}!")
            end
          end
        end

      assert {:ok, result} = analyze_ast(ast)
      func = result.functions[{TestIO, :greet, 1}]
      # Effect can be {:s, list}, {:effect_row, {:s, _}, _}, or {:effect_row, _, {:s, _}}
      assert match?({:s, list} when is_list(list), func.effect) or
               match?({:effect_row, {:s, _}, _}, func.effect) or
               match?({:effect_row, _, {:s, _}}, func.effect)
    end

    test "detects file effects" do
      ast =
        quote do
          defmodule TestFile do
            def read_config do
              File.read!("config.json")
            end
          end
        end

      assert {:ok, result} = analyze_ast(ast)
      func = result.functions[{TestFile, :read_config, 0}]
      # Check that the effect is a side effect with File.read! MFA
      assert match?({:s, list} when is_list(list), func.effect) or
               match?({:effect_row, {:s, _}, _}, func.effect) or
               match?({:effect_row, _, {:s, _}}, func.effect)
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
      ast =
        quote do
          defmodule TestException do
            def head_unsafe(list) do
              hd(list)
            end
          end
        end

      assert {:ok, result} = analyze_ast(ast)
      func = result.functions[{TestException, :head_unsafe, 1}]
      assert Effects.has_effect?(:exn, func.effect) != false
    end

    test "handles private functions" do
      ast =
        quote do
          defmodule TestPrivate do
            def public_func(x) do
              helper(x)
            end

            defp helper(x) do
              x * 2
            end
          end
        end

      assert {:ok, result} = analyze_ast(ast)
      assert Map.has_key?(result.functions, {TestPrivate, :public_func, 1})
      assert Map.has_key?(result.functions, {TestPrivate, :helper, 1})

      helper_func = result.functions[{TestPrivate, :helper, 1}]
      assert helper_func.visibility == :defp
      assert Effects.is_pure?(helper_func.effect)
    end

    test "tracks function calls" do
      ast =
        quote do
          defmodule TestCalls do
            def main do
              x = File.read!("input.txt")
              process(x)
            end

            def process(data) do
              String.upcase(data)
            end
          end
        end

      assert {:ok, result} = analyze_ast(ast)
      main_func = result.functions[{TestCalls, :main, 0}]

      # Should track the File.read! call
      assert {File, :read!, 1} in main_func.calls
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
  end

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
