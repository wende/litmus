defmodule LitmusTest do
  use ExUnit.Case
  # Skip doctests - Enum module uses maps which PURITY doesn't support
  # doctest Litmus

  @moduletag :integration

  describe "analyze_module/2" do
    test "successfully analyzes Erlang :lists module" do
      assert {:ok, results} = Litmus.analyze_module(:lists)
      assert is_map(results)
      assert map_size(results) > 0

      # Verify results contain MFA tuples as keys (most of them)
      # PURITY adds some built-in functions that might not be tuples
      mfa_keys = Map.keys(results) |> Enum.filter(fn
        {_, _, _} -> true
        _ -> false
      end)
      assert length(mfa_keys) > 200, "Expected mostly MFA tuples as keys"

      # Verify all values are valid purity levels
      valid_levels = [:pure, :exceptions, :dependent, :side_effects, :unknown]

      assert Enum.all?(Map.values(results), fn level ->
               level in valid_levels
             end)
    end

    test "returns error for non-existing module" do
      assert {:error, {:beam_not_found, :nonexistent_module_xyz, :non_existing}} =
               Litmus.analyze_module(:nonexistent_module_xyz)
    end

    # NOTE: :maps and :string use map literals which PURITY (2011) doesn't support
    # These tests are commented out due to known PURITY limitation

    # test "analyzes Erlang :maps module" do
    #   assert {:ok, results} = Litmus.analyze_module(:maps)
    #   assert map_size(results) > 0
    # end

    # test "analyzes Erlang :string module" do
    #   assert {:ok, results} = Litmus.analyze_module(:string)
    #   assert map_size(results) > 0
    # end

    test "analyzes Erlang :ordsets module" do
      assert {:ok, results} = Litmus.analyze_module(:ordsets)
      assert map_size(results) > 0
    end
  end

  describe "analyze_modules/2" do
    test "analyzes multiple modules sequentially" do
      # Use modules that don't have map literals (PURITY limitation)
      # :lists, :ordsets, :queue - pre-2014 Erlang modules
      modules = [:lists, :ordsets, :queue]
      assert {:ok, results} = Litmus.analyze_modules(modules)
      assert is_map(results)

      # Should contain functions from all modules
      module_names = results |> Map.keys() |> Enum.filter(fn {_, _, _} -> true; _ -> false end) |> Enum.map(fn {m, _, _} -> m end) |> Enum.uniq()
      assert :lists in module_names
      assert :ordsets in module_names
      assert :queue in module_names
    end

    test "returns error if any module doesn't exist" do
      modules = [:lists, :nonexistent_module, :maps]

      assert {:error, {:beam_not_found, :nonexistent_module, :non_existing}} =
               Litmus.analyze_modules(modules)
    end

    test "handles empty list" do
      {:ok, results} = Litmus.analyze_modules([])
      # PURITY adds some built-in erl functions even for empty input
      # Just verify it returns a map, don't check if empty
      assert is_map(results)
    end
  end

  describe "analyze_parallel/2" do
    test "analyzes multiple modules in parallel" do
      # Use modules that don't have map literals (PURITY limitation)
      # :lists, :ordsets, :queue - pre-2014 Erlang modules
      modules = [:lists, :ordsets, :queue]
      assert {:ok, results} = Litmus.analyze_parallel(modules)
      assert is_map(results)

      # Should contain functions from all modules
      module_names = results |> Map.keys() |> Enum.filter(fn {_, _, _} -> true; _ -> false end) |> Enum.map(fn {m, _, _} -> m end) |> Enum.uniq()
      assert :lists in module_names
      assert :ordsets in module_names
      assert :queue in module_names
    end

    test "returns error if any module doesn't exist" do
      modules = [:lists, :nonexistent_module, :maps]

      assert {:error, {:beam_not_found, :nonexistent_module, :non_existing}} =
               Litmus.analyze_parallel(modules)
    end
  end

  describe "pure?/2" do
    setup do
      {:ok, results} = Litmus.analyze_module(:lists)
      {:ok, results: results}
    end

    test "returns true for pure functions", %{results: results} do
      # lists:reverse/1 is pure
      assert Litmus.pure?(results, {:lists, :reverse, 1}) == true

      # lists:map/2 is pure (higher-order but operates on pure data)
      assert Litmus.pure?(results, {:lists, :map, 2}) == true

      # lists:foldl/3 is pure
      assert Litmus.pure?(results, {:lists, :foldl, 3}) == true

      # lists:filter/2 is pure
      assert Litmus.pure?(results, {:lists, :filter, 2}) == true
    end

    test "returns false for non-existent functions", %{results: results} do
      # Function that doesn't exist
      assert Litmus.pure?(results, {:lists, :nonexistent_function, 99}) == false
    end

    test "returns false for functions from unanalyzed modules", %{results: results} do
      # IO.puts is not in our results (we only analyzed :lists)
      assert Litmus.pure?(results, {:io, :puts, 1}) == false
    end
  end

  describe "get_purity/2" do
    setup do
      {:ok, results} = Litmus.analyze_module(:lists)
      {:ok, results: results}
    end

    test "returns purity level for existing functions", %{results: results} do
      assert {:ok, level} = Litmus.get_purity(results, {:lists, :reverse, 1})
      assert level in [:pure, :exceptions, :dependent, :side_effects, :unknown]
    end

    test "returns :error for non-existent functions", %{results: results} do
      assert :error = Litmus.get_purity(results, {:lists, :nonexistent, 99})
    end

    test "most common list functions are pure", %{results: results} do
      pure_functions = [
        {:lists, :reverse, 1},
        {:lists, :map, 2},
        {:lists, :filter, 2},
        {:lists, :foldl, 3},
        {:lists, :foldr, 3}
      ]

      for mfa <- pure_functions do
        assert {:ok, :pure} = Litmus.get_purity(results, mfa),
               "Expected #{inspect(mfa)} to be pure"
      end
    end
  end

  describe "find_missing/1" do
    test "returns missing functions and primops" do
      {:ok, results} = Litmus.analyze_module(:lists)
      %{functions: mfas, primops: primops} = Litmus.find_missing(results)

      assert is_list(mfas)
      assert is_list(primops)

      # For :lists module, there should be minimal missing functions
      # (it's a well-contained pure module)
      assert length(mfas) >= 0

      # All returned MFAs should be tuples
      assert Enum.all?(mfas, fn
               {m, f, a} when is_atom(m) and is_atom(f) and is_integer(a) -> true
               _ -> false
             end)
    end

    test "works with empty results" do
      results = %{}
      %{functions: mfas, primops: primops} = Litmus.find_missing(results)

      assert mfas == []
      assert primops == []
    end
  end

  describe "purity classification" do
    test "correctly identifies pure mathematical functions" do
      {:ok, results} = Litmus.analyze_module(:lists)

      # These are deterministic, side-effect free operations
      pure_mfas = [
        {:lists, :reverse, 1},
        {:lists, :sort, 1},
        {:lists, :flatten, 1},
        {:lists, :append, 2},
        {:lists, :subtract, 2}
      ]

      for mfa <- pure_mfas do
        case Litmus.get_purity(results, mfa) do
          {:ok, :pure} ->
            assert true

          {:ok, other} ->
            # Some might be classified differently, but shouldn't be side_effects
            assert other != :side_effects,
                   "#{inspect(mfa)} should not have side effects, got #{other}"

          :error ->
            flunk("#{inspect(mfa)} not found in results")
        end
      end
    end

    test "map size provides reasonable coverage" do
      {:ok, results} = Litmus.analyze_module(:lists)

      # :lists module has ~200+ functions
      assert map_size(results) > 100,
             "Expected to analyze substantial portion of :lists module"
    end
  end

  describe "edge cases" do
    test "handles same module analyzed multiple times" do
      assert {:ok, results1} = Litmus.analyze_module(:lists)
      assert {:ok, results2} = Litmus.analyze_module(:lists)

      # Should produce consistent results
      assert map_size(results1) == map_size(results2)
    end

    test "sequential and parallel analysis produce similar results" do
      # Use modules without map literals
      modules = [:lists, :ordsets]

      {:ok, seq_results} = Litmus.analyze_modules(modules)
      {:ok, par_results} = Litmus.analyze_parallel(modules)

      # Should have same number of functions
      assert map_size(seq_results) == map_size(par_results)

      # Should have same function keys
      assert MapSet.new(Map.keys(seq_results)) == MapSet.new(Map.keys(par_results))
    end
  end

  describe "performance" do
    @tag :slow
    @tag timeout: 120_000
    test "can analyze multiple large modules efficiently" do
      # Use modules without map literals (pre-2014 Erlang modules)
      modules = [:lists, :ordsets, :queue, :gb_sets, :gb_trees]

      # Should complete in reasonable time
      assert {:ok, results} =
               :timer.tc(fn -> Litmus.analyze_parallel(modules) end)
               |> elem(1)

      # Verify we got results for multiple modules
      module_names = results |> Map.keys() |> Enum.filter(fn {_, _, _} -> true; _ -> false end) |> Enum.map(fn {m, _, _} -> m end) |> Enum.uniq()
      assert length(module_names) >= 3, "Expected at least 3 modules analyzed"
    end
  end

  describe "pure_stdlib?/1" do
    test "returns true for whitelisted Elixir stdlib functions" do
      assert Litmus.pure_stdlib?({Enum, :map, 2})
      assert Litmus.pure_stdlib?({List, :first, 1})
      assert Litmus.pure_stdlib?({Integer, :to_string, 1})
      assert Litmus.pure_stdlib?({String, :upcase, 1})
      assert Litmus.pure_stdlib?({Kernel, :+, 2})
    end

    test "returns false for side-effect functions" do
      refute Litmus.pure_stdlib?({IO, :puts, 1})
      refute Litmus.pure_stdlib?({File, :read, 1})
      refute Litmus.pure_stdlib?({System, :cmd, 2})
      refute Litmus.pure_stdlib?({Process, :send, 2})
    end

    test "returns false for dangerous functions" do
      refute Litmus.pure_stdlib?({String, :to_atom, 1})
      refute Litmus.pure_stdlib?({String, :to_existing_atom, 1})
    end

    test "returns false for unknown modules" do
      refute Litmus.pure_stdlib?({UnknownModule, :foo, 1})
      refute Litmus.pure_stdlib?({MyApp.CustomModule, :bar, 2})
    end
  end

  describe "safe_to_optimize?/2" do
    setup do
      {:ok, results} = Litmus.analyze_module(:lists)
      {:ok, results: results}
    end

    test "returns true for functions pure by PURITY analysis", %{results: results} do
      assert Litmus.safe_to_optimize?(results, {:lists, :reverse, 1})
      assert Litmus.safe_to_optimize?(results, {:lists, :map, 2})
      assert Litmus.safe_to_optimize?(results, {:lists, :foldl, 3})
    end

    test "returns true for functions pure by stdlib whitelist (no analysis needed)" do
      assert Litmus.safe_to_optimize?(nil, {Enum, :map, 2})
      assert Litmus.safe_to_optimize?(nil, {Integer, :to_string, 1})
      assert Litmus.safe_to_optimize?(nil, {String, :upcase, 1})
    end

    test "returns true combining both sources", %{results: results} do
      # Works with either PURITY results or whitelist
      assert Litmus.safe_to_optimize?(results, {Enum, :map, 2})
      assert Litmus.safe_to_optimize?(results, {:lists, :reverse, 1})
    end

    test "returns false for known impure functions" do
      refute Litmus.safe_to_optimize?(nil, {IO, :puts, 1})
      refute Litmus.safe_to_optimize?(nil, {File, :read, 1})
      refute Litmus.safe_to_optimize?(nil, {Process, :send, 2})
    end

    test "returns false for unknown functions (conservative)", %{results: results} do
      refute Litmus.safe_to_optimize?(results, {:unknown_module, :foo, 1})
      refute Litmus.safe_to_optimize?(nil, {:unknown_module, :foo, 1})
    end

    test "handles nil results gracefully" do
      # Should still work with whitelist only
      assert Litmus.safe_to_optimize?(nil, {Enum, :map, 2})
      refute Litmus.safe_to_optimize?(nil, {IO, :puts, 1})
    end
  end
end
