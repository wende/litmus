defmodule Litmus.TerminationTest do
  use ExUnit.Case, async: true
  import Litmus.Pure

  doctest Litmus, import: true

  describe "analyze_termination/2" do
    test "analyzes :lists module for termination" do
      {:ok, results} = Litmus.analyze_termination(:lists)
      assert is_map(results)

      # Most list functions should terminate
      assert Litmus.terminates?(results, {:lists, :reverse, 1})
      assert Litmus.terminates?(results, {:lists, :map, 2})
      assert Litmus.terminates?(results, {:lists, :filter, 2})
    end

    test "returns error for non-existent module" do
      assert {:error, {:beam_not_found, NonExistent, :non_existing}} =
               Litmus.analyze_termination(NonExistent)
    end
  end

  describe "analyze_termination_modules/2" do
    test "analyzes multiple modules for termination" do
      {:ok, results} = Litmus.analyze_termination_modules([:lists, :ordsets])
      assert is_map(results)

      # Check results from both modules
      assert Litmus.terminates?(results, {:lists, :reverse, 1})
      # Note: ordsets.union/2 is recursive so PURITY marks it as non-terminating
      assert Litmus.terminates?(results, {:ordsets, :is_set, 1})
    end

    test "returns error if any module is missing" do
      assert {:error, {:beam_not_found, NonExistent, :non_existing}} =
               Litmus.analyze_termination_modules([:lists, NonExistent])
    end
  end

  describe "analyze_both/2" do
    test "performs combined purity and termination analysis" do
      {:ok, results} = Litmus.analyze_both(:lists)
      assert is_map(results)

      # Results should be tuples of {purity_level, termination_level}
      assert {:pure, :terminating} = results[{:lists, :reverse, 1}]
      assert {:pure, :terminating} = results[{:lists, :map, 2}]
    end

    test "returns error for non-existent module" do
      assert {:error, {:beam_not_found, NonExistent, :non_existing}} =
               Litmus.analyze_both(NonExistent)
    end
  end

  describe "terminates?/2" do
    test "returns true for terminating functions" do
      {:ok, results} = Litmus.analyze_termination(:lists)
      assert Litmus.terminates?(results, {:lists, :reverse, 1}) == true
      assert Litmus.terminates?(results, {:lists, :map, 2}) == true
    end

    test "returns false for unknown functions" do
      {:ok, results} = Litmus.analyze_termination(:lists)
      assert Litmus.terminates?(results, {:unknown, :func, 1}) == false
    end
  end

  describe "get_termination/2" do
    test "returns termination level for functions in results" do
      {:ok, results} = Litmus.analyze_termination(:lists)
      assert {:ok, :terminating} = Litmus.get_termination(results, {:lists, :reverse, 1})
    end

    test "returns :error for functions not in results" do
      {:ok, results} = Litmus.analyze_termination(:lists)
      assert :error = Litmus.get_termination(results, {:unknown, :func, 1})
    end
  end

  describe "Litmus.Stdlib.terminates?/1" do
    test "returns true for stdlib functions that terminate" do
      assert Litmus.Stdlib.terminates?({Enum, :map, 2})
      assert Litmus.Stdlib.terminates?({List, :first, 1})
      assert Litmus.Stdlib.terminates?({String, :upcase, 1})
      assert Litmus.Stdlib.terminates?({Integer, :to_string, 1})
    end

    test "returns false for infinite Stream generators" do
      refute Litmus.Stdlib.terminates?({Stream, :cycle, 1})
      refute Litmus.Stdlib.terminates?({Stream, :iterate, 2})
      refute Litmus.Stdlib.terminates?({Stream, :repeatedly, 1})
      refute Litmus.Stdlib.terminates?({Stream, :unfold, 2})
      refute Litmus.Stdlib.terminates?({Stream, :resource, 3})
    end

    test "returns false for blocking Process operations" do
      refute Litmus.Stdlib.terminates?({Process, :sleep, 1})
      refute Litmus.Stdlib.terminates?({Process, :hibernate, 3})
    end

    test "returns false for blocking GenServer operations" do
      refute Litmus.Stdlib.terminates?({GenServer, :call, 2})
      refute Litmus.Stdlib.terminates?({GenServer, :call, 3})
    end

    test "returns false for blocking Task operations" do
      refute Litmus.Stdlib.terminates?({Task, :await, 1})
      refute Litmus.Stdlib.terminates?({Task, :await, 2})
      refute Litmus.Stdlib.terminates?({Task, :await_many, 1})
      refute Litmus.Stdlib.terminates?({Task, :await_many, 2})
    end

    test "returns false for blocking Agent operations" do
      refute Litmus.Stdlib.terminates?({Agent, :get, 2})
      refute Litmus.Stdlib.terminates?({Agent, :get, 3})
      refute Litmus.Stdlib.terminates?({Agent, :update, 2})
      refute Litmus.Stdlib.terminates?({Agent, :update, 3})
    end

    test "handles invalid MFA tuples gracefully" do
      # Should return true (conservative - assume terminates)
      assert Litmus.Stdlib.terminates?({:not_a_module, :func, 1})
      assert Litmus.Stdlib.terminates?({String, "not_atom", 1})
    end
  end

  describe "Litmus.Stdlib.get_termination/1" do
    test "returns :terminating for terminating functions" do
      assert Litmus.Stdlib.get_termination({Enum, :map, 2}) == :terminating
      assert Litmus.Stdlib.get_termination({List, :first, 1}) == :terminating
    end

    test "returns :non_terminating for non-terminating functions" do
      assert Litmus.Stdlib.get_termination({Stream, :cycle, 1}) == :non_terminating
      assert Litmus.Stdlib.get_termination({Process, :sleep, 1}) == :non_terminating
    end
  end

  describe "Litmus.Stdlib.non_terminating_modules/0" do
    test "returns list of modules with non-terminating functions" do
      modules = Litmus.Stdlib.non_terminating_modules()
      assert is_list(modules)
      assert Stream in modules
      assert Process in modules
      assert GenServer in modules
      assert Task in modules
      assert Agent in modules
    end

    test "does not include modules with only terminating functions" do
      modules = Litmus.Stdlib.non_terminating_modules()
      refute Enum in modules
      refute List in modules
      refute String in modules
    end
  end

  describe "Litmus.Stdlib.non_terminating_functions/1" do
    test "returns non-terminating functions for Stream" do
      functions = Litmus.Stdlib.non_terminating_functions(Stream)
      assert {:cycle, 1} in functions
      assert {:iterate, 2} in functions
      assert {:repeatedly, 1} in functions
    end

    test "returns non-terminating functions for Process" do
      functions = Litmus.Stdlib.non_terminating_functions(Process)
      assert {:sleep, 1} in functions
      assert {:hibernate, 3} in functions
    end

    test "returns empty list for modules with only terminating functions" do
      assert Litmus.Stdlib.non_terminating_functions(Enum) == []
      assert Litmus.Stdlib.non_terminating_functions(List) == []
    end

    test "returns empty list for unknown modules" do
      assert Litmus.Stdlib.non_terminating_functions(UnknownModule) == []
    end
  end

  describe "pure macro with require_termination: true" do
    test "allows terminating functions" do
      result =
        pure require_termination: true do
          x = [1, 2, 3]
          Enum.map(x, fn n -> n * 2 end)
        end

      assert result == [2, 4, 6]
    end

    test "fails for non-terminating Stream.cycle" do
      assert_raise Litmus.Pure.ImpurityError, ~r/Stream.cycle\/1/, fn ->
        Code.compile_quoted(
          quote do
            import Litmus.Pure

            pure require_termination: true do
              Stream.cycle([1, 2, 3])
            end
          end
        )
      end
    end

    test "fails for Process.sleep" do
      assert_raise Litmus.Pure.ImpurityError, ~r/Process.sleep\/1/, fn ->
        Code.compile_quoted(
          quote do
            import Litmus.Pure

            pure require_termination: true do
              Process.sleep(100)
            end
          end
        )
      end
    end

    test "combines with purity level checking" do
      # Should allow pure, terminating functions
      result =
        pure level: :pure, require_termination: true do
          [1, 2, 3]
          |> Enum.map(&(&1 * 2))
          |> Enum.sum()
        end

      assert result == 12
    end

    test "fails for both impure and non-terminating" do
      assert_raise Litmus.Pure.ImpurityError, ~r/Multiple violations/, fn ->
        Code.compile_quoted(
          quote do
            import Litmus.Pure

            pure require_termination: true do
              IO.puts("test")
              Stream.cycle([1, 2])
            end
          end
        )
      end
    end
  end

  describe "pure macro termination error messages" do
    test "provides helpful error message for Stream.cycle" do
      try do
        Code.compile_quoted(
          quote do
            import Litmus.Pure

            pure require_termination: true do
              Stream.cycle([1, 2, 3])
            end
          end
        )

        flunk("Expected ImpurityError to be raised")
      rescue
        error in [Litmus.Pure.ImpurityError] ->
          message = Exception.message(error)
          assert message =~ "Stream.cycle/1"
          assert message =~ "infinite generator"
          assert message =~ "may run forever"
      end
    end

    test "provides helpful error message for Process.sleep" do
      try do
        Code.compile_quoted(
          quote do
            import Litmus.Pure

            pure require_termination: true do
              Process.sleep(1000)
            end
          end
        )

        flunk("Expected ImpurityError to be raised")
      rescue
        error in [Litmus.Pure.ImpurityError] ->
          message = Exception.message(error)
          assert message =~ "Process.sleep/1"
          assert message =~ "blocking process operation"
      end
    end
  end

  describe "integration tests" do
    test "pure terminating code compiles successfully" do
      result =
        pure require_termination: true do
          numbers = [1, 2, 3, 4, 5]

          numbers
          |> Enum.map(&(&1 * 2))
          |> Enum.filter(&(&1 > 5))
          |> Enum.reduce(0, &+/2)
        end

      # [1,2,3,4,5] -> [2,4,6,8,10] -> [6,8,10] -> 24
      assert result == 24
    end

    test "combining purity levels with termination" do
      # Exception-raising but terminating should work
      result =
        pure level: :exceptions, require_termination: true do
          Integer.parse("123")
        end

      assert result == {123, ""}
    end
  end

  describe "edge cases" do
    test "empty block with require_termination passes" do
      result =
        pure require_termination: true do
          :ok
        end

      assert result == :ok
    end

    test "only literals with require_termination passes" do
      result =
        pure require_termination: true do
          x = 42
          y = "hello"
          [x, y]
        end

      assert result == [42, "hello"]
    end

    test "nested function calls all checked for termination" do
      result =
        pure require_termination: true do
          [1, 2, 3]
          |> Enum.map(fn n ->
            Integer.to_string(n)
          end)
          |> Enum.join(",")
        end

      assert result == "1,2,3"
    end
  end
end
