defmodule Litmus.EffectsNewApiTest do
  use ExUnit.Case, async: true

  import Litmus.Effects

  describe "effect with catch syntax" do
    test "single effect with inline handler" do
      result =
        effect do
          File.read!("test.txt")
        catch
          {File, :read!, ["test.txt"]} -> "mocked content"
        end

      assert result == "mocked content"
    end

    test "sequential effects" do
      result =
        effect do
          x = File.read!("a.txt")
          y = File.read!("b.txt")
          x <> y
        catch
          {File, :read!, ["a.txt"]} -> "hello "
          {File, :read!, ["b.txt"]} -> "world"
        end

      assert result == "hello world"
    end

    test "effect with pure code between" do
      result =
        effect do
          x = File.read!("input.txt")
          y = String.upcase(x)
          File.write!("output.txt", y)
          y
        catch
          {File, :read!, ["input.txt"]} -> "hello"
          {File, :write!, ["output.txt", "HELLO"]} -> :ok
        end

      assert result == "HELLO"
    end

    test "wildcard pattern" do
      result =
        effect do
          File.read!("test.txt")
        catch
          {File, :read!, _} -> "wildcard match"
        end

      assert result == "wildcard match"
    end

    test "effect with variable capture in handler" do
      result =
        effect do
          File.write!("log.txt", "message")
        catch
          {File, :write!, [path, content]} ->
            assert path == "log.txt"
            assert content == "message"
            :ok
        end

      assert result == :ok
    end
  end

  describe "effect with external handler" do
    test "using handler function" do
      mock_handler = fn
        {File, :read!, _} -> "external mock"
      end

      result =
        effect(
          do: File.read!("test.txt"),
          catch: mock_handler
        )

      assert result == "external mock"
    end

    test "reusable handler" do
      file_mock = fn
        {File, :read!, _} -> "mocked"
        {File, :write!, _} -> :ok
      end

      result1 =
        effect(
          do: File.read!("a.txt"),
          catch: file_mock
        )

      result2 =
        effect(
          do: File.write!("b.txt", "data"),
          catch: file_mock
        )

      assert result1 == "mocked"
      assert result2 == :ok
    end
  end

  describe "branching with effects" do
    test "if with effect in true branch" do
      result =
        effect do
          x =
            if true do
              File.read!("true.txt")
            else
              "false value"
            end

          x
        catch
          {File, :read!, ["true.txt"]} -> "from true branch"
        end

      assert result == "from true branch"
    end

    test "if with effect in false branch" do
      result =
        effect do
          x =
            if false do
              File.read!("true.txt")
            else
              File.read!("false.txt")
            end

          x
        catch
          {File, :read!, ["false.txt"]} -> "from false branch"
        end

      assert result == "from false branch"
    end

    test "if with no effects in one branch" do
      result =
        effect do
          x =
            if false do
              File.read!("file.txt")
            else
              "pure value"
            end

          File.write!("output.txt", x)
        catch
          {File, :write!, ["output.txt", "pure value"]} -> :written
        end

      assert result == :written
    end
  end

  # describe "effect tracking options" do
  #   test "track specific effect categories" do
  #     result =
  #       effect track: [:file] do
  #         x = File.read!("test.txt")
  #         # IO effects should not be tracked when track: [:file]
  #         # (if they were tracked, this would raise UnhandledError)
  #         _ = "simulated IO operation"
  #         x
  #       catch
  #         {File, :read!, _} -> "tracked"
  #       end

  #     assert result == "tracked"
  #   end
  # end
end
