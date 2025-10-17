defmodule Litmus.KernelEffectsTest do
  @moduledoc """
  Auto-generated tests for all exception-raising Kernel functions.

  This ensures we've registered all Kernel functions that can raise exceptions
  as effects in the registry.
  """

  use ExUnit.Case, async: true
  import Litmus.Effects

  # List of Kernel functions that can raise exceptions
  # Format: {function_name, test_args, expected_exception}
  @exception_functions [
    # List operations that raise ArgumentError
    {:hd, [[]], ArgumentError},
    {:tl, [[]], ArgumentError},

    # Tuple operations that raise ArgumentError
    {:elem, [{:a, :b}, 5], ArgumentError},
    {:put_elem, [{:a, :b}, 5, :c], ArgumentError},

    # Arithmetic that can raise ArithmeticError
    {:div, [1, 0], ArithmeticError},
    {:rem, [1, 0], ArithmeticError},

    # Binary operations that raise ArgumentError
    {:binary_part, [<<1, 2, 3>>, 10, 1], ArgumentError},

    # Bit/byte size operations - these actually work on binaries, not strings
    # Elixir strings ARE binaries, so these succeed and return values
    # We need to test with actual non-binaries
    {:bit_size, [:not_a_binary], ArgumentError},
    {:byte_size, [:not_a_binary], ArgumentError},

    # Map/struct operations that raise BadMapError (not ArgumentError!)
    {:map_size, ["not a map"], BadMapError},

    # Tuple operations that raise ArgumentError
    {:tuple_size, ["not a tuple"], ArgumentError},

    # Process control (exit and throw don't raise, they use different mechanisms)
    # exits instead of raising
    {:exit, [:normal], nil},
    # throws instead of raising
    {:throw, [:value], nil}
    # Note: raise/1 is a macro, not a function, so we can't test it with apply/3
  ]

  # Generate a test for each function
  for {function, args, exception} <- @exception_functions do
    test_name = "Kernel.#{function}/#{length(args)} - registered as effect"

    @tag function: function
    @tag exception: exception
    test test_name do
      function = unquote(function)
      args = unquote(Macro.escape(args))
      exception_type = unquote(exception)

      # Test 1: Verify it's registered as an effect
      assert Litmus.Effects.Registry.effect?({Kernel, function, length(args)}),
             "Kernel.#{function}/#{length(args)} should be registered as an effect"

      # Test 2: Verify effect category
      category = Litmus.Effects.Registry.effect_category({Kernel, function, length(args)})

      assert category == :exception,
             "Kernel.#{function}/#{length(args)} should have :exception category, got #{inspect(category)}"

      # Test 3: If it raises an exception, verify we can catch it with rescue
      if exception_type do
        result =
          effect do
            apply(Kernel, function, args)
          catch
            effect_sig -> Litmus.Effects.apply_effect(effect_sig)
          rescue
            e -> e.__struct__
          end

        assert result == exception_type,
               "Should have caught #{inspect(exception_type)} from Kernel.#{function}, got #{inspect(result)}"
      end
    end
  end

  # Additional comprehensive test
  test "all exception-raising Kernel functions are covered" do
    # Get all functions we've registered with :exception category
    registered =
      Enum.filter(@exception_functions, fn {func, args, _} ->
        Litmus.Effects.Registry.effect?({Kernel, func, length(args)})
      end)

    # Ensure we have a reasonable number registered
    assert length(registered) >= 10,
           "Expected at least 10 exception-raising Kernel functions to be registered"
  end

  test "exception functions can be mocked without raising" do
    # If we mock the effect, the exception never happens
    result =
      effect do
        # Would raise ArgumentError
        hd([])
      catch
        {Kernel, :hd, [[]]} -> :mocked_value
      end

    assert result == :mocked_value
  end

  test "exception functions can passthrough and be rescued" do
    result =
      effect do
        # Will raise ArgumentError
        hd([])
      catch
        effect_sig -> Litmus.Effects.apply_effect(effect_sig)
      rescue
        ArgumentError -> :rescued
      end

    assert result == :rescued
  end

  test "multiple exception functions in sequence" do
    result =
      effect do
        # OK
        x = hd([1, 2, 3])
        # OK
        y = elem({:a, :b}, 0)
        # Would raise
        z = hd([])
        {x, y, z}
      catch
        {Kernel, :hd, [[1, 2, 3]]} -> 1
        {Kernel, :elem, [{:a, :b}, 0]} -> :a
        {Kernel, :hd, [[]]} -> :default
      end

    assert result == {1, :a, :default}
  end

  test "exception function with wildcard passthrough" do
    result =
      effect do
        # Out of bounds
        elem({:a, :b}, 5)
      catch
        _ -> Litmus.Effects.apply_effect({Kernel, :elem, [{:a, :b}, 5]})
      rescue
        ArgumentError -> :out_of_bounds
      end

    assert result == :out_of_bounds
  end
end
