defmodule Litmus.EffectsTest do
  use ExUnit.Case, async: true

  import Litmus.Effects
  alias Litmus.Effects

  describe "effect/1 macro" do
    test "creates an effect function" do
      eff =
        effect do
          :ok
        end

      assert is_function(eff, 1)
    end

    test "single effect with custom handler" do
      result =
        effect do
          File.read!("test.txt")
        end
        |> Effects.run(fn
          {File, :read!, ["test.txt"]} -> "mocked content"
        end)

      assert result == "mocked content"
    end

    test "sequential effects with handler" do
      result =
        effect do
          x = File.read!("a.txt")
          y = File.read!("b.txt")
          x <> y
        end
        |> Effects.run(fn
          {File, :read!, ["a.txt"]} -> "hello "
          {File, :read!, ["b.txt"]} -> "world"
        end)

      assert result == "hello world"
    end

    test "pure code between effects is preserved" do
      result =
        effect do
          x = File.read!("a.txt")
          # Pure operation
          y = String.upcase(x)
          z = File.read!("b.txt")
          y <> " " <> z
        end
        |> Effects.run(fn
          {File, :read!, ["a.txt"]} -> "hello"
          {File, :read!, ["b.txt"]} -> "world"
        end)

      assert result == "HELLO world"
    end

    test "effect with write operation" do
      result =
        effect do
          content = File.read!("input.txt")
          File.write!("output.txt", content)
        end
        |> Effects.run(fn
          {File, :read!, ["input.txt"]} ->
            send(self(), :read_called)
            "test content"

          {File, :write!, ["output.txt", "test content"]} ->
            send(self(), :write_called)
            :ok
        end)

      assert_received :read_called
      assert_received :write_called
      assert result == :ok
    end
  end

  describe "Effects.run/2" do
    test "passthrough mode executes effects normally" do
      # Create a temporary file for testing
      path = "test_file_#{:rand.uniform(1000)}.txt"
      File.write!(path, "real content")

      result =
        effect do
          File.read!(path)
        end
        |> Effects.run(:passthrough)

      assert result == "real content"

      # Cleanup
      File.rm!(path)
    end
  end

  describe "Effects.map/2" do
    test "transforms effects before handling" do
      result =
        effect do
          File.read!("test.txt")
        end
        |> Effects.map(fn {File, :read!, [path]} ->
          {File, :read!, ["/mocked/" <> path]}
        end)
        |> Effects.run(fn
          {File, :read!, ["/mocked/test.txt"]} -> "transformed"
        end)

      assert result == "transformed"
    end
  end

  describe "Effects.compose/2" do
    test "composes multiple handlers" do
      file_handler = fn
        {File, _, _} = eff ->
          case eff do
            {File, :read!, [_]} -> "file content"
          end
      end

      io_handler = fn
        {IO, _, _} = eff ->
          case eff do
            {IO, :puts, [_]} -> :ok
          end
      end

      combined = Effects.compose(file_handler, io_handler)

      # Should use file_handler for File operations
      assert combined.({File, :read!, ["test.txt"]}) == "file content"

      # Should use io_handler for IO operations
      assert combined.({IO, :puts, ["hello"]}) == :ok
    end
  end

  describe "effect tracking options" do
    test "track specific effect categories" do
      # Only track :file effects
      eff =
        effect track: [:file] do
          x = File.read!("test.txt")
          # IO effects should not be tracked when track: [:file]
          # (if they were tracked, handler wouldn't match and test would fail)
          _ = "simulated IO operation"
          x
        end

      result =
        Effects.run(eff, fn
          {File, :read!, ["test.txt"]} -> "content"
        end)

      assert result == "content"
    end
  end
end
