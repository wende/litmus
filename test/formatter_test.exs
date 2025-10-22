defmodule Litmus.FormatterTest do
  use ExUnit.Case
  alias Litmus.Formatter

  @moduledoc """
  Tests for the Litmus.Formatter module to ensure robust formatting
  of types and effects without crashes.

  These tests prevent regressions in display/output code that previously
  caused crashes when handling effect variables or complex effect types.
  """

  describe "format_type/1" do
    test "handles basic types" do
      assert Formatter.format_type(:int) == "Int"
      assert Formatter.format_type(:string) == "String"
      assert Formatter.format_type(:bool) == "Bool"
      assert Formatter.format_type(:atom) == "Atom"
      assert Formatter.format_type(:any) == "Any"
    end

    test "handles type variables" do
      assert Formatter.format_type({:type_var, :alpha}) == "alpha"
      assert Formatter.format_type({:type_var, :t}) == "t"
    end

    test "handles function types" do
      result = Formatter.format_type({:function, :int, {:effect_empty}, :string})
      assert result == "Int -> ⟨⟩ String"
    end

    test "handles function types with effects" do
      result =
        Formatter.format_type({:function, :int, {:s, ["File.read/1"]}, :string})

      assert result =~ "Int ->"
      assert result =~ "String"
      assert result =~ "File.read/1"
    end

    test "handles tuples" do
      assert Formatter.format_type({:tuple, []}) == "{}"
      assert Formatter.format_type({:tuple, [:int, :string]}) == "{Int, String}"
    end

    test "handles lists" do
      assert Formatter.format_type({:list, :int}) == "[Int]"
    end

    test "handles maps" do
      assert Formatter.format_type({:map, []}) == "%{}"

      result = Formatter.format_type({:map, [{:atom, :string}]})
      assert result == "%{Atom => String}"
    end

    test "handles union types" do
      result = Formatter.format_type({:union, [:int, :string]})
      assert result == "Int | String"
    end

    test "handles forall quantification" do
      result = Formatter.format_type({:forall, [{:type_var, :a}], :a})
      assert result =~ "∀"
      assert result =~ "a"
    end

    test "handles unknown types gracefully" do
      result = Formatter.format_type({:weird_type, :unknown})
      # Should not crash, returns inspect fallback
      assert is_binary(result)
    end
  end

  describe "format_effect/1" do
    test "handles empty effect" do
      assert Formatter.format_effect({:effect_empty}) == "⟨⟩"
    end

    test "handles effect labels" do
      assert Formatter.format_effect({:effect_label, :exn}) == "⟨exn⟩"
      assert Formatter.format_effect({:effect_label, :io}) == "⟨io⟩"
    end

    test "handles effect variables (Issue #98983d5)" do
      # This used to crash when displaying effect variables
      result = Formatter.format_effect({:effect_var, :alpha})
      assert result == "alpha"

      result = Formatter.format_effect({:effect_var, :beta})
      assert result == "beta"
    end

    test "handles unknown effect" do
      assert Formatter.format_effect({:effect_unknown}) == "¿"
    end

    test "handles side effect tuples" do
      assert Formatter.format_effect({:s, ["File.read/1"]}) == "⟨File.read/1⟩"

      result = Formatter.format_effect({:s, ["File.read/1", "IO.puts/1"]})
      assert result == "⟨File.read/1 | IO.puts/1⟩"
    end

    test "handles dependent effect tuples" do
      assert Formatter.format_effect({:d, ["System.get_env/1"]}) ==
               "⟨System.get_env/1⟩"

      result =
        Formatter.format_effect({:d, ["System.get_env/1", "Process.get/1"]})

      assert result == "⟨System.get_env/1 | Process.get/1⟩"
    end

    test "handles exception effect tuples" do
      result = Formatter.format_effect({:e, ["Elixir.ArgumentError"]})
      assert result =~ "ArgumentError"

      result =
        Formatter.format_effect({:e, ["Elixir.ArgumentError", "Elixir.KeyError"]})

      assert result =~ "ArgumentError"
      assert result =~ "KeyError"
    end

    test "handles dynamic exceptions" do
      result = Formatter.format_effect({:e, [:dynamic]})
      assert result =~ "dynamic"
    end

    test "handles effect rows" do
      result =
        Formatter.format_effect({:effect_row, :exn, {:s, ["File.write/2"]}})

      assert result =~ "exn"
      assert result =~ "File.write/2"
    end

    test "handles complex effect rows" do
      result =
        Formatter.format_effect(
          {:effect_row, {:e, ["Elixir.ArgumentError"]}, {:s, ["IO.puts/1"]}}
        )

      assert result =~ "ArgumentError"
      assert result =~ "IO.puts/1"
    end

    test "handles unknown effect shapes gracefully" do
      result = Formatter.format_effect({:weird_effect, :unknown})
      # Should not crash, returns inspect fallback
      assert is_binary(result)
    end
  end

  describe "format_compact_effect/1" do
    test "handles all compact effect types" do
      assert Formatter.format_compact_effect(:p) == "p (pure)"
      assert Formatter.format_compact_effect(:d) == "d (dependent)"
      assert Formatter.format_compact_effect(:l) == "l (lambda)"
      assert Formatter.format_compact_effect(:n) == "n (nif)"
      assert Formatter.format_compact_effect(:s) == "s (side effects)"
      assert Formatter.format_compact_effect(:exn) == "e (exceptions)"
      assert Formatter.format_compact_effect(:u) == "u (unknown)"
    end

    test "handles exception types with details" do
      result = Formatter.format_compact_effect({:e, ["Elixir.ArgumentError"]})
      assert result =~ "e ("
      assert result =~ "ArgumentError"
    end

    test "handles multiple exception types" do
      result =
        Formatter.format_compact_effect(
          {:e, ["Elixir.ArgumentError", "Elixir.KeyError"]}
        )

      assert result =~ "ArgumentError"
      assert result =~ "KeyError"
    end

    test "handles unknown compact effects gracefully" do
      result = Formatter.format_compact_effect({:unknown_compact, :data})
      assert is_binary(result)
    end
  end

  describe "format_var/1" do
    test "handles type variables" do
      assert Formatter.format_var({:type_var, :alpha}) == "alpha"
    end

    test "handles effect variables" do
      assert Formatter.format_var({:effect_var, :beta}) == "beta"
    end

    test "handles unknown variables gracefully" do
      result = Formatter.format_var({:weird_var, :data})
      assert is_binary(result)
    end
  end
end
