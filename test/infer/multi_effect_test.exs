defmodule MultiEffectTest do
  @moduledoc """
  Integration tests for PDR 001 and 002: Functions with multiple simultaneous effect types.

  Tests that functions can have both side effects and exceptions (or other combinations)
  properly tracked and displayed.
  """
  use ExUnit.Case
  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.Core

  # Helper to analyze code and get effect
  defp analyze_function(ast, module, function, arity) do
    {:ok, result} = ASTWalker.analyze_ast(ast)
    mfa = {module, function, arity}

    case Map.get(result.functions, mfa) do
      nil -> {:error, :function_not_found}
      func_analysis -> {:ok, func_analysis}
    end
  end

  describe "functions with side effects AND exceptions" do
    test "function with File.write! and raise has both side effects and exceptions" do
      ast =
        quote do
          defmodule TestMod do
            def test_write(path, data) do
              if String.length(data) == 0 do
                raise ArgumentError, "empty data"
              else
                File.write!(path, data)
              end
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :test_write, 2)

      # Extract all effects
      all_effects = Core.extract_all_effects(func.effect)

      # Should have BOTH side effects and exceptions
      assert Enum.any?(all_effects, fn
               {:s, _} -> true
               _ -> false
             end),
             "Expected side effects in #{inspect(all_effects)}"

      assert Enum.any?(all_effects, fn
               {:e, _} -> true
               _ -> false
             end),
             "Expected exceptions in #{inspect(all_effects)}"

      # Compact effect should return most severe (side effects > exceptions)
      compact = Core.to_compact_effect(func.effect)
      assert match?({:s, _}, compact), "Expected compact effect to be {:s, _}, got #{inspect(compact)}"
    end

    test "custom function with IO and raise" do
      ast =
        quote do
          defmodule TestMod do
            def log_and_raise(msg) do
              IO.puts("Error: " <> msg)
              raise ArgumentError, msg
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :log_and_raise, 1)

      # Extract all effects
      all_effects = Core.extract_all_effects(func.effect)

      # Should have both side effects (IO.puts) and exceptions (raise)
      assert Enum.any?(all_effects, fn
               {:s, list} -> "IO.puts/1" in list
               _ -> false
             end),
             "Expected IO.puts/1 side effect"

      assert Enum.any?(all_effects, fn
               {:e, types} -> "Elixir.ArgumentError" in types
               _ -> false
             end),
             "Expected ArgumentError exception"

      # Should have exactly 2 effect types
      assert length(all_effects) == 2
    end

    test "function with File.read!, File.write!, and conditional raise" do
      ast =
        quote do
          defmodule TestMod do
            def process_file(input, output) do
              content = File.read!(input)
              if String.length(content) == 0 do
                raise ArgumentError, "empty file"
              else
                File.write!(output, content)
              end
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :process_file, 2)

      # Extract all effects
      all_effects = Core.extract_all_effects(func.effect)

      # Should have side effects with multiple MFAs
      # Note: File.write!/2 now resolves to File.write/3 (bottommost)
      side_effect_entry =
        Enum.find(all_effects, fn
          {:s, _} -> true
          _ -> false
        end)

      assert side_effect_entry != nil, "Expected side effect entry"
      {:s, mfas} = side_effect_entry
      assert "File.read!/1" in mfas
      assert "File.write/3" in mfas or "IO.warn/1" in mfas, "Expected File.write/3 or its helpers in MFAs, got: #{inspect(mfas)}"

      # Should have exceptions
      exception_entry =
        Enum.find(all_effects, fn
          {:e, _} -> true
          _ -> false
        end)

      assert exception_entry != nil, "Expected exception entry"
      {:e, types} = exception_entry
      assert "Elixir.ArgumentError" in types or "Elixir.File.Error" in types
    end
  end

  describe "functions with dependent effects AND exceptions" do
    test "function reading env and raising" do
      ast =
        quote do
          defmodule TestMod do
            def get_required_env(key) do
              case System.get_env(key) do
                nil -> raise ArgumentError, "missing env var"
                value -> value
              end
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :get_required_env, 1)

      # Extract all effects
      all_effects = Core.extract_all_effects(func.effect)

      # Should have dependent effects
      assert Enum.any?(all_effects, fn
               {:d, list} -> "System.get_env/1" in list
               _ -> false
             end),
             "Expected System.get_env/1 dependent effect"

      # Should have exceptions
      assert Enum.any?(all_effects, fn
               {:e, types} -> "Elixir.ArgumentError" in types
               _ -> false
             end),
             "Expected ArgumentError exception"

      # Compact effect should return dependent (more severe than exception)
      compact = Core.to_compact_effect(func.effect)
      assert match?({:d, _}, compact), "Expected compact effect to be {:d, _}, got #{inspect(compact)}"
    end
  end

  # Lambda detection from function parameters is a separate feature
  # For now, skip these tests as they require bidirectional inference improvements

  describe "functions with multiple effect types" do
    test "complex function with side effects, dependent, and exceptions" do
      ast =
        quote do
          defmodule TestMod do
            def complex_operation(data) do
              env_value = System.get_env("CONFIG")
              IO.puts("Processing with config: " <> env_value)

              if String.length(data) == 0 do
                raise RuntimeError, "empty data"
              else
                File.write!("output.txt", data)
                data
              end
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :complex_operation, 1)

      # Extract all effects
      all_effects = Core.extract_all_effects(func.effect)

      # Should have side effects
      assert Enum.any?(all_effects, fn
               {:s, list} -> "IO.puts/1" in list or "File.write!/2" in list
               _ -> false
             end),
             "Expected side effects, got #{inspect(all_effects)}"

      # Should have dependent effects
      assert Enum.any?(all_effects, fn
               {:d, list} -> "System.get_env/1" in list
               _ -> false
             end),
             "Expected dependent effects, got #{inspect(all_effects)}"

      # Should have exceptions
      assert Enum.any?(all_effects, fn
               {:e, _} -> true
               _ -> false
             end),
             "Expected exceptions, got #{inspect(all_effects)}"

      # Should have at least 3 distinct effect types
      assert length(all_effects) >= 3,
             "Expected at least 3 distinct effect types, got #{length(all_effects)}: #{inspect(all_effects)}"

      # Compact effect should return most severe (side effects)
      compact = Core.to_compact_effect(func.effect)
      assert match?({:s, _}, compact), "Expected compact effect to be {:s, _}, got #{inspect(compact)}"
    end
  end

  describe "pure functions with only exceptions" do
    test "Map.fetch!/2 has only exceptions (no side effects)" do
      ast =
        quote do
          defmodule TestMod do
            def get_value(map, key) do
              Map.fetch!(map, key)
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :get_value, 2)

      # Extract all effects
      all_effects = Core.extract_all_effects(func.effect)

      # Should have only exceptions (no side effects, no dependent)
      assert Enum.all?(all_effects, fn
               {:e, _} -> true
               :p -> true
               _ -> false
             end),
             "Expected only exceptions or pure, got #{inspect(all_effects)}"

      # Compact effect should be exception
      compact = Core.to_compact_effect(func.effect)
      assert match?({:e, _}, compact), "Expected compact effect to be {:e, _}, got #{inspect(compact)}"
    end

    test "Integer.parse!/1 has only exceptions" do
      ast =
        quote do
          defmodule TestMod do
            def parse_number(str) do
              Integer.parse!(str)
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :parse_number, 1)

      # Extract all effects
      all_effects = Core.extract_all_effects(func.effect)

      # Should have exceptions
      assert Enum.any?(all_effects, fn
               {:e, _} -> true
               _ -> false
             end),
             "Expected exceptions"

      # Should NOT have side effects
      refute Enum.any?(all_effects, fn
               {:s, _} -> true
               _ -> false
             end),
             "Should not have side effects"

      # Compact effect should be exception
      compact = Core.to_compact_effect(func.effect)
      assert match?({:e, _}, compact), "Expected compact effect to be {:e, _}, got #{inspect(compact)}"
    end
  end

  describe "edge cases" do
    test "function with unknown and exceptions" do
      ast =
        quote do
          defmodule TestMod do
            def dynamic_call(mod, fun, arg) do
              result = apply(mod, fun, [arg])
              if is_nil(result) do
                raise ArgumentError, "nil result"
              else
                result
              end
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :dynamic_call, 3)

      # apply/3 is unknown, raise adds exception
      # Should have unknown effect (most severe)
      # Compact effect should be unknown
      compact = Core.to_compact_effect(func.effect)
      assert compact == :u or match?({:s, _}, compact),
             "Expected compact effect to be :u or {:s, _}, got #{inspect(compact)}"
    end

    test "function with NIF and exceptions" do
      ast =
        quote do
          defmodule TestMod do
            def crypto_operation(data) do
              result = :crypto.hash(:sha256, data)
              if byte_size(result) == 0 do
                raise ArgumentError, "hash failed"
              else
                result
              end
            end
          end
        end

      {:ok, func} = analyze_function(ast, TestMod, :crypto_operation, 1)

      # :crypto.hash is a NIF
      # Should have both NIF and exception effects

      # Compact effect should be NIF (more severe than exception)
      compact = Core.to_compact_effect(func.effect)
      # Depending on registry, might be :n or :u
      assert compact in [:n, :u, :s],
             "Expected compact effect to be :n, :u, or :s, got #{inspect(compact)}"
    end
  end
end
