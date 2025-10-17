defmodule Litmus.ExceptionPropagationTest do
  use ExUnit.Case, async: true

  alias ExceptionTestModules.PropagateExample
  alias ExceptionTestModules.ThrowPropagateExample
  alias ExceptionTestModules.MultipleCalleesExample
  alias ExceptionTestModules.DeepPropagateExample
  alias ExceptionTestModules.MutualRecursionExample
  alias ExceptionTestModules.UnknownExceptionExample
  alias ExceptionTestModules.PureExample

  describe "exception propagation through call graph" do
    test "propagates exceptions from callees to callers" do
      {:ok, results} = Litmus.analyze_exceptions(PropagateExample)

      # All three levels should show ArgumentError from elem/2 with out of bounds index
      assert Litmus.can_raise?(results, {PropagateExample, :level1, 1}, ArgumentError)
      assert Litmus.can_raise?(results, {PropagateExample, :level2, 1}, ArgumentError)
      assert Litmus.can_raise?(results, {PropagateExample, :level3, 1}, ArgumentError)
    end

    test "propagates throw through call chain" do
      {:ok, results} = Litmus.analyze_exceptions(ThrowPropagateExample)

      # Both functions should show non_errors (can throw)
      assert Litmus.can_throw_or_exit?(results, {ThrowPropagateExample, :caller, 1})
      assert Litmus.can_throw_or_exit?(results, {ThrowPropagateExample, :thrower, 1})
    end

    test "merges exceptions from multiple callees" do
      {:ok, results} = Litmus.analyze_exceptions(MultipleCalleesExample)

      # Should have both ArgumentError and KeyError
      assert Litmus.can_raise?(results, {MultipleCalleesExample, :caller, 2}, ArgumentError)
      assert Litmus.can_raise?(results, {MultipleCalleesExample, :caller, 2}, KeyError)
    end

    test "deep propagation through multiple levels" do
      {:ok, results} = Litmus.analyze_exceptions(DeepPropagateExample)

      # Exception should propagate all the way up (ArgumentError from elem/2 out of bounds)
      assert Litmus.can_raise?(results, {DeepPropagateExample, :top, 1}, ArgumentError)
      assert Litmus.can_raise?(results, {DeepPropagateExample, :middle, 1}, ArgumentError)
      assert Litmus.can_raise?(results, {DeepPropagateExample, :bottom, 1}, ArgumentError)
      assert Litmus.can_raise?(results, {DeepPropagateExample, :deeper, 1}, ArgumentError)
    end

    test "handles mutual recursion" do
      {:ok, results} = Litmus.analyze_exceptions(MutualRecursionExample)

      # Neither function raises exceptions
      refute Litmus.can_raise?(results, {MutualRecursionExample, :ping, 1}, ArgumentError)
      refute Litmus.can_raise?(results, {MutualRecursionExample, :pong, 1}, ArgumentError)
      refute Litmus.can_throw_or_exit?(results, {MutualRecursionExample, :ping, 1})
      refute Litmus.can_throw_or_exit?(results, {MutualRecursionExample, :pong, 1})
    end

    test "propagates unknown exceptions" do
      {:ok, results} = Litmus.analyze_exceptions(UnknownExceptionExample)

      # Both should have :dynamic errors since we can't determine the exception type
      info1 = results[{UnknownExceptionExample, :caller, 1}]
      info2 = results[{UnknownExceptionExample, :raiser, 1}]

      assert info1.errors == :dynamic
      assert info2.errors == :dynamic
    end

    test "pure function has no exceptions" do
      {:ok, results} = Litmus.analyze_exceptions(PureExample)

      # All functions should be pure (no exceptions)
      {:ok, info1} = Litmus.get_exceptions(results, {PureExample, :pure_add, 2})
      {:ok, info2} = Litmus.get_exceptions(results, {PureExample, :pure_mul, 2})
      {:ok, info3} = Litmus.get_exceptions(results, {PureExample, :combined, 2})

      assert Litmus.Exceptions.pure?(info1)
      assert Litmus.Exceptions.pure?(info2)
      assert Litmus.Exceptions.pure?(info3)
    end
  end
end
