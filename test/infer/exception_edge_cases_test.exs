defmodule ExceptionEdgeCasesTest do
  @moduledoc """
  Additional edge case tests for exception type inference:
  - Lambdas raising exceptions
  - Non-Kernel raise usage
  - Custom exception modules
  """

  # Import shared test exceptions
  alias Test.Exceptions.{CustomError, DomainError, ValidationError}

  # ============================================================================
  # Basic Custom Exception Raises
  # ============================================================================

  def raise_custom_error do
    raise CustomError, message: "Custom error occurred"
  end

  def raise_domain_error do
    raise DomainError, message: "Invalid domain", domain: "example.com"
  end

  def raise_validation_error do
    raise ValidationError, field: :email, reason: "invalid format"
  end

  def raise_custom_with_struct do
    raise %CustomError{message: "Struct-based custom error"}
  end

  # ============================================================================
  # Lambdas Raising Exceptions
  # ============================================================================

  def lambda_raises_argument_error do
    fn ->
      raise ArgumentError, "Lambda raised error"
    end
  end

  def lambda_raises_custom_error do
    fn x ->
      if x < 0 do
        raise CustomError, message: "Negative value"
      else
        x * 2
      end
    end
  end

  def map_with_lambda_raising(list) do
    Enum.map(list, fn item ->
      if item == nil do
        raise ArgumentError, "nil not allowed"
      else
        item * 2
      end
    end)
  end

  def filter_with_lambda_raising(list) do
    Enum.filter(list, fn item ->
      if item < 0 do
        raise DomainError, message: "Negative numbers not allowed", domain: "positive"
      else
        item > 5
      end
    end)
  end

  def reduce_with_lambda_raising(list) do
    Enum.reduce(list, 0, fn item, acc ->
      if item == :error do
        raise CustomError, message: "Error token encountered"
      else
        acc + item
      end
    end)
  end

  def higher_order_with_exception_lambda(list, processor) do
    # processor is a lambda that might raise
    Enum.map(list, processor)
  end

  # ============================================================================
  # Non-Kernel Raise Usage (Erlang-style)
  # ============================================================================

  def erlang_error_direct do
    :erlang.error(ArgumentError.exception("Direct erlang error"))
  end

  def erlang_throw_value do
    throw(:some_value)
  end

  def erlang_exit_process do
    exit(:normal)
  end

  # ============================================================================
  # Nested Lambdas with Exceptions
  # ============================================================================

  def nested_lambda_with_exception do
    fn x ->
      fn y ->
        if x + y < 0 do
          raise ArgumentError, "Sum cannot be negative"
        else
          x + y
        end
      end
    end
  end

  def lambda_returning_lambda_with_exception(threshold) do
    fn list ->
      Enum.map(list, fn item ->
        if item > threshold do
          raise DomainError, message: "Exceeds threshold", domain: "range"
        else
          item
        end
      end)
    end
  end

  # ============================================================================
  # Mixed Exception Types in Lambdas
  # ============================================================================

  def lambda_with_multiple_exception_types do
    fn input ->
      case input do
        nil ->
          raise ArgumentError, "Input cannot be nil"

        x when x < 0 ->
          raise CustomError, message: "Negative value"

        x when x > 100 ->
          raise DomainError, message: "Value too large", domain: "0..100"

        x ->
          x
      end
    end
  end

  def map_with_mixed_exceptions(list) do
    Enum.map(list, fn
      nil ->
        raise ArgumentError, "nil found"

      :error ->
        raise RuntimeError, "error token found"

      {:custom, _} ->
        raise CustomError, message: "custom tuple found"

      x ->
        x
    end)
  end

  # ============================================================================
  # Exception Propagation Through Lambda Chains
  # ============================================================================

  def chained_lambdas_with_exceptions(list) do
    list
    |> Enum.map(fn x ->
      if x < 0, do: raise(CustomError, message: "negative"), else: x
    end)
    |> Enum.filter(fn x ->
      if x == 0, do: raise(DomainError, message: "zero", domain: "non-zero"), else: x > 5
    end)
    |> Enum.reduce(0, fn x, acc ->
      if x > 100, do: raise(ArgumentError, "too large"), else: acc + x
    end)
  end

  # ============================================================================
  # Dynamic Exception Types in Lambdas
  # ============================================================================

  def lambda_with_dynamic_exception(error_type) do
    fn x ->
      if x < 0 do
        raise error_type
      else
        x
      end
    end
  end

  def map_with_dynamic_exception(list, exception_module) do
    Enum.map(list, fn item ->
      if item == :bad do
        raise exception_module, "Bad item"
      else
        item
      end
    end)
  end

  # ============================================================================
  # Exception Handling in Lambdas
  # ============================================================================

  def lambda_with_try_catch do
    fn x ->
      try do
        if x < 0 do
          raise ArgumentError, "Negative"
        else
          x * 2
        end
      rescue
        ArgumentError -> 0
      end
    end
  end

  def map_with_exception_recovery(list) do
    Enum.map(list, fn item ->
      try do
        if item == nil do
          raise CustomError, message: "nil item"
        else
          item * 2
        end
      rescue
        CustomError -> 0
      end
    end)
  end

  # ============================================================================
  # Partial Application with Exceptions
  # ============================================================================

  def partial_with_exception do
    validate = fn threshold ->
      fn value ->
        if value > threshold do
          raise DomainError, message: "Exceeds limit", domain: "threshold"
        else
          value
        end
      end
    end

    checker = validate.(100)
    checker.(150)
  end

  # ============================================================================
  # Exceptions in Anonymous Function Calls
  # ============================================================================

  def anonymous_call_with_exception do
    func = fn _x ->
      raise ArgumentError, "Always fails"
    end

    func.(42)
  end

  def anonymous_multi_clause_with_exceptions do
    func = fn
      {:ok, value} -> value
      {:error, _} -> raise CustomError, message: "Error tuple"
      nil -> raise ArgumentError, "nil value"
    end

    func.({:error, "something"})
  end

  # ============================================================================
  # Struct Updates with Custom Exceptions
  # ============================================================================

  def update_with_custom_exception(value) do
    if value < 0 do
      raise %CustomError{message: "Cannot update with negative"}
    else
      %{data: value}
    end
  end

  def struct_pattern_with_exception(%CustomError{} = error) do
    raise error
  end

  def struct_pattern_with_exception(value) do
    value
  end

  # ============================================================================
  # Import-based Raise (without Kernel prefix)
  # ============================================================================

  def raise_without_kernel_prefix do
    # raise is auto-imported from Kernel
    raise ArgumentError, "No Kernel prefix"
  end

  def lambda_raise_without_prefix do
    fn ->
      raise CustomError, message: "No prefix in lambda"
    end
  end

  # ============================================================================
  # Exception in Captured Functions
  # ============================================================================

  def capture_function_with_exception do
    captured = &raise_custom_error/0
    captured.()
  end

  def capture_lambda_with_exception do
    lambda = fn -> raise ArgumentError, "Captured lambda" end
    lambda.()
  end
end
