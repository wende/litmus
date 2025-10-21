defmodule Litmus.Registry.FileWriteEffectTest do
  use ExUnit.Case
  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.Core

  describe "File.write! effect analysis" do
    test "File.write!/2 returns side effect from bottommost function" do
      ast =
        quote do
          defmodule TestMod do
            def test_write do
              File.write!("test.txt", "content")
            end
          end
        end

      {:ok, result} = ASTWalker.analyze_ast(ast)
      func = result.functions[{TestMod, :test_write, 0}]

      all_effects = Core.extract_all_effects(func.effect)
      compact = Core.to_compact_effect(func.effect)

      # File.write!/2 should resolve to File.write/3 (bottommost side-effectful function)
      assert match?({:s, _}, compact), "Expected side effect, got #{inspect(compact)}"

      # Check that we track File.write/3 and helper functions
      side_effects =
        Enum.find(all_effects, fn
          {:s, _} -> true
          _ -> false
        end)

      assert side_effects != nil, "Expected side effect in #{inspect(all_effects)}"
      {:s, mfas} = side_effects
      assert "File.write/3" in mfas, "Expected File.write/3 in MFAs, got #{inspect(mfas)}"
    end

    test "File.write/2 returns side effect only (no exceptions)" do
      ast =
        quote do
          defmodule TestMod do
            def test_write do
              File.write("test.txt", "content")
            end
          end
        end

      {:ok, result} = ASTWalker.analyze_ast(ast)
      func = result.functions[{TestMod, :test_write, 0}]

      IO.puts("\n=== File.write/2 Analysis ===")
      IO.puts("Effect: #{inspect(func.effect, pretty: true)}")

      all_effects = Core.extract_all_effects(func.effect)
      IO.puts("\nAll effects: #{inspect(all_effects, pretty: true)}")

      # Should have side effects
      has_side_effect =
        Enum.any?(all_effects, fn
          {:s, _} -> true
          _ -> false
        end)

      # Should NOT have exception effects
      has_exception =
        Enum.any?(all_effects, fn
          {:e, _} -> true
          _ -> false
        end)

      assert has_side_effect, "Expected side effect"
      refute has_exception, "Should not have exception effect for File.write/2"
    end
  end
end
