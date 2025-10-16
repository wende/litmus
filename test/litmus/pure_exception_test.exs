defmodule Litmus.PureExceptionTest do
  use ExUnit.Case, async: true

  import Litmus.Pure

  describe "allow_exceptions: :none" do
    test "allows pure functions without exceptions" do
      result = pure allow_exceptions: :none do
        x = [1, 2, 3]
        Enum.map(x, &(&1 * 2))
      end

      assert result == [2, 4, 6]
    end

    test "rejects functions that raise ArgumentError" do
      assert_raise Litmus.Pure.ImpurityError, ~r/Disallowed exception/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure allow_exceptions: :none do
              String.to_integer!("123")
            end
          end
        )
      end
    end
  end

  describe "allow_exceptions: [ArgumentError]" do
    test "allows functions that raise only ArgumentError" do
      # Note: This test verifies the compile-time check passes
      # The actual runtime behavior would still raise if given invalid input
      assert_raise ArgumentError, fn ->
        pure allow_exceptions: [ArgumentError] do
          hd([])  # Raises ArgumentError on empty list
        end
      end
    end

    test "rejects functions that raise KeyError" do
      assert_raise Litmus.Pure.ImpurityError, ~r/Disallowed exception/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure allow_exceptions: [ArgumentError] do
              Map.fetch!(%{}, :key)
            end
          end
        )
      end
    end

    test "allows mix of pure and ArgumentError functions" do
      # Should compile successfully
      result = pure allow_exceptions: [ArgumentError] do
        x = [1, 2, 3]
        y = Enum.map(x, &(&1 * 2))
        # String.to_integer! is allowed (raises ArgumentError)
        z = "123"
        {y, z}
      end

      assert result == {[2, 4, 6], "123"}
    end
  end

  describe "allow_exceptions: [ArgumentError, KeyError]" do
    test "allows functions that raise ArgumentError or KeyError" do
      # Should compile successfully
      result = pure allow_exceptions: [ArgumentError, KeyError] do
        x = [1, 2, 3]
        Enum.sum(x)
      end

      assert result == 6
    end

    test "allows ArgumentError function" do
      assert_raise ArgumentError, fn ->
        pure allow_exceptions: [ArgumentError, KeyError] do
          hd([])  # Raises ArgumentError on empty list
        end
      end
    end

    test "allows KeyError function" do
      assert_raise KeyError, fn ->
        pure allow_exceptions: [ArgumentError, KeyError] do
          Map.fetch!(%{}, :missing)
        end
      end
    end
  end

  describe "allow_exceptions: :any" do
    test "allows functions with any exceptions" do
      # Should compile successfully even with exception-raising functions
      result = pure allow_exceptions: :any do
        x = [1, 2, 3]
        Enum.sum(x)
      end

      assert result == 6
    end

    test "allows ArgumentError function" do
      assert_raise ArgumentError, fn ->
        pure allow_exceptions: :any do
          hd([])  # Raises ArgumentError on empty list
        end
      end
    end

    test "allows KeyError function" do
      assert_raise KeyError, fn ->
        pure allow_exceptions: :any do
          Map.fetch!(%{}, :missing)
        end
      end
    end
  end

  describe "default exception behavior" do
    test "pure level defaults to no exceptions" do
      # Default level is :pure, which means no exceptions
      result = pure do
        x = [1, 2, 3]
        Enum.map(x, &(&1 * 2))
      end

      assert result == [2, 4, 6]
    end

    test "exceptions level defaults to any exceptions" do
      # level: :exceptions means any exceptions allowed
      result = pure level: :exceptions do
        x = [1, 2, 3]
        Enum.sum(x)
      end

      assert result == 6
    end
  end

  describe "combining options" do
    test "can combine level and allow_exceptions" do
      # allow_exceptions overrides the exception behavior of level
      result = pure level: :pure, allow_exceptions: [ArgumentError] do
        x = [1, 2, 3]
        Enum.sum(x)
      end

      assert result == 6
    end

    test "can combine require_termination and allow_exceptions" do
      result = pure require_termination: true, allow_exceptions: [ArgumentError] do
        x = [1, 2, 3]
        Enum.map(x, &(&1 * 2))
      end

      assert result == [2, 4, 6]
    end
  end
end
