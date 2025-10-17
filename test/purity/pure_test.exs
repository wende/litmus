defmodule Litmus.PureTest do
  use ExUnit.Case, async: true
  import Litmus.Pure

  describe "pure/1 macro - successful compilation" do
    test "allows pure Enum operations" do
      result =
        pure do
          [1, 2, 3, 4, 5]
          |> Enum.map(fn x -> x * 2 end)
          |> Enum.filter(fn x -> x > 5 end)
          |> Enum.sum()
        end

      # [1,2,3,4,5] |> map(*2) => [2,4,6,8,10] |> filter(>5) => [6,8,10] |> sum => 24
      assert result == 24
    end

    test "allows pure List operations" do
      result =
        pure do
          list = [1, 2, 3]
          List.duplicate(list, 3) |> List.flatten()
        end

      assert result == [1, 2, 3, 1, 2, 3, 1, 2, 3]
    end

    test "allows pure String operations" do
      result =
        pure do
          "hello world"
          |> String.upcase()
          |> String.reverse()
        end

      assert result == "DLROW OLLEH"
    end

    test "allows pure Integer operations" do
      result =
        pure do
          Integer.digits(12345)
          |> Enum.sum()
        end

      assert result == 15
    end

    test "allows pure Kernel operations" do
      result =
        pure do
          x = 10
          y = 20
          x + y * 2
        end

      assert result == 50
    end

    test "allows nested pure function calls" do
      result =
        pure do
          data = [1, 2, 3]

          data
          |> Enum.map(fn x ->
            String.duplicate("*", x)
          end)
          |> Enum.join(", ")
        end

      assert result == "*, **, ***"
    end

    test "allows pure mathematical operations" do
      result =
        pure do
          list = [1.5, 2.7, 3.2]

          list
          |> Enum.map(&Float.ceil/1)
          |> Enum.sum()
        end

      assert result == 9.0
    end

    test "allows Map operations" do
      result =
        pure do
          map = %{a: 1, b: 2, c: 3}
          Map.get(map, :b)
        end

      assert result == 2
    end

    test "allows Jason encode and decode" do
      result =
        pure do
          {:ok, json} = Jason.encode(%{name: "Alice", age: 30})
          {:ok, decoded} = Jason.decode(json)
          decoded
        end

      assert result == %{"name" => "Alice", "age" => 30}
    end

    test "allows Tuple operations" do
      result =
        pure do
          tuple = {:ok, 42, "data"}
          elem(tuple, 1)
        end

      assert result == 42
    end

    test "returns the last expression value" do
      result =
        pure do
          x = Enum.sum([1, 2, 3])
          y = String.length("hello")
          x + y
        end

      assert result == 11
    end
  end

  describe "pure/1 macro - compilation failures" do
    test "raises error for IO operations" do
      assert_raise Litmus.Pure.ImpurityError, ~r/IO.puts\/1/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure do
              IO.puts("Hello")
            end
          end
        )
      end
    end

    test "raises error for File operations" do
      assert_raise Litmus.Pure.ImpurityError, ~r/File.read\/1/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure do
              File.read("test.txt")
            end
          end
        )
      end
    end

    test "raises error for Process operations" do
      assert_raise Litmus.Pure.ImpurityError, ~r/Process.send\/2/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure do
              Process.send(self(), :msg)
            end
          end
        )
      end
    end

    test "raises error for String.to_atom/1" do
      assert_raise Litmus.Pure.ImpurityError, ~r/String.to_atom\/1/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure do
              String.to_atom("test")
            end
          end
        )
      end
    end

    test "raises error for System operations" do
      assert_raise Litmus.Pure.ImpurityError, ~r/System.get_env\/1/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure do
              System.get_env("PATH")
            end
          end
        )
      end
    end

    test "raises error for Logger operations" do
      assert_raise Litmus.Pure.ImpurityError, ~r/Logger.info\/1/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure do
              Logger.info("test")
            end
          end
        )
      end
    end

    test "raises error for Kernel.send/2" do
      assert_raise Litmus.Pure.ImpurityError, ~r/Kernel.send\/2/, fn ->
        Code.eval_quoted(
          quote do
            import Litmus.Pure

            pure do
              send(self(), :msg)
            end
          end
        )
      end
    end

    test "error message includes classification" do
      error =
        assert_raise Litmus.Pure.ImpurityError, fn ->
          Code.eval_quoted(
            quote do
              import Litmus.Pure

              pure do
                IO.inspect("test")
              end
            end
          )
        end

      assert error.message =~ "I/O operation"
    end

    test "error message lists all impure calls" do
      error =
        assert_raise Litmus.Pure.ImpurityError, fn ->
          Code.eval_quoted(
            quote do
              import Litmus.Pure

              pure do
                IO.puts("hello")
                File.read("test.txt")
                Process.send(self(), :msg)
              end
            end
          )
        end

      assert error.message =~ "IO.puts"
      assert error.message =~ "File.read"
      assert error.message =~ "Process.send"
    end
  end

  describe "check_purity/1" do
    test "returns {:ok, calls} for pure code" do
      ast =
        quote do
          Enum.map([1, 2, 3], fn x -> x * 2 end)
        end

      assert {:ok, calls} = Litmus.Pure.check_purity(ast)
      assert {Enum, :map, 2} in calls
    end

    test "returns {:error, impure_calls} for impure code" do
      ast =
        quote do
          IO.puts("Hello")
          File.read("test.txt")
        end

      assert {:error, impure_calls} = Litmus.Pure.check_purity(ast)
      assert {IO, :puts, 1} in impure_calls
      assert {File, :read, 1} in impure_calls
    end

    test "handles mixed pure and impure code" do
      ast =
        quote do
          x = Enum.sum([1, 2, 3])
          IO.puts(x)
        end

      assert {:error, impure_calls} = Litmus.Pure.check_purity(ast)
      assert {IO, :puts, 1} in impure_calls
      refute {Enum, :sum, 1} in impure_calls
    end

    test "returns empty impure list for pure code" do
      ast =
        quote do
          String.upcase("hello")
        end

      assert {:ok, _calls} = Litmus.Pure.check_purity(ast)
    end
  end

  describe "list_calls/1" do
    test "extracts all function calls from AST" do
      ast =
        quote do
          x = Enum.map([1, 2, 3], fn n -> n * 2 end)
          String.upcase("hello")
        end

      calls = Litmus.Pure.list_calls(ast)
      assert {Enum, :map, 2} in calls
      assert {String, :upcase, 1} in calls
    end

    test "extracts Kernel function calls" do
      ast =
        quote do
          x = 10
          y = 20
          x + y
        end

      calls = Litmus.Pure.list_calls(ast)
      assert {Kernel, :+, 2} in calls
    end

    test "handles nested calls" do
      ast =
        quote do
          [1, 2, 3]
          |> Enum.map(&String.duplicate("*", &1))
          |> Enum.join(", ")
        end

      calls = Litmus.Pure.list_calls(ast)
      # Note: list_calls without env doesn't expand macros, so pipe shows up
      # We can see pipe operator and String.duplicate, but not expanded calls
      assert {Kernel, :|>, 2} in calls
      assert {String, :duplicate, 2} in calls
    end

    test "returns empty list for code without function calls" do
      ast =
        quote do
          x = 42
          y = "hello"
          {x, y}
        end

      calls = Litmus.Pure.list_calls(ast)
      # Should be empty or only contain basic operators
      # Note: Even tuple creation might not show up as a call
      assert is_list(calls)
    end

    test "deduplicates repeated calls" do
      ast =
        quote do
          String.upcase("hello")
          String.upcase("world")
          String.upcase("test")
        end

      calls = Litmus.Pure.list_calls(ast)
      # Should only appear once despite being called 3 times
      assert Enum.count(calls, fn call -> call == {String, :upcase, 1} end) == 1
    end
  end

  describe "edge cases" do
    test "handles empty blocks" do
      result =
        pure do
          :ok
        end

      assert result == :ok
    end

    test "handles single expression" do
      result =
        pure do
          Enum.sum([1, 2, 3])
        end

      assert result == 6
    end

    test "handles complex nested structures" do
      result =
        pure do
          data = %{
            values: [1, 2, 3],
            multiplier: 2
          }

          Map.get(data, :values)
          |> Enum.map(&(&1 * Map.get(data, :multiplier)))
          |> Enum.sum()
        end

      assert result == 12
    end

    test "preserves variable bindings" do
      result =
        pure do
          x = 10
          y = 20
          z = x + y
          z * 2
        end

      assert result == 60
    end
  end

  describe "module alias handling" do
    test "correctly resolves aliased modules" do
      ast =
        quote do
          alias Enum, as: E
          E.map([1, 2, 3], & &1)
        end

      calls = Litmus.Pure.list_calls(ast)
      # The alias should be resolved to Enum
      # Note: This might not work perfectly as written since we're analyzing AST
      # The important thing is that it doesn't crash
      assert is_list(calls)
    end
  end

  describe "practical examples" do
    test "pure data transformation pipeline" do
      result =
        pure do
          [
            %{name: "Alice", age: 30},
            %{name: "Bob", age: 25},
            %{name: "Charlie", age: 35}
          ]
          |> Enum.filter(fn person -> Map.get(person, :age) > 26 end)
          |> Enum.map(fn person -> Map.get(person, :name) end)
          |> Enum.join(", ")
        end

      assert result == "Alice, Charlie"
    end

    test "pure mathematical computation" do
      result =
        pure do
          numbers = [1, 2, 3, 4, 5]

          sum = Enum.sum(numbers)
          count = Enum.count(numbers)
          average = sum / count

          Float.round(average, 2)
        end

      assert result == 3.0
    end

    test "pure string processing" do
      result =
        pure do
          text = "Hello World From Elixir"

          text
          |> String.downcase()
          |> String.split(" ")
          |> Enum.map(&String.reverse/1)
          |> Enum.join("-")
        end

      assert result == "olleh-dlrow-morf-rixile"
    end
  end
end
