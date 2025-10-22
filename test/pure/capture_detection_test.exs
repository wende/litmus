defmodule CaptureDetectionTest do
  @moduledoc """
  Comprehensive test suite for captured function detection in pure blocks.
  Tests the fix for Objective 009 - ensuring captured functions are properly
  analyzed for purity and side effects.
  """
  use ExUnit.Case

  test "detects captured IO functions with proper error message" do
    assert_raise Litmus.Pure.ImpurityError, ~r/IO.puts\/1.*I\/O operation/, fn ->
      Code.eval_string("""
      import Litmus.Pure
      pure do
        Enum.each([1, 2, 3], &IO.puts/1)
      end
      """)
    end
  end

  test "allows captured pure functions" do
    {result, _binding} =
      Code.eval_string("""
      import Litmus.Pure
      pure do
        Enum.map(["1", "2", "3"], &String.to_integer/1)
      end
      """)

    assert result == [1, 2, 3]
  end

  test "detects nested captured effects" do
    assert_raise Litmus.Pure.ImpurityError, fn ->
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

  test "detects anonymous captures with effects" do
    assert_raise Litmus.Pure.ImpurityError, fn ->
      Code.eval_string("""
      import Litmus.Pure
      pure do
        Enum.map([1, 2, 3], &(IO.puts(&1)))
      end
      """)
    end
  end

  test "allows anonymous captures with pure functions" do
    {result, _binding} =
      Code.eval_string("""
      import Litmus.Pure
      pure do
        Enum.map([1, 2, 3], &(&1 * 2))
      end
      """)

    assert result == [2, 4, 6]
  end

  test "detects captured File functions with proper error message" do
    assert_raise Litmus.Pure.ImpurityError, ~r/File.read!\/1.*I\/O operation/, fn ->
      Code.eval_string("""
      import Litmus.Pure
      pure do
        Enum.each(["file1", "file2"], &File.read!/1)
      end
      """)
    end
  end

  test "allows captured Enum functions" do
    {result, _binding} =
      Code.eval_string("""
      import Litmus.Pure
      pure do
        [[1, 2], [3, 4]]
        |> Enum.map(&Enum.sum/1)
      end
      """)

    assert result == [3, 7]
  end
end
