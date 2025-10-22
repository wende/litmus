defmodule Objective009VerificationTest do
  @moduledoc """
  Comprehensive verification test suite for Objective 009 Testing Criteria.

  This test file systematically verifies all requirements from:
  objective/009-captured-function-detection-fix.md

  Testing Criteria:
  1. Detection Coverage
  2. Error Reporting
  3. Integration
  """
  use ExUnit.Case

  # ============================================================================
  # 1. DETECTION COVERAGE
  # ============================================================================

  describe "Detection Coverage - Remote Captures (&Module.function/arity)" do
    test "detects impure remote captures" do
      assert_raise Litmus.Pure.ImpurityError, ~r/IO.puts\/1/, fn ->
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.each([1, 2, 3], &IO.puts/1)
        end
        """)
      end
    end

    test "allows pure remote captures" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map(["1", "2", "3"], &String.to_integer/1)
        end
        """)

      assert result == [1, 2, 3]
    end

    test "detects File operations in remote captures" do
      assert_raise Litmus.Pure.ImpurityError, ~r/File.read!\/1/, fn ->
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map(["a.txt", "b.txt"], &File.read!/1)
        end
        """)
      end
    end

    test "detects System operations in remote captures" do
      assert_raise Litmus.Pure.ImpurityError, fn ->
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map([:foo, :bar], &System.get_env/1)
        end
        """)
      end
    end
  end

  describe "Detection Coverage - Anonymous Captures (&(expr))" do
    test "detects effects in anonymous capture bodies" do
      assert_raise Litmus.Pure.ImpurityError, ~r/IO.puts\/1/, fn ->
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map([1, 2, 3], &(IO.puts(&1)))
        end
        """)
      end
    end

    test "allows pure expressions in anonymous captures" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map([1, 2, 3], &(&1 * 2))
        end
        """)

      assert result == [2, 4, 6]
    end

    test "detects nested function calls in anonymous captures" do
      assert_raise Litmus.Pure.ImpurityError, fn ->
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map([1, 2, 3], &(IO.inspect(&1 * 2)))
        end
        """)
      end
    end

    test "allows pure function calls in anonymous captures" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map([1, 2, 3], &(String.duplicate("x", &1)))
        end
        """)

      assert result == ["x", "xx", "xxx"]
    end
  end

  describe "Detection Coverage - Capture Combinations" do
    test "detects effects in pipeline with multiple captures" do
      assert_raise Litmus.Pure.ImpurityError, ~r/IO.puts\/1/, fn ->
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [1, 2, 3]
          |> Enum.map(&to_string/1)
          |> Enum.each(&IO.puts/1)
        end
        """)
      end
    end

    test "allows pure pipeline with multiple captures" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [1, 2, 3]
          |> Enum.map(&(&1 * 2))
          |> Enum.map(&to_string/1)
          |> Enum.join(",")
        end
        """)

      assert result == "2,4,6"
    end
  end

  # ============================================================================
  # 2. ERROR REPORTING
  # ============================================================================

  describe "Error Reporting - Clear Messages" do
    test "error message includes function name and arity" do
      error =
        assert_raise Litmus.Pure.ImpurityError, fn ->
          Code.eval_string("""
          import Litmus.Pure
          pure do
            Enum.each([1, 2, 3], &IO.puts/1)
          end
          """)
        end

      message = Exception.message(error)
      assert message =~ "IO.puts/1"
    end

    test "error message includes effect type description" do
      error =
        assert_raise Litmus.Pure.ImpurityError, fn ->
          Code.eval_string("""
          import Litmus.Pure
          pure do
            Enum.map([1, 2, 3], &File.read!/1)
          end
          """)
        end

      message = Exception.message(error)
      assert message =~ "File.read!/1"
      # Should indicate it's an I/O operation
      assert message =~ ~r/I\/O|operation|side effect/i
    end

    test "error message indicates purity requirement" do
      error =
        assert_raise Litmus.Pure.ImpurityError, fn ->
          Code.eval_string("""
          import Litmus.Pure
          pure do
            Enum.each([1], &IO.puts/1)
          end
          """)
        end

      message = Exception.message(error)
      assert message =~ ~r/pure|impure/i
    end
  end

  describe "Error Reporting - No False Positives" do
    test "does not flag pure Kernel functions in captures" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map([1, 2, 3], &to_string/1)
        end
        """)

      assert result == ["1", "2", "3"]
    end

    test "does not flag pure String functions in captures" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map(["hello", "world"], &String.upcase/1)
        end
        """)

      assert result == ["HELLO", "WORLD"]
    end

    test "does not flag pure Enum functions in captures" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [[1, 2], [3, 4, 5]]
          |> Enum.map(&Enum.sum/1)
        end
        """)

      assert result == [3, 12]
    end

    test "does not flag pure List functions in captures" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [[1, 2, 3], [4, 5]]
          |> Enum.map(&List.first/1)
        end
        """)

      assert result == [1, 4]
    end
  end

  # ============================================================================
  # 3. INTEGRATION
  # ============================================================================

  describe "Integration - Enum Functions" do
    test "works with Enum.map" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.map([1, 2, 3], &String.duplicate("x", &1))
        end
        """)

      assert result == ["x", "xx", "xxx"]
    end

    test "works with Enum.filter" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.filter([1, 2, 3, 4], &(rem(&1, 2) == 0))
        end
        """)

      assert result == [2, 4]
    end

    test "works with Enum.reduce" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.reduce([1, 2, 3], 0, &(&1 + &2))
        end
        """)

      assert result == 6
    end

    test "detects impurity in Enum.each" do
      assert_raise Litmus.Pure.ImpurityError, fn ->
        Code.eval_string("""
        import Litmus.Pure
        pure do
          Enum.each([1, 2, 3], &IO.puts/1)
        end
        """)
      end
    end
  end

  describe "Integration - Stream Functions" do
    test "works with Stream.map" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [1, 2, 3]
          |> Stream.map(&(&1 * 2))
          |> Enum.to_list()
        end
        """)

      assert result == [2, 4, 6]
    end

    test "works with Stream.filter" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [1, 2, 3, 4, 5]
          |> Stream.filter(&(rem(&1, 2) == 0))
          |> Enum.to_list()
        end
        """)

      assert result == [2, 4]
    end

    test "detects impurity in Stream operations" do
      assert_raise Litmus.Pure.ImpurityError, fn ->
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [1, 2, 3]
          |> Stream.map(&(IO.inspect(&1)))
          |> Enum.to_list()
        end
        """)
      end
    end
  end

  describe "Integration - Higher-Order Function Scenarios" do
    test "works with nested Enum operations" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [[1, 2], [3, 4]]
          |> Enum.map(&Enum.sum/1)
          |> Enum.map(&(&1 * 2))
        end
        """)

      assert result == [6, 14]
    end

    test "works with complex pure transformations" do
      {result, _} =
        Code.eval_string("""
        import Litmus.Pure
        pure do
          [1, 2, 3]
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 3))
          |> Enum.map(&to_string/1)
          |> Enum.join(",")
        end
        """)

      assert result == "4,6"
    end
  end

  describe "Integration - Performance" do
    test "no significant performance regression for simple captures" do
      # Baseline: compile and execute
      baseline_time =
        :timer.tc(fn ->
          for _ <- 1..100 do
            Code.eval_string("""
            import Litmus.Pure
            pure do
              Enum.map([1, 2, 3], &(&1 * 2))
            end
            """)
          end
        end)
        |> elem(0)

      # Should complete in reasonable time (< 5 seconds for 100 iterations)
      assert baseline_time < 5_000_000, "Performance regression detected"
    end
  end
end
