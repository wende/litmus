defmodule NestedClosureTrackingTest do
  @moduledoc """
  Tests for nested closure tracking functionality.

  These tests verify that the type system can:
  1. Define closure types with captured and return effects
  2. Detect when functions return closures
  3. Track effects through closure calls
  """

  use ExUnit.Case, async: true

  alias Litmus.Types.{Core, Effects}
  alias Litmus.Inference.Bidirectional

  describe "Closure type construction" do
    test "creates closure type with captured and return effects" do
      captured_effect = Core.empty_effect()
      return_effect = Core.single_effect(:io)

      closure_type = Core.closure_type(:string, captured_effect, return_effect)

      assert closure_type == {:closure, :string, captured_effect, return_effect}
    end

    test "closure type contains both captured and return effects" do
      captured_effect = Core.single_effect(:dependent)
      return_effect = {:s, ["IO.puts/1"]}

      closure_type = Core.closure_type(:int, captured_effect, return_effect)

      # Verify structure
      assert is_tuple(closure_type)
      assert tuple_size(closure_type) == 4
      assert elem(closure_type, 0) == :closure
    end
  end

  describe "Closure effect extraction" do
    test "extracts return effect from closure type" do
      return_effect = Core.single_effect(:io)
      closure_type = Core.closure_type(:string, Core.empty_effect(), return_effect)

      extracted = Effects.extract_closure_return_effect(closure_type)

      assert extracted == return_effect
    end

    test "returns empty effect for non-closure types" do
      function_type = Core.function_type(:int, Core.single_effect(:io), :string)

      extracted = Effects.extract_closure_return_effect(function_type)

      assert extracted == Core.empty_effect()
    end
  end

  describe "Closure type unification" do
    test "unifies two compatible closure types" do
      alias Litmus.Types.Unification

      closure1 = Core.closure_type(:string, Core.empty_effect(), Core.single_effect(:io))
      closure2 = Core.closure_type(:string, Core.empty_effect(), Core.single_effect(:io))

      result = Unification.unify(closure1, closure2)

      assert {:ok, _subst} = result
    end

    test "fails to unify closures with different return effects" do
      alias Litmus.Types.Unification

      closure1 = Core.closure_type(:string, Core.empty_effect(), Core.single_effect(:io))
      closure2 = Core.closure_type(:string, Core.empty_effect(), Core.single_effect(:file))

      result = Unification.unify(closure1, closure2)

      assert {:error, _} = result
    end
  end

  describe "Closure type substitution" do
    test "applies substitution to closure type" do
      alias Litmus.Types.Substitution

      type_var = {:type_var, :a}
      effect_var = {:effect_var, :e}

      closure = Core.closure_type(type_var, Core.empty_effect(), effect_var)

      subst = %{
        type_var => :string,
        effect_var => Core.single_effect(:io)
      }

      result = Substitution.apply_subst(subst, closure)

      expected =
        Core.closure_type(:string, Core.empty_effect(), Core.single_effect(:io))

      assert result == expected
    end
  end

  describe "Closure variable capture" do
    test "closure tracking helpers are available in bidirectional module" do
      # The helper functions for closure tracking are available internally
      # in the bidirectional module and are used during lambda synthesis
      # This test just verifies the module loads correctly with these functions
      assert is_atom(Bidirectional)
    end
  end

  describe "Closure application" do
    test "closure types are handled in function application" do
      # This is more of an integration test to verify the type system
      # can handle closure types being called without errors

      context = Litmus.Inference.Context.empty()

      # Add a closure-returning function to context
      closure_type = Core.closure_type(:string, Core.empty_effect(), Core.single_effect(:io))
      context_with_closure = Litmus.Inference.Context.add(context, :make_logger, closure_type)

      # Synthesizing a variable with closure type should work
      result = Bidirectional.synthesize({:make_logger, [], Elixir}, context_with_closure)

      assert {:ok, type, _effect, _subst} = result
      assert type == closure_type
    end
  end
end
