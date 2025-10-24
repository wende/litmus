defmodule Support.EdgeCasesTest do
  @moduledoc """
  Test cases covering edge cases and features discovered during development.

  These tests validate:
  - Lambda-dependent function classification
  - Block expressions with multiple statements
  - Exception effect handling
  - Module alias handling (compile-time constructs)
  - Cross-module effect propagation
  - Mixed effects in sequential blocks
  - Unknown effects (apply)
  """

  # ============================================================================
  # Lambda-Dependent Functions (Higher-Order Functions)
  # ============================================================================

  @doc """
  A higher-order function that takes a function parameter and calls it.
  Should be classified as lambda-dependent (l), not unknown (u).
  """
  def higher_order_simple(func) do
    func.(10)
  end

  @doc """
  Higher-order function with two function parameters.
  Should be classified as lambda-dependent.
  """
  def higher_order_two_funcs(f, g) do
    x = f.(5)
    g.(x)
  end

  @doc """
  Higher-order function that passes arguments to the lambda.
  Should be classified as lambda-dependent.
  """
  def higher_order_with_args(func, x, y) do
    func.(x, y)
  end

  @doc """
  Calling a higher-order function with a pure lambda.
  The overall effect should be pure, not lambda-dependent.
  """
  def call_higher_order_with_pure_lambda do
    higher_order_simple(fn x -> x * 2 end)
  end

  @doc """
  Calling a higher-order function with an effectful lambda.
  The overall effect should be effectful (s), not lambda-dependent.
  """
  def call_higher_order_with_effectful_lambda do
    higher_order_simple(fn x ->
      IO.puts("Processing: #{x}")
      x * 2
    end)
  end

  @doc """
  Higher-order function that also has concrete effects.
  Should combine lambda-dependent with side effects.
  """
  def higher_order_mixed_effects(func) do
    IO.puts("Before calling function")
    result = func.(10)
    IO.puts("After calling function")
    result
  end

  # ============================================================================
  # Block Expressions with Multiple Statements
  # ============================================================================

  @doc """
  Block with multiple pure statements.
  Should be classified as pure (p).
  """
  def block_pure_statements(x, y) do
    a = x + 1
    b = y + 2
    a + b
  end

  @doc """
  Block with IO and File operations.
  Should be classified as effectful (s).
  Was previously incorrectly classified as unknown due to block pattern matching order.
  """
  def log_and_save(message, path) do
    IO.puts(message)
    File.write!(path, message)
  end

  @doc """
  Block with mixed pure and effectful statements.
  Should be classified as effectful (s).
  """
  def block_mixed_effects(x) do
    y = x * 2
    IO.puts("Result: #{y}")
    z = y + 10
    z
  end

  @doc """
  Nested blocks with effects.
  Should propagate effects correctly.
  """
  def nested_blocks(flag) do
    if flag do
      x = 5
      IO.puts("x is #{x}")
      x
    else
      y = 10
      File.write!("output.txt", "y is #{y}")
      y
    end
  end

  # ============================================================================
  # Exception Effects
  # ============================================================================

  @doc """
  Function that explicitly raises an exception.
  Should be classified as exception (e), not unknown.
  Was previously unknown because ArgumentError (module alias) produced effect variables.
  """
  def exception_explicit_raise do
    raise ArgumentError, "Something went wrong"
  end

  @doc """
  Function with multiple exception types.
  Should be classified as exception.
  """
  def exception_multiple_types(type) do
    case type do
      :arg -> raise ArgumentError
      :runtime -> raise RuntimeError
      :custom -> raise "Custom error"
    end
  end

  @doc """
  Function that may raise from stdlib function.
  Should be classified as exception.
  """
  def exception_from_stdlib(list) do
    # Can raise ArgumentError on empty list
    hd(list)
  end

  @doc """
  Division that can raise ArithmeticError.
  Should be classified as exception.
  """
  def exception_division(x, y) do
    div(x, y)
  end

  @doc """
  Exception wrapped in a block.
  Should still be classified as exception.
  """
  def exception_in_block do
    # Intentional: testing exception inference (using apply to avoid compile warning)
    x = 10
    y = 0
    apply(Kernel, :div, [x, y])
  end

  # ============================================================================
  # Module Aliases (Compile-Time Constructs)
  # ============================================================================

  @doc """
  Using module aliases in various contexts.
  Module aliases should not produce effect variables.
  """
  def use_module_aliases do
    _error_type = ArgumentError
    _string_type = String
    _file_type = File
    :ok
  end

  @doc """
  Pattern matching with module aliases.
  Should be pure.
  """
  def pattern_match_aliases(value) do
    case value do
      %ArgumentError{} -> :error
      %RuntimeError{} -> :runtime
      _ -> :unknown
    end
  end

  # ============================================================================
  # Unknown Effects (apply)
  # ============================================================================

  @doc """
  Using Kernel.apply with unknown function.
  Should be classified as unknown (u), not effectful (s).
  """
  def unknown_apply_kernel do
    apply(IO, :puts, ["Hello"])
  end

  @doc """
  Using apply/3 with unknown function.
  Should be classified as unknown.
  """
  def unknown_apply_3(module, func, args) do
    apply(module, func, args)
  end

  @doc """
  Using apply with lambda.
  Should be classified as unknown.
  """
  def unknown_apply_lambda(func, arg) do
    apply(func, [arg])
  end

  # ============================================================================
  # Variables with Module Context
  # ============================================================================

  @doc """
  Variables with module context (not nil).
  Was previously not recognized as variables, causing issues.
  """
  def variables_with_context(x, y) do
    z = x + y
    result = z * 2
    result
  end

  @doc """
  Variables in pattern matching.
  Should handle variables with module context correctly.
  """
  def variables_in_pattern(tuple) do
    {x, y} = tuple
    x + y
  end

  # ============================================================================
  # Cross-Module Function Calls
  # ============================================================================

  defmodule TestHelper do
    @moduledoc """
    This module is used for testing cross-module effects.
    """

    def pure_helper(x), do: x * 2
    def effectful_helper(x), do: IO.puts("Value: #{x}")
    def exception_helper(x), do: hd(x)
    def lambda_helper(func), do: func.(10)
  end

  @doc """
  Calling pure function from another module.
  Should be classified as pure.
  """
  def cross_module_pure(x) do
    TestHelper.pure_helper(x)
  end

  @doc """
  Calling effectful function from another module.
  Should be classified as effectful.
  """
  def cross_module_effectful(x) do
    TestHelper.effectful_helper(x)
  end

  @doc """
  Calling exception function from another module.
  Should be classified as exception.
  """
  def cross_module_exception(x) do
    TestHelper.exception_helper(x)
  end

  @doc """
  Calling lambda-dependent function from another module with pure lambda.
  Should be classified as pure.
  """
  def cross_module_lambda_pure do
    TestHelper.lambda_helper(fn x -> x * 2 end)
  end

  @doc """
  Calling lambda-dependent function from another module with effectful lambda.
  Should be classified as effectful.
  """
  def cross_module_lambda_effectful do
    TestHelper.lambda_helper(fn x ->
      IO.puts("Processing: #{x}")
      x * 2
    end)
  end

  # ============================================================================
  # String Interpolation (Binary Construction)
  # ============================================================================

  @doc """
  String interpolation is pure.
  Should be classified as pure.
  """
  def string_interpolation(name, age) do
    "Name: #{name}, Age: #{age}"
  end

  @doc """
  String interpolation with effectful expression inside.
  Should be classified as effectful.
  """
  def string_interpolation_with_effects(x) do
    "Result: #{IO.inspect(x)}"
  end

  @doc """
  Multiple string interpolations.
  Should be classified as pure.
  """
  def multiple_interpolations(a, b, c) do
    first = "a: #{a}"
    second = "b: #{b}"
    third = "c: #{c}"
    "#{first}, #{second}, #{third}"
  end

  # ============================================================================
  # If/Case Expressions
  # ============================================================================

  @doc """
  If expression with pure branches.
  Should be classified as pure.
  """
  def if_pure(flag, x) do
    if flag do
      x * 2
    else
      x + 1
    end
  end

  @doc """
  If expression with effectful then branch.
  Should be classified as effectful.
  """
  def if_effectful_then(flag) do
    if flag do
      IO.puts("True branch")
      :ok
    else
      :ok
    end
  end

  @doc """
  If expression with effectful else branch.
  Should be classified as effectful.
  """
  def if_effectful_else(flag) do
    if flag do
      :ok
    else
      File.write!("log.txt", "False branch")
      :ok
    end
  end

  @doc """
  Case expression with pure patterns.
  Should be classified as pure.
  """
  def case_pure(value) do
    case value do
      {:ok, x} -> x
      {:error, _} -> 0
      _ -> -1
    end
  end

  @doc """
  Case expression with mixed effects.
  Should be classified as effectful (union of all branches).
  """
  def case_mixed_effects(value) do
    case value do
      {:ok, data} ->
        File.write!("output.txt", data)
        :success

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        :failure

      _ ->
        :unknown
    end
  end

  # ============================================================================
  # Pipe Operator Edge Cases
  # ============================================================================

  @doc """
  Pipe with all pure functions.
  Should be classified as pure.
  """
  def pipe_all_pure(x) do
    x
    |> String.upcase()
    |> String.trim()
    |> String.reverse()
  end

  @doc """
  Pipe with one effectful function in the middle.
  Should be classified as effectful.
  """
  def pipe_with_effect_in_middle(x) do
    x
    |> String.upcase()
    |> IO.inspect(label: "Uppercased")
    |> String.trim()
  end

  @doc """
  Pipe with lambda-dependent function and pure lambda.
  Should be classified as pure.
  """
  def pipe_with_lambda_dependent(list) do
    list
    |> Enum.map(fn x -> x * 2 end)
    |> Enum.sum()
  end

  @doc """
  Pipe with exception-throwing function.
  Should be classified as exception.
  """
  def pipe_with_exception(list) do
    list
    |> Enum.reverse()
    |> hd()
  end

  # ============================================================================
  # Dependent Effects (Context-Dependent)
  # ============================================================================

  @doc """
  Function that reads from process dictionary.
  Should be classified as dependent (d).
  """
  def dependent_process_get(key) do
    Process.get(key)
  end

  @doc """
  Function that reads from ETS.
  Should be classified as dependent (d) or effectful (s) depending on categorization.
  """
  def dependent_ets_lookup(table, key) do
    :ets.lookup(table, key)
  end

  @doc """
  Function that gets system time.
  Should be classified as dependent (d).
  """
  def dependent_system_time do
    System.system_time()
  end

  # ============================================================================
  # Complex Nested Scenarios
  # ============================================================================

  @doc """
  Nested higher-order functions with lambda propagation.
  Should correctly propagate effects through multiple levels.
  """
  def nested_higher_order_complex(data) do
    Enum.map(data, fn outer_item ->
      Enum.filter(outer_item, fn inner_item ->
        Enum.reduce(inner_item, 0, fn x, acc -> x + acc end)
        |> (&(&1 > 10)).()
      end)
    end)
  end

  @doc """
  Higher-order with effects at multiple levels.
  Should combine all effects correctly.
  """
  def nested_with_effects_at_all_levels(data) do
    IO.puts("Starting processing")

    result =
      Enum.map(data, fn item ->
        IO.puts("Processing item: #{inspect(item)}")

        Enum.filter(item, fn x ->
          File.write!("debug.log", "Checking: #{x}\n", [:append])
          x > 0
        end)
      end)

    IO.puts("Done processing")
    result
  end

  @doc """
  Exception in nested context with blocks.
  Should propagate exception effect to top level.
  """
  def nested_exception_in_blocks(list_of_lists) do
    Enum.map(list_of_lists, fn sublist ->
      # Can raise
      x = hd(sublist)
      y = x * 2
      IO.puts("Doubled: #{y}")
      y
    end)
  end
end
