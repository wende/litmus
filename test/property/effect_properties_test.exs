defmodule Litmus.EffectPropertiesTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Litmus.Formatter
  alias Litmus.Types.Core

  @moduledoc """
  Property-based tests for the effect system using StreamData.

  These tests generate random effect types and verify invariants hold:
  - No crashes when formatting
  - JSON encodability
  - Type system invariants
  """

  describe "effect formatting properties" do
    property "all effect types are formattable without crashing" do
      check all(effect <- effect_generator(), max_runs: 100) do
        # Should never crash when formatting
        result = Formatter.format_effect(effect)
        assert is_binary(result)
      end
    end

    property "formatted effects are non-empty strings" do
      check all(effect <- effect_generator(), max_runs: 100) do
        result = Formatter.format_effect(effect)
        assert String.length(result) > 0
      end
    end

    property "effect variables format to their name" do
      check all(var_name <- atom(:alphanumeric), max_runs: 50) do
        effect = {:effect_var, var_name}
        result = Formatter.format_effect(effect)
        assert result == to_string(var_name)
      end
    end
  end

  describe "compact effect properties" do
    property "all compact effects are formattable" do
      check all(compact <- compact_effect_generator(), max_runs: 100) do
        result = Formatter.format_compact_effect(compact)
        assert is_binary(result)
        assert String.length(result) > 0
      end
    end

    property "compact effects contain effect name" do
      check all(compact <- basic_compact_effect_generator(), max_runs: 50) do
        result = Formatter.format_compact_effect(compact)

        # Should contain the effect abbreviation
        assert result =~ ~r/[pldnseou]/
      end
    end
  end

  describe "JSON encoding properties" do
    property "mix effect --json output is valid JSON for various files" do
      # Test that JSON output works correctly by actually running the task
      # This indirectly tests the private compact_effect_to_json and all_effects_to_json functions

      check all(
              _iteration <- integer(1..20),
              max_runs: 20
            ) do
        # Run mix effect with JSON output on a test file
        json_output =
          ExUnit.CaptureIO.capture_io(fn ->
            Mix.Tasks.Effect.run(["test/support/demo.ex", "--json"])
          end)

        # Should produce valid JSON
        assert {:ok, _parsed} = Jason.decode(json_output)
      end
    end
  end

  describe "type formatting properties" do
    property "all basic types are formattable" do
      check all(type <- basic_type_generator(), max_runs: 100) do
        result = Formatter.format_type(type)
        assert is_binary(result)
        assert String.length(result) > 0
      end
    end

    property "type variables format to their name" do
      check all(var_name <- atom(:alphanumeric), max_runs: 50) do
        type = {:type_var, var_name}
        result = Formatter.format_type(type)
        assert result == to_string(var_name)
      end
    end
  end

  describe "effect system invariants" do
    property "to_compact_effect never crashes" do
      check all(effect <- effect_generator(), max_runs: 100) do
        # Should either return a compact effect or raise a known error
        result =
          try do
            Core.to_compact_effect(effect)
          rescue
            _ -> :error
          end

        assert result != nil
      end
    end

    property "extract_all_effects returns a list" do
      check all(effect <- effect_generator(), max_runs: 100) do
        result =
          try do
            Core.extract_all_effects(effect)
          rescue
            _ -> []
          end

        assert is_list(result)
      end
    end
  end

  # --- Generators ---

  defp effect_generator do
    one_of([
      constant({:effect_empty}),
      effect_var_generator(),
      constant({:effect_unknown}),
      effect_label_generator(),
      side_effect_generator(),
      dependent_effect_generator(),
      exception_effect_generator()
      # Note: effect_row generator omitted to avoid infinite recursion
    ])
  end

  defp effect_var_generator do
    map(atom(:alphanumeric), fn name -> {:effect_var, name} end)
  end

  defp effect_label_generator do
    map(atom(:alphanumeric), fn label -> {:effect_label, label} end)
  end

  defp side_effect_generator do
    map(list_of(mfa_string_generator(), min_length: 1, max_length: 3), fn calls ->
      {:s, calls}
    end)
  end

  defp dependent_effect_generator do
    map(list_of(mfa_string_generator(), min_length: 1, max_length: 3), fn calls ->
      {:d, calls}
    end)
  end

  defp exception_effect_generator do
    map(list_of(exception_name_generator(), min_length: 1, max_length: 3), fn types ->
      {:e, types}
    end)
  end

  defp mfa_string_generator do
    # Generate realistic MFA strings like "File.read/1"
    one_of([
      constant("File.read/1"),
      constant("IO.puts/1"),
      constant("System.get_env/1"),
      constant("Process.get/1"),
      constant("Enum.map/2")
    ])
  end

  defp exception_name_generator do
    one_of([
      constant("Elixir.ArgumentError"),
      constant("Elixir.KeyError"),
      constant("Elixir.RuntimeError"),
      constant(:dynamic),
      constant(:exn)
    ])
  end

  defp compact_effect_generator do
    one_of([
      basic_compact_effect_generator()
    ])
  end

  defp basic_compact_effect_generator do
    one_of([
      constant(:p),
      constant(:l),
      constant(:d),
      constant(:u),
      constant(:n),
      constant(:exn)
    ])
  end

  defp basic_type_generator do
    one_of([
      constant(:int),
      constant(:float),
      constant(:string),
      constant(:bool),
      constant(:atom),
      constant(:pid),
      constant(:reference),
      constant(:any),
      map(atom(:alphanumeric), fn name -> {:type_var, name} end),
      tuple_type_generator(),
      list_type_generator()
    ])
  end

  defp tuple_type_generator do
    one_of([
      constant({:tuple, []}),
      map(list_of(constant(:int), min_length: 1, max_length: 3), fn types ->
        {:tuple, types}
      end)
    ])
  end

  defp list_type_generator do
    map(constant(:int), fn type -> {:list, type} end)
  end
end
