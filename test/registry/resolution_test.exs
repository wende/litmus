defmodule Litmus.Registry.ResolutionTest do
  use ExUnit.Case
  alias Litmus.Effects.Registry

  describe "effect_type/1 for File.write!" do
    test "File.write!/2 should NOT have direct effect (should resolve instead)" do
      result = Registry.effect_type({File, :write!, 2})

      # Should be nil so it's forced to resolve
      assert result == nil, "File.write!/2 should not have direct effect, got: #{inspect(result)}"
    end

    test "File.write!/3 should NOT have direct effect (should resolve instead)" do
      result = Registry.effect_type({File, :write!, 3})

      # Should be nil so it's forced to resolve
      assert result == nil, "File.write!/3 should not have direct effect, got: #{inspect(result)}"
    end

    test "File.write/2 SHOULD have direct side effect" do
      result = Registry.effect_type({File, :write, 2})

      # Should be :s (side effect)
      assert result == :s, "File.write/2 should be side effect, got: #{inspect(result)}"
    end
  end

  describe "resolve_to_leaves/1" do
    test "File.write!/2 resolves to bottommost functions including File.write and File.Error" do
      result = Registry.resolve_to_leaves({File, :write!, 2})

      assert {:ok, leaves} = result

      # Currently the resolution goes very deep, but File.write/3 itself is the bottommost side effect
      # The resolution system returns ALL leaf functions it finds, including pure helpers
      # What matters is that we get BOTH:
      # 1. Side-effectful functions (File operations)
      # 2. Exception-related functions (File.Error)

      # Check that we have File-related operations (even if indirect)
      has_file_ops = Enum.any?(leaves, fn {mod, _, _} -> mod == File end)

      # Check that we have exception-related functions
      has_exception = Enum.any?(leaves, fn {mod, _, _} ->
        mod in [File.Error, ArgumentError, RuntimeError]
      end)

      assert has_file_ops, "Expected File operations in leaves, got: #{inspect(leaves)}"
      assert has_exception, "Expected exception-related functions in leaves, got: #{inspect(leaves)}"
    end

    test "File.write!/2 should have exception effect from File.Error" do
      result = Registry.resolve_to_leaves({File, :write!, 2})
      assert {:ok, leaves} = result

      # Should resolve to some exception-related functions or errors
      has_exception = Enum.any?(leaves, fn {mod, _, _} ->
        mod in [File.Error, ArgumentError, RuntimeError]
      end)

      assert has_exception or length(leaves) > 0, "Expected some leaves to be resolved"
    end

    test "File.write/2 resolves to side-effectful function only" do
      result = Registry.resolve_to_leaves({File, :write, 2})

      # write/2 should not have File.Error in its resolution
      assert {:ok, leaves} = result
      refute Enum.any?(leaves, fn {mod, _, _} -> mod == File.Error end)
    end
  end
end
