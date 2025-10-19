defmodule InferAnalysisTest do
  use ExUnit.Case
  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.Core

  # Helper to analyze a module and get function effect
  defp get_function_effect(module, function, arity) do
    source_file = "test/support/infer_test.exs"
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

  describe "Pure Functions" do
    test "pure_arithmetic/2 is pure" do
      assert_effect_type(Support.InferTest, :pure_arithmetic, 2, :p)
    end

    test "pure_string_ops/1 is pure" do
      func = assert_effect_type(Support.InferTest, :pure_string_ops, 1, :p)
      assert {String, :upcase, 1} in func.calls
      assert {String, :trim, 1} in func.calls
    end

    test "pure_list_ops/1 is pure" do
      func = assert_effect_type(Support.InferTest, :pure_list_ops, 1, :p)
      assert {Enum, :reverse, 1} in func.calls
      assert {Enum, :take, 2} in func.calls
    end
  end

  describe "Lambda Effect Propagation - Pure Lambdas" do
    test "map_with_pure_lambda/1 is pure" do
      func = assert_effect_type(Support.InferTest, :map_with_pure_lambda, 1, :p)
      assert {Enum, :map, 2} in func.calls
    end

    test "filter_with_pure_lambda/1 is pure" do
      func = assert_effect_type(Support.InferTest, :filter_with_pure_lambda, 1, :p)
      assert {Enum, :filter, 2} in func.calls
    end

    test "reduce_with_pure_lambda/1 is pure" do
      func = assert_effect_type(Support.InferTest, :reduce_with_pure_lambda, 1, :p)
      assert {Enum, :reduce, 3} in func.calls
    end

    test "nested_pure_lambdas/1 is pure" do
      func = assert_effect_type(Support.InferTest, :nested_pure_lambdas, 1, :p)
      assert {Enum, :map, 2} in func.calls
      assert {Enum, :filter, 2} in func.calls
      assert {Enum, :reduce, 3} in func.calls
    end
  end

  describe "Lambda Effect Propagation - Effectful Lambdas" do
    test "map_with_io_lambda/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :map_with_io_lambda, 1, :s)
      assert {Enum, :map, 2} in func.calls
      assert {IO, :puts, 1} in func.calls
    end

    test "filter_with_io_lambda/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :filter_with_io_lambda, 1, :s)
      assert {Enum, :filter, 2} in func.calls
      assert {IO, :inspect, 2} in func.calls
    end

    test "each_always_effectful/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :each_always_effectful, 1, :s)
      assert {Enum, :each, 2} in func.calls
      assert {IO, :puts, 1} in func.calls
    end

    test "mixed_pure_and_effectful/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :mixed_pure_and_effectful, 1, :s)
      assert {Enum, :map, 2} in func.calls
      assert {Enum, :filter, 2} in func.calls
      assert {IO, :puts, 1} in func.calls
    end
  end

  describe "Function Capture - Pure" do
    test "map_with_pure_capture/1 is pure" do
      func = assert_effect_type(Support.InferTest, :map_with_pure_capture, 1, :p)
      assert {Enum, :map, 2} in func.calls
    end

    test "reduce_with_operator_capture/1 is pure" do
      func = assert_effect_type(Support.InferTest, :reduce_with_operator_capture, 1, :p)
      assert {Enum, :reduce, 3} in func.calls
    end

    test "pipe_with_captures/1 is lambda-dependent" do
      # Function captures create lambda-dependent effects
      func = assert_effect_type(Support.InferTest, :pipe_with_captures, 1, :l)
      assert {Enum, :map, 2} in func.calls
      assert {Enum, :filter, 2} in func.calls
      assert {Enum, :reduce, 3} in func.calls
    end
  end

  describe "Function Capture - Effectful" do
    test "map_with_io_capture/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :map_with_io_capture, 1, :s)
      assert {Enum, :map, 2} in func.calls
    end

    test "each_with_io_capture/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :each_with_io_capture, 1, :s)
      assert {Enum, :each, 2} in func.calls
    end
  end

  describe "Mixed Lambdas and Captures" do
    test "mixed_lambda_and_capture/1 is lambda-dependent" do
      # Function captures create lambda-dependent effects
      func = assert_effect_type(Support.InferTest, :mixed_lambda_and_capture, 1, :l)
      assert {Enum, :map, 2} in func.calls
      assert {Enum, :filter, 2} in func.calls
    end

    test "mixed_with_effectful_lambda/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :mixed_with_effectful_lambda, 1, :s)
      assert {Enum, :map, 2} in func.calls
      assert {Enum, :each, 2} in func.calls
      assert {IO, :puts, 1} in func.calls
    end
  end

  describe "Higher-Order with Side Effects" do
    test "spawn_with_pure_lambda/1 is effectful (spawn is always effectful)" do
      func = assert_effect_type(Support.InferTest, :spawn_with_pure_lambda, 1, :s)
      assert {Kernel, :spawn, 1} in func.calls
    end

    test "spawn_with_io_lambda/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :spawn_with_io_lambda, 1, :s)
      assert {Kernel, :spawn, 1} in func.calls
      assert {IO, :puts, 1} in func.calls
    end

    test "task_async_pure/1 is effectful (Task is always effectful)" do
      func = assert_effect_type(Support.InferTest, :task_async_pure, 1, :s)
      assert {Task, :async, 1} in func.calls
    end

    test "task_async_effectful/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :task_async_effectful, 1, :s)
      assert {Task, :async, 1} in func.calls
      assert {IO, :puts, 1} in func.calls
    end
  end

  describe "Side Effects" do
    test "write_to_file/2 is effectful" do
      func = assert_effect_type(Support.InferTest, :write_to_file, 2, :s)
      assert {File, :write!, 2} in func.calls
    end

    test "read_from_file/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :read_from_file, 1, :s)
      assert {File, :read!, 1} in func.calls
    end

    test "log_message/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :log_message, 1, :s)
      assert {IO, :puts, 1} in func.calls
    end

    test "modify_ets/3 is effectful" do
      assert_effect_type(Support.InferTest, :modify_ets, 3, :s)
    end
  end

  describe "Exceptions" do
    test "may_raise_list_error/1 has exception effect" do
      assert_effect_type(Support.InferTest, :may_raise_list_error, 1, {:e, [:exn]})
    end

    test "may_raise_division/2 has exception effect" do
      assert_effect_type(Support.InferTest, :may_raise_division, 2, {:e, [:exn]})
    end

    test "explicit_raise/1 has exception effect" do
      func = assert_effect_type(Support.InferTest, :explicit_raise, 1, {:e, [:exn]})
      assert {Kernel, :raise, 1} in func.calls
    end
  end

  describe "Complex Pipelines" do
    test "complex_pipeline/1 is unknown" do
      # Pattern matching in lambda (fn {k, v} -> ...) creates unknown effects
      func = assert_effect_type(Support.InferTest, :complex_pipeline, 1, :u)
      assert {Enum, :map, 2} in func.calls
      assert {Enum, :filter, 2} in func.calls
      assert {Enum, :group_by, 2} in func.calls
    end

    test "complex_with_io/1 is effectful" do
      func = assert_effect_type(Support.InferTest, :complex_with_io, 1, :s)
      assert {Enum, :map, 2} in func.calls
      assert {IO, :inspect, 2} in func.calls
    end

    test "nested_higher_order/1 is pure" do
      func = assert_effect_type(Support.InferTest, :nested_higher_order, 1, :p)
      assert {Enum, :map, 2} in func.calls
      assert {Enum, :filter, 2} in func.calls
    end
  end

  describe "Edge Cases" do
    test "empty_lambda_body/0 is pure" do
      func = assert_effect_type(Support.InferTest, :empty_lambda_body, 0, :p)
      assert {Enum, :map, 2} in func.calls
    end

    test "lambda_with_pattern_match/1 is unknown" do
      # Pattern matching in lambdas creates unknown effects currently
      func = assert_effect_type(Support.InferTest, :lambda_with_pattern_match, 1, :u)
      assert {Enum, :map, 2} in func.calls
    end
  end
end
