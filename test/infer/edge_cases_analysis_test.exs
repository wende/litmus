defmodule EdgeCasesAnalysisTest do
  use ExUnit.Case
  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.Core

  # Helper to analyze a module and get function effect
  defp get_function_effect(module, function, arity) do
    source_file = "test/support/edge_cases_test.exs"
    {:ok, source} = File.read(source_file)
    {:ok, ast} = Code.string_to_quoted(source, file: source_file)

    case ASTWalker.analyze_ast(ast) do
      {:ok, result} ->
        mfa = {module, function, arity}
        case Map.get(result.functions, mfa) do
          nil -> {:error, :function_not_found}
          func_analysis -> {:ok, func_analysis}
        end
      error -> error
    end
  end

  # Helper to check compact effect type
  defp assert_effect_type(module, function, arity, expected_compact) do
    case get_function_effect(module, function, arity) do
      {:ok, func_analysis} ->
        compact = Core.to_compact_effect(func_analysis.effect)
        assert compact == expected_compact,
          "Expected #{function}/#{arity} to have effect #{inspect(expected_compact)}, got #{inspect(compact)}"
        func_analysis
      {:error, reason} ->
        flunk("Failed to analyze #{function}/#{arity}: #{inspect(reason)}")
    end
  end

  describe "Lambda-Dependent Functions" do
    test "higher_order_pure/1 is lambda-dependent" do
      assert_effect_type(Support.EdgeCasesTest, :higher_order_pure, 1, :l)
    end

    test "higher_order_with_args/3 is lambda-dependent" do
      assert_effect_type(Support.EdgeCasesTest, :higher_order_with_args, 3, :l)
    end

    test "call_higher_order_with_pure_lambda/0 calls higher-order function" do
      # Note: When analyzed standalone, this shows as unknown because
      # higher_order_pure is a local function not in the cache
      func = assert_effect_type(Support.EdgeCasesTest, :call_higher_order_with_pure_lambda, 0, :u)
      # Local function calls appear as Kernel calls when analyzed standalone
      assert {Kernel, :higher_order_pure, 1} in func.calls
    end

    test "call_higher_order_with_effectful_lambda/0 calls higher-order with effects" do
      # Note: When analyzed standalone, local function calls show as unknown
      # The IO.puts effect is inside the lambda, not a direct call
      func = assert_effect_type(Support.EdgeCasesTest, :call_higher_order_with_effectful_lambda, 0, :u)
      # Local function calls appear as Kernel calls when analyzed standalone
      assert {Kernel, :higher_order_pure, 1} in func.calls
      # IO.puts is inside the lambda passed to higher_order_pure
      assert {IO, :puts, 1} in func.calls
    end
  end

  describe "Block Expressions" do
    test "block_pure_statements/2 is pure" do
      assert_effect_type(Support.EdgeCasesTest, :block_pure_statements, 2, :p)
    end

    test "block_mixed_effects/1 is effectful" do
      func = assert_effect_type(Support.EdgeCasesTest, :block_mixed_effects, 1, :s)
      assert {IO, :puts, 1} in func.calls
    end

    test "log_and_save/2 is effectful" do
      func = assert_effect_type(Support.EdgeCasesTest, :log_and_save, 2, :s)
      assert {IO, :puts, 1} in func.calls
      assert {File, :write!, 2} in func.calls
    end
  end

  describe "Exception Effects" do
    test "exception_explicit_raise/0 has exception effect" do
      func = assert_effect_type(Support.EdgeCasesTest, :exception_explicit_raise, 0, {:e, [:exn]})
      assert {Kernel, :raise, 2} in func.calls
    end

    test "exception_division/2 has exception effect" do
      assert_effect_type(Support.EdgeCasesTest, :exception_division, 2, {:e, [:exn]})
    end

    test "exception_from_stdlib/1 has exception effect" do
      assert_effect_type(Support.EdgeCasesTest, :exception_from_stdlib, 1, {:e, [:exn]})
    end
  end

  describe "Unknown Effects (apply)" do
    test "unknown_apply_kernel/0 is unknown" do
      func = assert_effect_type(Support.EdgeCasesTest, :unknown_apply_kernel, 0, :u)
      assert {Kernel, :apply, 3} in func.calls
    end

    test "unknown_apply_3/3 is unknown" do
      assert_effect_type(Support.EdgeCasesTest, :unknown_apply_3, 3, :u)
    end

    test "unknown_apply_lambda/2 is unknown" do
      assert_effect_type(Support.EdgeCasesTest, :unknown_apply_lambda, 2, :u)
    end
  end

  describe "Module Aliases" do
    test "use_module_aliases/0 is pure" do
      assert_effect_type(Support.EdgeCasesTest, :use_module_aliases, 0, :p)
    end
  end

  describe "String Interpolation" do
    test "string_interpolation/2 is pure" do
      assert_effect_type(Support.EdgeCasesTest, :string_interpolation, 2, :p)
    end

    test "string_interpolation_with_effects/1 is effectful" do
      func = assert_effect_type(Support.EdgeCasesTest, :string_interpolation_with_effects, 1, :s)
      assert {IO, :inspect, 1} in func.calls
    end
  end

  describe "If Expressions" do
    test "if_pure/2 is pure" do
      assert_effect_type(Support.EdgeCasesTest, :if_pure, 2, :p)
    end

    test "if_effectful_then/1 is effectful" do
      func = assert_effect_type(Support.EdgeCasesTest, :if_effectful_then, 1, :s)
      assert {IO, :puts, 1} in func.calls
    end

    test "if_effectful_else/1 is effectful" do
      func = assert_effect_type(Support.EdgeCasesTest, :if_effectful_else, 1, :s)
      assert {File, :write!, 2} in func.calls
    end
  end

  describe "Pipe Operators" do
    test "pipe_all_pure/1 is pure" do
      func = assert_effect_type(Support.EdgeCasesTest, :pipe_all_pure, 1, :p)
      assert {String, :upcase, 1} in func.calls
      assert {String, :trim, 1} in func.calls
      assert {String, :reverse, 1} in func.calls
    end

    test "pipe_with_effect_in_middle/1 is effectful" do
      func = assert_effect_type(Support.EdgeCasesTest, :pipe_with_effect_in_middle, 1, :s)
      assert {IO, :inspect, 2} in func.calls
    end

    test "pipe_with_lambda_dependent/1 is pure" do
      func = assert_effect_type(Support.EdgeCasesTest, :pipe_with_lambda_dependent, 1, :p)
      assert {Enum, :map, 2} in func.calls
      assert {Enum, :sum, 1} in func.calls
    end

    test "pipe_with_exception/1 has exception effect" do
      assert_effect_type(Support.EdgeCasesTest, :pipe_with_exception, 1, {:e, [:exn]})
    end
  end

  describe "Context-Dependent Effects" do
    test "dependent_process_get/1 is context-dependent" do
      func = assert_effect_type(Support.EdgeCasesTest, :dependent_process_get, 1, :d)
      assert {Process, :get, 1} in func.calls
    end

    test "dependent_system_time/0 is context-dependent" do
      func = assert_effect_type(Support.EdgeCasesTest, :dependent_system_time, 0, :d)
      assert {System, :system_time, 0} in func.calls
    end

    test "dependent_ets_lookup/2 is context-dependent" do
      assert_effect_type(Support.EdgeCasesTest, :dependent_ets_lookup, 2, :d)
    end
  end

  describe "Nested Scenarios" do
    test "nested_exception_in_blocks/1 is effectful" do
      func = assert_effect_type(Support.EdgeCasesTest, :nested_exception_in_blocks, 1, :s)
      assert {Enum, :map, 2} in func.calls
      assert {IO, :puts, 1} in func.calls
    end

    test "nested_with_effects_at_all_levels/1 is effectful" do
      func = assert_effect_type(Support.EdgeCasesTest, :nested_with_effects_at_all_levels, 1, :s)
      assert {IO, :puts, 1} in func.calls
    end
  end
end
