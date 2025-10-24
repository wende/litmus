defmodule ExceptionInferenceTest do
  @moduledoc """
  Test cases for specific exception type inference, including:
  - Identifying exception types the same way as effects (PDR 003)
  - Handling Kernel.raise to identify specific error types (PDR 004)

  Note: This module intentionally contains code that will fail at runtime
  to test exception inference. Compiler warnings about guaranteed failures
  are expected and safe to ignore.
  """

  # Suppress warnings about guaranteed failures (intentional for testing)
  @compile {:no_warn_undefined, []}

  # ============================================================================
  # Basic Specific Exception Types from Standard Library Functions
  # ============================================================================

  # Helper functions to provide values (prevents some compile-time analysis)
  defp get_tuple, do: {:a, :b}
  defp get_index, do: 5
  defp get_ten, do: 10
  defp get_zero, do: 0
  defp get_empty_list, do: []

  def may_raise_argument_error_tuple do
    apply(:erlang, :element, [get_index(), get_tuple()])
  end

  def may_raise_arithmetic_error_div do
    apply(Kernel, :div, [get_ten(), get_zero()])
  end

  def may_raise_arithmetic_error_rem do
    apply(Kernel, :rem, [get_ten(), get_zero()])
  end

  def may_raise_hd_error do
    apply(Kernel, :hd, [get_empty_list()])
  end

  def may_raise_tl_error do
    apply(Kernel, :tl, [get_empty_list()])
  end

  # ============================================================================
  # Kernel.raise with Specific Exception Modules (PDR 004)
  # ============================================================================

  def explicit_raise_with_module do
    raise ArgumentError, "invalid argument"  # Should identify ArgumentError specifically
  end

  def explicit_raise_with_key_error do
    raise KeyError, key: :missing, term: %{}  # Should identify KeyError specifically
  end

  def explicit_raise_with_runtime_error do
    raise RuntimeError, message: "something went wrong"  # Should identify RuntimeError specifically
  end

  def explicit_raise_with_file_error do
    raise File.Error, reason: "enoent", action: "read", path: "missing.txt"  # Should identify File.Error specifically
  end

  def explicit_raise_with_arithmetic_error do
    raise ArithmeticError, message: "bad argument"  # Should identify ArithmeticError specifically
  end

  # ============================================================================
  # Kernel.raise with Exception Structs (PDR 004)
  # ============================================================================

  def explicit_raise_with_struct do
    raise %ArgumentError{message: "struct-based error"}  # Should identify ArgumentError specifically
  end

  def explicit_raise_with_key_error_struct do
    raise %KeyError{key: :missing, term: %{}}  # Should identify KeyError specifically
  end

  # ============================================================================
  # Kernel.raise with Variables (Should Remain Dynamic/Generic)
  # ============================================================================

  def dynamic_raise_variable(error_type) do
    raise error_type  # Should remain as dynamic exception type
  end

  def dynamic_raise_with_message(msg) do
    raise msg  # Should remain as dynamic exception type
  end

  # ============================================================================
  # Functions with Mixed Exception Types (PDR 003)
  # ============================================================================

  def function_with_multiple_specific_exceptions(input) do
    cond do
      is_nil(input) ->
        raise ArgumentError, "input cannot be nil"  # ArgumentError
      is_binary(input) and String.length(input) == 0 ->
        raise KeyError, key: :empty_string  # KeyError
      true ->
        input
    end
  end

  def function_with_standard_and_custom_exceptions(data) do
    case data do
      [] ->
        raise Enum.EmptyError  # Should identify Enum.EmptyError specifically
      %{} = map when not is_map_key(map, :required) ->
        raise KeyError, key: :required, term: map  # Should identify KeyError specifically
      _ ->
        data
    end
  end

  # ============================================================================
  # Exception and Other Effect Combinations (PDR 003 & 004)
  # ============================================================================

  def function_with_exception_and_io_side_effect(input) do
    if is_nil(input) do
      IO.puts("Input was nil")  # Side effect
      raise ArgumentError, "input cannot be nil"  # Should identify ArgumentError specifically
    else
      input
    end
  end

  def function_with_exception_and_dependent_effect(input) do
    pid = self()  # Dependent effect
    if Process.alive?(pid) and is_nil(input) do
      raise ArgumentError, "input cannot be nil"  # Should identify ArgumentError specifically
    else
      input
    end
  end

  # ============================================================================
  # Complex Cases with Higher-Order Functions and Specific Exceptions
  # ============================================================================

  def map_with_specific_exceptions(list) do
    Enum.map(list, fn item ->
      case item do
        nil -> raise ArgumentError, "nil not allowed"  # Should identify ArgumentError
        n when is_number(n) -> n * 2
        _ -> item
      end
    end)
  end

  def higher_order_with_raise_capture(list) do
    Enum.filter(list, &(elem(&1, 0)))  # Should identify potential ArgumentError from elem
  end

  # ============================================================================
  # Edge Cases and Error Scenarios
  # ============================================================================

  def raise_with_complex_expression do
    exception_type = ArgumentError  # This should still be identified as generic since it's a variable
    raise exception_type, message: "complex"
  end

  def nested_raise_scenarios do
    try do
      raise ArgumentError, "inner error"  # Should identify ArgumentError
    rescue
      ArgumentError -> :handled
    end
  end

  # ============================================================================
  # Non-raising Functions for Comparison
  # ============================================================================

  def pure_function_no_exceptions do
    42  # Should be pure, no exceptions
  end

  def function_with_io_no_exceptions(msg) do
    IO.puts(msg)  # Should have side effect, no exceptions
  end

  def function_with_multiple_side_effects_no_exceptions(data) do
    IO.inspect(data, label: "Processing")
    File.write!("temp.txt", inspect(data))  # Should have multiple side effects, no exceptions
  end
end