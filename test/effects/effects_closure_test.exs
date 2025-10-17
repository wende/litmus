defmodule Litmus.EffectsClosureTest do
  @moduledoc """
  Tests for effects inside anonymous functions and closures.

  Anonymous functions can contain effects in their bodies, and when called,
  those effects are properly intercepted by the effect handler.
  """

  use ExUnit.Case, async: true

  import Litmus.Effects

  describe "anonymous functions with effects" do
    test "single clause function with effect" do
      result =
        effect do
          reader = fn -> File.read!("data.txt") end
          reader.()
        catch
          {File, :read!, ["data.txt"]} -> "mocked content"
        end

      assert result == "mocked content"
    end

    test "pattern matching function with effects" do
      result =
        effect do
          handler = fn
            :read -> File.read!("data.txt")
            :write -> File.write!("output.txt", "data")
          end

          handler.(:read)
        catch
          {File, :read!, ["data.txt"]} -> "mocked read"
          {File, :write!, _} -> "mocked write"
        end

      assert result == "mocked read"
    end

    test "function with multiple effects in body" do
      result =
        effect do
          processor = fn ->
            content = File.read!("input.txt")
            File.write!("output.txt", content)
            :done
          end

          processor.()
        catch
          {File, :read!, ["input.txt"]} -> "hello"
          {File, :write!, ["output.txt", "hello"]} -> :ok
        end

      assert result == :done
    end

    test "function with arguments containing effects" do
      result =
        effect do
          writer = fn path, content ->
            File.write!(path, content)
          end

          writer.("log.txt", "message")
        catch
          {File, :write!, ["log.txt", "message"]} -> :written
        end

      assert result == :written
    end
  end

  describe "closures capturing handler context" do
    test "closure captures handler variable" do
      result =
        effect do
          # Define function inside effect block
          loader = fn -> File.read!("config.json") end

          # Handler is in scope when function is defined
          loader.()
        catch
          {File, :read!, ["config.json"]} -> ~s({"config": "value"})
        end

      assert result == ~s({"config": "value"})
    end

    test "multiple calls to same closure" do
      result =
        effect do
          counter = fn ->
            File.write!("count.txt", "1")
          end

          counter.()
          counter.()
          :called_twice
        catch
          {File, :write!, ["count.txt", "1"]} -> :counted
        end

      assert result == :called_twice
    end

    @tag :skip
    test "closure defined in one branch, called in another (NOT YET SUPPORTED)" do
      # TODO: Closures created inside if branches and returned need special handling
      result =
        effect do
          # Define in one place
          reader =
            if true do
              fn -> File.read!("a.txt") end
            else
              fn -> File.read!("b.txt") end
            end

          # Call in another place
          reader.()
        catch
          {File, :read!, ["a.txt"]} -> "from a"
          {File, :read!, ["b.txt"]} -> "from b"
        end

      assert result == "from a"
    end
  end

  describe "higher-order functions" do
    @tag :skip
    test "function taking callback with effects (NOT YET SUPPORTED)" do
      # TODO: Requires tracking closures passed as parameters
      result =
        effect do
          process = fn callback ->
            value = callback.()
            File.write!("result.txt", value)
          end

          loader = fn -> File.read!("source.txt") end
          process.(loader)
        catch
          {File, :read!, ["source.txt"]} -> "loaded"
          {File, :write!, ["result.txt", "loaded"]} -> :saved
        end

      assert result == :saved
    end

    @tag :skip
    test "function returning function with effects (NOT YET SUPPORTED)" do
      # TODO: Requires tracking nested closure creation
      result =
        effect do
          make_reader = fn path ->
            fn -> File.read!(path) end
          end

          reader = make_reader.("data.txt")
          reader.()
        catch
          {File, :read!, ["data.txt"]} -> "nested closure result"
        end

      assert result == "nested closure result"
    end

    @tag :skip
    test "map with effectful function (NOT YET SUPPORTED)" do
      # TODO: Requires transforming closures passed to higher-order functions
      result =
        effect do
          paths = ["a.txt", "b.txt", "c.txt"]

          contents =
            Enum.map(paths, fn path ->
              File.read!(path)
            end)

          Enum.join(contents, ", ")
        catch
          {File, :read!, ["a.txt"]} -> "A"
          {File, :read!, ["b.txt"]} -> "B"
          {File, :read!, ["c.txt"]} -> "C"
        end

      assert result == "A, B, C"
    end

    test "inline higher-order function works" do
      # When the higher-order function is defined AND called in the effect block,
      # the transformation works correctly
      result =
        effect do
          apply_twice = fn f, x ->
            f.(f.(x))
          end

          doubler = fn x -> x * 2 end
          apply_twice.(doubler, 5)
        catch
          _ -> :should_not_match
        end

      assert result == 20
    end
  end

  describe "complex patterns" do
    test "guard clauses with effects" do
      result =
        effect do
          handler = fn
            x when x > 0 -> File.read!("positive.txt")
            x when x < 0 -> File.read!("negative.txt")
            _ -> "zero"
          end

          handler.(5)
        catch
          {File, :read!, ["positive.txt"]} -> "positive result"
          {File, :read!, ["negative.txt"]} -> "negative result"
        end

      assert result == "positive result"
    end

    test "function with mixed pure and effectful clauses" do
      result =
        effect do
          processor = fn
            :pure -> "pure value"
            :effect -> File.read!("data.txt")
          end

          # Call pure clause
          pure_result = processor.(:pure)
          # Call effectful clause
          effect_result = processor.(:effect)

          {pure_result, effect_result}
        catch
          {File, :read!, ["data.txt"]} -> "mocked"
        end

      assert result == {"pure value", "mocked"}
    end

    test "recursive function with effects" do
      result =
        effect do
          # Recursive function that reads files
          read_chain = fn
            _self, 0 ->
              "done"

            self, count ->
              File.read!("file#{count}.txt")
              self.(self, count - 1)
          end

          read_chain.(read_chain, 2)
        catch
          {File, :read!, ["file2.txt"]} -> "content2"
          {File, :read!, ["file1.txt"]} -> "content1"
        end

      assert result == "done"
    end
  end

  describe "variable capture" do
    test "closure captures variables from outer scope" do
      result =
        effect do
          prefix = "log_"

          writer = fn name ->
            File.write!(prefix <> name, "data")
          end

          writer.("test")
        catch
          {File, :write!, ["log_test", "data"]} -> :written
        end

      assert result == :written
    end

    test "multiple closures share captured context" do
      result =
        effect do
          base_path = "/var/log/"

          reader = fn -> File.read!(base_path <> "input.txt") end
          writer = fn -> File.write!(base_path <> "output.txt", "data") end

          {reader.(), writer.()}
        catch
          {File, :read!, ["/var/log/input.txt"]} -> "read"
          {File, :write!, ["/var/log/output.txt", "data"]} -> :written
        end

      assert result == {"read", :written}
    end
  end

  describe "edge cases" do
    test "empty function body" do
      result =
        effect do
          noop = fn -> :ok end
          noop.()
        catch
          _ -> :should_not_match
        end

      assert result == :ok
    end

    test "function with only pure operations" do
      result =
        effect do
          calculator = fn x, y -> x + y end
          calculator.(2, 3)
        catch
          _ -> :should_not_match
        end

      assert result == 5
    end

    test "function definition without call has no effects" do
      result =
        effect do
          # Define but never call
          _unused = fn -> File.read!("unused.txt") end
          :no_effects
        catch
          _ -> :should_not_match
        end

      assert result == :no_effects
    end
  end
end
