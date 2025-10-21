defmodule RegressionAnalysisTest do
  use ExUnit.Case
  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.Core

  # Helper to analyze a module and get function effect
  defp get_function_effect(module, function, arity) do
    source_file = "test/support/regression_test.exs"
    {:ok, source} = File.read(source_file)
    {:ok, ast} = Code.string_to_quoted(source, file: source_file)

    case ASTWalker.analyze_ast(ast) do
      {:ok, result} ->
        mfa = {module, function, arity}

        case Map.get(result.functions, mfa) do
          nil -> {:error, :function_not_found}
          func_analysis -> {:ok, func_analysis}
        end

      error ->
        error
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

  describe "Bug #1: Higher-Order Functions" do
    test "bug_1_higher_order_function/1 is lambda-dependent (not unknown)" do
      assert_effect_type(Support.RegressionTest, :bug_1_higher_order_function, 1, :l)
    end

    test "bug_1_call_with_pure_lambda/0 calls higher-order function" do
      # Now resolved: local functions are added to runtime cache during analysis
      func = assert_effect_type(Support.RegressionTest, :bug_1_call_with_pure_lambda, 0, :p)
      assert {Kernel, :bug_1_higher_order_function, 1} in func.calls
    end

    test "bug_1_call_with_effectful_lambda/0 calls higher-order function with effects" do
      # Now resolved: local functions are added to runtime cache during analysis
      func =
        assert_effect_type(
          Support.RegressionTest,
          :bug_1_call_with_effectful_lambda,
          0,
          {:s, ["IO.puts/1"]}
        )

      assert {Kernel, :bug_1_higher_order_function, 1} in func.calls
      assert {IO, :puts, 1} in func.calls
    end
  end

  describe "Bug #2: Block Expressions" do
    test "bug_2_log_and_save/2 is effectful (not unknown)" do
      # File.write!/2 now resolves to bottommost File.write/3 + helpers
      # Effects are deduplicated and sorted
      func =
        assert_effect_type(
          Support.RegressionTest,
          :bug_2_log_and_save,
          2,
          {:s, ["File.write/3", "IO.puts/1", "IO.warn/1"]}
        )

      assert {IO, :puts, 1} in func.calls
      assert {File, :write!, 2} in func.calls
    end

    test "bug_2_pure_block/2 is pure" do
      assert_effect_type(Support.RegressionTest, :bug_2_pure_block, 2, :p)
    end
  end

  describe "Bug #3: Variables with Context" do
    test "bug_3_variables_with_context/2 is pure" do
      assert_effect_type(Support.RegressionTest, :bug_3_variables_with_context, 2, :p)
    end
  end

  describe "Bug #4: Exception Functions" do
    test "bug_4_exception_with_module_alias/0 has exception effect (not unknown)" do
      func =
        assert_effect_type(
          Support.RegressionTest,
          :bug_4_exception_with_module_alias,
          0,
          {:e, ["Elixir.ArgumentError"]}
        )

      assert {Kernel, :raise, 2} in func.calls
    end

    test "bug_4_exception_runtime_error/0 has exception effect" do
      func =
        assert_effect_type(
          Support.RegressionTest,
          :bug_4_exception_runtime_error,
          0,
          {:e, ["Elixir.RuntimeError"]}
        )

      assert {Kernel, :raise, 2} in func.calls
    end
  end

  describe "Bug #5: Apply Function" do
    test "bug_5_unknown_apply/0 is unknown (not effectful)" do
      func = assert_effect_type(Support.RegressionTest, :bug_5_unknown_apply, 0, :u)
      assert {Kernel, :apply, 3} in func.calls
    end

    test "bug_5_unknown_apply_3/3 is unknown" do
      func = assert_effect_type(Support.RegressionTest, :bug_5_unknown_apply_3, 3, :u)
      assert {Kernel, :apply, 3} in func.calls
    end
  end

  describe "Bug #6: Cross-Module Lambda-Dependent" do
    test "bug_6_call_lambda_dependent/0 calls lambda-dependent function" do
      # Since Bug6Helper is defined in the same file, it's analyzed together
      # and the call resolves to pure (lambda-dependent with pure lambda)
      func = assert_effect_type(Support.RegressionTest, :bug_6_call_lambda_dependent, 0, :p)
      # Nested module calls appear without full module path
      assert {Bug6Helper, :lambda_dependent_func, 1} in func.calls
    end
  end

  describe "Bug #8: Enum.reduce" do
    test "bug_8_reduce_with_pure_lambda/1 is pure" do
      func = assert_effect_type(Support.RegressionTest, :bug_8_reduce_with_pure_lambda, 1, :p)
      assert {Enum, :reduce, 3} in func.calls
    end

    test "bug_8_reduce_with_effectful_lambda/1 is effectful" do
      func =
        assert_effect_type(
          Support.RegressionTest,
          :bug_8_reduce_with_effectful_lambda,
          1,
          {:s, ["IO.puts/1"]}
        )

      assert {Enum, :reduce, 3} in func.calls
      assert {IO, :puts, 1} in func.calls
    end
  end

  describe "Integration Tests" do
    test "integration_test_2/2 is lambda-dependent" do
      assert_effect_type(Support.RegressionTest, :integration_test_2, 2, :l)
    end

    test "integration_test_2_pure/0 calls integration_test_2" do
      # Now resolved: local functions are added to runtime cache during analysis
      func = assert_effect_type(Support.RegressionTest, :integration_test_2_pure, 0, :p)
      assert {Kernel, :integration_test_2, 2} in func.calls
    end

    test "integration_test_2_effectful/0 calls integration_test_2 with effects" do
      # Now resolved: local functions are added to runtime cache during analysis
      func =
        assert_effect_type(
          Support.RegressionTest,
          :integration_test_2_effectful,
          0,
          {:s, ["IO.puts/1"]}
        )

      assert {Kernel, :integration_test_2, 2} in func.calls
      assert {IO, :puts, 1} in func.calls
    end
  end
end
