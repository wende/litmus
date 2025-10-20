defmodule Support.RegressionTest do
  @moduledoc """
  Regression tests for bugs discovered and fixed during development.

  Each test is documented with:
  - The bug that was discovered
  - The root cause
  - The fix that was applied
  - Expected behavior
  """

  # ============================================================================
  # Bug #1: Higher-Order Functions Marked as Unknown Instead of Lambda-Dependent
  # ============================================================================

  @doc """
  BUG: Higher-order functions were being marked as unknown (u) instead of lambda-dependent (l).

  ROOT CAUSE: When analyzing a function like `def foo(func), do: func.(10)`, the bidirectional
  inference system creates a fresh effect variable for the call to the unknown function parameter.
  These effect variables were being converted to :u (unknown) without checking if the function
  should be classified as lambda-dependent.

  FIX: Added `classify_effect/2` in `ast_walker.ex` that post-processes effects after function
  body analysis. If a function has function-typed parameters and its effect contains only variables
  (no concrete effects), it's marked as :l (lambda-dependent).

  EXPECTED: This function should be classified as lambda-dependent (l).
  """
  def bug_1_higher_order_function(func) do
    func.(10)
  end

  @doc """
  EXPECTED: Calling a lambda-dependent function with a pure lambda should be pure (p).
  """
  def bug_1_call_with_pure_lambda do
    bug_1_higher_order_function(fn x -> x * 2 end)
  end

  @doc """
  EXPECTED: Calling a lambda-dependent function with an effectful lambda should be effectful (s).
  """
  def bug_1_call_with_effectful_lambda do
    bug_1_higher_order_function(fn x ->
      IO.puts("Value: #{x}")
      x * 2
    end)
  end

  # ============================================================================
  # Bug #2: Block Expressions Marked as Unknown
  # ============================================================================

  @doc """
  BUG: Multi-statement blocks were being marked as unknown instead of combining effects.

  ROOT CAUSE: The `{:__block__, _, expressions}` pattern in `infer_type/4` was being matched
  by the local call pattern `{func, meta, args}` BEFORE reaching the block handler, because
  `__block__` is an atom and the third element is a list (which matches the local call pattern).

  FIX: Moved the `__block__` pattern BEFORE the local call pattern in `bidirectional.ex`.

  EXPECTED: This function should be classified as effectful (s), not unknown (u).
  """
  def bug_2_log_and_save(message, path) do
    IO.puts(message)
    File.write!(path, message)
  end

  @doc """
  EXPECTED: Pure multi-statement block should be pure (p).
  """
  def bug_2_pure_block(x, y) do
    a = x + 1
    b = y + 2
    a + b
  end

  @doc """
  EXPECTED: Block with exception should be exception (e).
  """
  def bug_2_exception_block(list) do
    x = List.first(list)
    # Can raise
    y = hd(list)
    x + y
  end

  # ============================================================================
  # Bug #3: Variables Not Recognized
  # ============================================================================

  @doc """
  BUG: Variables were not being recognized correctly, contributing to Bug #2.

  ROOT CAUSE: The variable pattern was `{name, _, nil}` but variables can have module contexts
  like `{name, _, Elixir}` or `{name, _, SomeModule}`.

  FIX: Changed pattern to `{name, _, context_atom} when is_atom(name) and is_atom(context_atom)`.

  EXPECTED: This function should be pure (p).
  """
  def bug_3_variables_with_context(x, y) do
    z = x + y
    result = z * 2
    result
  end

  # ============================================================================
  # Bug #4: Exception Functions Marked as Unknown
  # ============================================================================

  @doc """
  BUG: Functions that raise exceptions were marked as unknown (u) instead of exception (e).

  ROOT CAUSE: The `ArgumentError` module reference is an `{:__aliases__, _, [:ArgumentError]}`
  AST node, which was producing an effect variable. This variable combined with `raise`'s
  `:exn` effect resulted in an unknown effect.

  FIX: Added pattern to handle `{:__aliases__, _, _parts}` as compile-time constructs with
  no effects (they produce atoms at compile time).

  EXPECTED: This function should be classified as exception (e), not unknown (u).
  """
  def bug_4_exception_with_module_alias do
    raise ArgumentError, "Something went wrong"
  end

  @doc """
  EXPECTED: Exception with different error types should still be exception (e).
  """
  def bug_4_exception_runtime_error do
    raise RuntimeError, "Runtime error"
  end

  # ============================================================================
  # Bug #5: Apply Marked as Effectful Instead of Unknown
  # ============================================================================

  @doc """
  BUG: `Kernel.apply/2` and `apply/3` were marked as effectful (s) instead of unknown (u).

  ROOT CAUSE: These functions were categorized as side effects in the registry because their
  actual effects depend on the function being called at runtime.

  FIX: Changed `Kernel.apply/2` and `apply/3` from "s" to "u" in `.effects.json`.

  EXPECTED: This function should be classified as unknown (u), not effectful (s).
  """
  def bug_5_unknown_apply do
    apply(IO, :puts, ["Hello"])
  end

  @doc """
  EXPECTED: apply/3 should also be unknown (u).
  """
  def bug_5_unknown_apply_3(module, func, args) do
    apply(module, func, args)
  end

  # ============================================================================
  # Bug #6: Cross-Module Lambda-Dependent Functions Show Wrong Indicator
  # ============================================================================

  @doc """
  BUG: Cross-module calls to lambda-dependent functions showed '?' instead of 'λ'.

  ROOT CAUSE: The runtime cache stores compact effects (atoms/tuples like :p, :l, {:e, [:exn]})
  but `effect_type/1` in the registry expected JSON string format ("p", "l", {"e": ["exn"]}).
  When looking up cached effects, they weren't being handled correctly.

  FIX: Updated `effect_type/1` to return cached compact effects directly when they're atoms/tuples,
  and updated `Effects.from_mfa/1` to handle {:e, _types} tuple format.

  EXPECTED: Cross-module calls to lambda-dependent functions should show 'λ' indicator.
  """
  defmodule Bug6Helper do
    def lambda_dependent_func(func) do
      func.(42)
    end
  end

  def bug_6_call_lambda_dependent do
    Bug6Helper.lambda_dependent_func(fn x -> x * 2 end)
  end

  # ============================================================================
  # Bug #7: Test Support Modules Not Included in Cache
  # ============================================================================

  @doc """
  BUG: Modules in test/support were not being analyzed in dev environment.

  ROOT CAUSE: `discover_app_files/0` in effect.ex only included test/support when
  `Mix.env() == :test`, but we often run analysis in dev environment.

  FIX: Changed condition from `if Mix.env() == :test` to `if File.dir?("test/support")`
  to always include test/support if it exists.

  EXPECTED: Cross-module calls to test support modules should work correctly.
  """

  # This bug is more about infrastructure, but we can still document it
  # The fix ensures that modules like SampleModule are always in the cache

  # ============================================================================
  # Bug #8: Enum.reduce Marked as Unknown Instead of Lambda-Dependent
  # ============================================================================

  @doc """
  BUG: `Enum.reduce/3` was marked as unknown (u) instead of lambda-dependent (l).

  ROOT CAUSE: `Enum.reduce/3` was categorized as "u" in the registry, but it should be "l"
  because its effects depend entirely on the lambda passed to it.

  FIX: Changed `Enum.reduce/3` from "u" to "l" in `.effects.json`.

  EXPECTED: Calling Enum.reduce with a pure lambda should be pure (p).
  """
  def bug_8_reduce_with_pure_lambda(list) do
    Enum.reduce(list, 0, fn x, acc -> x + acc end)
  end

  @doc """
  EXPECTED: Calling Enum.reduce with an effectful lambda should be effectful (s).
  """
  def bug_8_reduce_with_effectful_lambda(list) do
    Enum.reduce(list, 0, fn x, acc ->
      IO.puts("Adding: #{x}")
      x + acc
    end)
  end

  # ============================================================================
  # Integration Tests - Multiple Bugs Combined
  # ============================================================================

  @doc """
  Complex scenario combining multiple fixes:
  - Block expressions (Bug #2)
  - Variables with context (Bug #3)
  - Exception with module alias (Bug #4)
  - Higher-order functions (Bug #1)

  EXPECTED: Should be classified as exception (e).
  """
  def integration_test_1(list) do
    x = 10
    y = 20
    _z = x + y

    if Enum.empty?(list) do
      raise ArgumentError, "List cannot be empty"
    else
      hd(list)
    end
  end

  @doc """
  Complex scenario with higher-order and blocks:
  - Higher-order function (Bug #1)
  - Block expressions (Bug #2)
  - Lambda-dependent (Bug #6)

  EXPECTED: Should be classified as lambda-dependent (l).
  """
  def integration_test_2(func, x) do
    y = x * 2
    z = y + 10
    result = func.(z)
    result + 1
  end

  @doc """
  Calling integration_test_2 with pure lambda.

  EXPECTED: Should be classified as pure (p).
  """
  def integration_test_2_pure do
    integration_test_2(fn x -> x * 2 end, 10)
  end

  @doc """
  Calling integration_test_2 with effectful lambda.

  EXPECTED: Should be classified as effectful (s).
  """
  def integration_test_2_effectful do
    integration_test_2(
      fn x ->
        IO.puts("Processing: #{x}")
        x * 2
      end,
      10
    )
  end

  @doc """
  All bugs combined in one complex function:
  - Blocks (Bug #2)
  - Variables (Bug #3)
  - Exceptions (Bug #4)
  - Higher-order (Bug #1)
  - Enum.reduce (Bug #8)

  EXPECTED: Should be classified as exception (e) because of hd/1.
  """
  def integration_test_all_bugs(list_of_lists) do
    # Block with variables
    _x = 10
    _y = 20

    # Higher-order with reduce (Bug #1, #8)
    result =
      Enum.reduce(list_of_lists, 0, fn sublist, acc ->
        # Exception (Bug #4)
        first = hd(sublist)
        acc + first
      end)

    # Exception with module alias (Bug #4)
    if result < 0 do
      raise ArgumentError, "Result cannot be negative"
    end

    result
  end
end
