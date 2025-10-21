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

  describe "multi-effect functions (PDR 001/002)" do
    test "File.write! has both side effects and exceptions - can still match" do
      result =
        effect do
          File.write!("test.txt", "content")
        catch
          {File, :write!, ["test.txt", "content"]} -> :mocked_write
        end

      assert result == :mocked_write
    end

    test "function with IO.puts (side effect) and conditional raise - both effects handled" do
      result =
        effect do
          IO.puts("Processing...")
          x = File.read!("input.txt")
          if String.length(x) == 0 do
            raise ArgumentError, "empty"
          else
            :success
          end
        catch
          {IO, :puts, ["Processing..."]} -> :ok
          {File, :read!, ["input.txt"]} -> "content"
        end

      assert result == :success
    end

    test "function with File.read!, File.write!, and raise - match all" do
      result =
        effect do
          content = File.read!("input.txt")
          if String.length(content) == 0 do
            raise ArgumentError, "empty file"
          else
            File.write!("output.txt", content)
            :success
          end
        catch
          {File, :read!, ["input.txt"]} -> "test content"
          {File, :write!, ["output.txt", "test content"]} -> :ok
        end

      assert result == :success
    end

    test "function with System.get_env (dependent) and raise - match both" do
      result =
        effect do
          env_value = System.get_env("CONFIG")
          if is_nil(env_value) do
            raise ArgumentError, "missing config"
          else
            env_value
          end
        catch
          {System, :get_env, ["CONFIG"]} -> "test_config"
        end

      assert result == "test_config"
    end

    test "Map.fetch! has only exceptions (no side effects) - still matchable" do
      result =
        effect do
          Map.fetch!(%{a: 1}, :b)
        catch
          {Map, :fetch!, [%{a: 1}, :b]} -> :mocked_fetch
        end

      assert result == :mocked_fetch
    end

    test "Integer.parse! has only exceptions - still matchable" do
      result =
        effect do
          Integer.parse!("not a number")
        catch
          {Integer, :parse!, ["not a number"]} -> 42
        end

      assert result == 42
    end

    test "complex function with side effects, dependent, and exceptions" do
      result =
        effect do
          config = System.get_env("DATABASE_URL")
          IO.puts("Connecting to: #{config}")

          if is_nil(config) do
            raise RuntimeError, "no database config"
          else
            File.write!("connection.log", "Connected to #{config}")
            :connected
          end
        catch
          {System, :get_env, ["DATABASE_URL"]} -> "postgres://localhost"
          {IO, :puts, ["Connecting to: postgres://localhost"]} -> :ok
          {File, :write!, ["connection.log", "Connected to postgres://localhost"]} -> :ok
        end

      assert result == :connected
    end

    test "wildcard matching works with multi-effect functions" do
      result =
        effect do
          File.write!("anything.txt", "any content")
        catch
          {File, :write!, _} -> :wildcard_matched
        end

      assert result == :wildcard_matched
    end

    test "variable capture works with multi-effect functions" do
      result =
        effect do
          File.write!("log.txt", "important message")
        catch
          {File, :write!, [path, content]} ->
            # Return a tuple showing we captured the variables
            {:captured, path, content}
        end

      assert result == {:captured, "log.txt", "important message"}
    end
  end
end
