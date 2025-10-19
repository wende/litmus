defmodule Litmus.Inference.ContextTest do
  use ExUnit.Case, async: true

  alias Litmus.Inference.Context
  alias Litmus.Types.Core

  describe "scope management" do
    test "enter_scope increases scope level" do
      ctx = Context.empty()
      ctx = Context.enter_scope(ctx)

      assert ctx.scope_level == 1
    end

    test "exit_scope decreases scope level" do
      ctx = Context.empty()
      |> Context.enter_scope()
      |> Context.enter_scope()
      |> Context.exit_scope()

      assert ctx.scope_level == 1
    end

    test "exit_scope on level 0 returns unchanged context" do
      ctx = Context.empty()
      result = Context.exit_scope(ctx)

      assert result.scope_level == 0
      assert result == ctx
    end

    test "nested scopes track properly" do
      ctx = Context.empty()
      |> Context.enter_scope()  # level 1
      |> Context.enter_scope()  # level 2
      |> Context.enter_scope()  # level 3

      assert ctx.scope_level == 3

      ctx = Context.exit_scope(ctx)  # level 2
      assert ctx.scope_level == 2

      ctx = Context.exit_scope(ctx)  # level 1
      assert ctx.scope_level == 1

      ctx = Context.exit_scope(ctx)  # level 0
      assert ctx.scope_level == 0
    end
  end

  describe "effect management" do
    test "add_effect adds effect to context" do
      ctx = Context.empty()
      |> Context.add_effect({:effect_label, :io})

      effects = Context.get_effects(ctx)

      assert {:effect_label, :io} in effects
    end

    test "multiple effects accumulate in order" do
      ctx = Context.empty()
      |> Context.add_effect({:effect_label, :io})
      |> Context.add_effect({:effect_label, :exn})
      |> Context.add_effect({:effect_label, :file})

      effects = Context.get_effects(ctx)

      # Effects are added to the front, so they appear in reverse order
      assert effects == [
        {:effect_label, :file},
        {:effect_label, :exn},
        {:effect_label, :io}
      ]
    end

    test "get_effects returns empty list for new context" do
      ctx = Context.empty()
      effects = Context.get_effects(ctx)

      assert effects == []
    end
  end

  describe "merge/2" do
    test "merges bindings from two contexts" do
      ctx1 = Context.empty()
      |> Context.add(:x, :int)
      |> Context.add(:y, :string)

      ctx2 = Context.empty()
      |> Context.add(:z, :bool)

      merged = Context.merge(ctx1, ctx2)

      assert {:ok, :int} = Context.lookup(merged, :x)
      assert {:ok, :string} = Context.lookup(merged, :y)
      assert {:ok, :bool} = Context.lookup(merged, :z)
    end

    test "second context bindings override first" do
      ctx1 = Context.empty()
      |> Context.add(:x, :int)

      ctx2 = Context.empty()
      |> Context.add(:x, :string)

      merged = Context.merge(ctx1, ctx2)

      assert {:ok, :string} = Context.lookup(merged, :x)
    end

    test "merges effects from both contexts" do
      ctx1 = Context.empty()
      |> Context.add_effect({:effect_label, :io})

      ctx2 = Context.empty()
      |> Context.add_effect({:effect_label, :exn})

      merged = Context.merge(ctx1, ctx2)
      effects = Context.get_effects(merged)

      assert {:effect_label, :io} in effects
      assert {:effect_label, :exn} in effects
    end

    test "takes maximum scope level" do
      ctx1 = Context.empty()
      |> Context.enter_scope()
      |> Context.enter_scope()

      ctx2 = Context.empty()
      |> Context.enter_scope()

      merged = Context.merge(ctx1, ctx2)

      assert merged.scope_level == 2
    end
  end

  describe "free_variables/1" do
    test "returns empty set for context with no variables" do
      ctx = Context.empty()
      |> Context.add(:x, :int)
      |> Context.add(:y, :string)

      vars = Context.free_variables(ctx)

      assert MapSet.size(vars) == 0
    end

    test "finds free type variables in bindings" do
      ctx = Context.empty()
      |> Context.add(:x, {:type_var, :a})
      |> Context.add(:y, {:list, {:type_var, :b}})

      vars = Context.free_variables(ctx)

      assert MapSet.member?(vars, {:type_var, :a})
      assert MapSet.member?(vars, {:type_var, :b})
    end

    test "finds free variables in function types" do
      ctx = Context.empty()
      |> Context.add(:f, {:function, {:type_var, :a}, {:effect_var, :e}, {:type_var, :b}})

      vars = Context.free_variables(ctx)

      assert MapSet.member?(vars, {:type_var, :a})
      assert MapSet.member?(vars, {:type_var, :b})
      assert MapSet.member?(vars, {:effect_var, :e})
    end
  end

  describe "has_binding?/2 and remove/2" do
    test "has_binding? returns true for existing binding" do
      ctx = Context.empty()
      |> Context.add(:x, :int)

      assert Context.has_binding?(ctx, :x)
    end

    test "has_binding? returns false for non-existent binding" do
      ctx = Context.empty()

      refute Context.has_binding?(ctx, :x)
    end

    test "remove removes binding from context" do
      ctx = Context.empty()
      |> Context.add(:x, :int)
      |> Context.add(:y, :string)

      ctx = Context.remove(ctx, :x)

      refute Context.has_binding?(ctx, :x)
      assert Context.has_binding?(ctx, :y)
    end

    test "remove on non-existent binding is safe" do
      ctx = Context.empty()
      |> Context.add(:x, :int)

      result = Context.remove(ctx, :y)

      assert Context.has_binding?(result, :x)
    end
  end

  describe "with_stdlib/0" do
    test "creates context with standard library bindings" do
      ctx = Context.with_stdlib()

      # Check arithmetic operators
      assert {:ok, _type} = Context.lookup(ctx, :+)
      assert {:ok, _type} = Context.lookup(ctx, :-)
      assert {:ok, _type} = Context.lookup(ctx, :*)

      # Check comparisons
      assert {:ok, _type} = Context.lookup(ctx, :==)
      assert {:ok, _type} = Context.lookup(ctx, :<)
      assert {:ok, _type} = Context.lookup(ctx, :>)

      # Check boolean operations
      assert {:ok, _type} = Context.lookup(ctx, :and)
      assert {:ok, _type} = Context.lookup(ctx, :or)
      assert {:ok, _type} = Context.lookup(ctx, :not)

      # Check list operations
      assert {:ok, _type} = Context.lookup(ctx, :hd)
      assert {:ok, _type} = Context.lookup(ctx, :tl)
      assert {:ok, _type} = Context.lookup(ctx, :length)
    end

    test "stdlib arithmetic operators have correct types" do
      ctx = Context.with_stdlib()

      {:ok, plus_type} = Context.lookup(ctx, :+)
      assert plus_type == {:function, {:tuple, [:int, :int]}, Core.empty_effect(), :int}
    end

    test "stdlib comparison operators are polymorphic" do
      ctx = Context.with_stdlib()

      {:ok, eq_type} = Context.lookup(ctx, :==)
      # Should be ∀a. (a, a) -> Bool
      assert {:function, {:tuple, [{:type_var, :a}, {:type_var, :a}]}, _effect, :bool} = eq_type
    end

    test "stdlib list operations have correct effect annotations" do
      ctx = Context.with_stdlib()

      # hd and tl can raise exceptions
      {:ok, hd_type} = Context.lookup(ctx, :hd)
      assert {:forall, [{:type_var, :a}],
               {:function, {:list, {:type_var, :a}}, {:effect_label, :exn}, {:type_var, :a}}} = hd_type

      # length is pure
      {:ok, length_type} = Context.lookup(ctx, :length)
      assert {:forall, [{:type_var, :a}],
               {:function, {:list, {:type_var, :a}}, {:effect_empty}, :int}} = length_type
    end
  end

  describe "format/1" do
    test "formats empty context" do
      ctx = Context.empty()
      result = Context.format(ctx)

      assert result =~ "Context"
      assert result =~ "scope level: 0"
    end

    test "formats context with bindings" do
      ctx = Context.empty()
      |> Context.add(:x, :int)
      |> Context.add(:y, :string)

      result = Context.format(ctx)

      assert result =~ "x"
      assert result =~ "y"
      assert result =~ "Int"
      assert result =~ "String"
    end

    test "formats context with effects" do
      ctx = Context.empty()
      |> Context.add_effect({:effect_label, :io})
      |> Context.add_effect({:effect_label, :exn})

      result = Context.format(ctx)

      assert result =~ "io"
      assert result =~ "exn"
    end

    test "shows (none) for context with no effects" do
      ctx = Context.empty()
      |> Context.add(:x, :int)

      result = Context.format(ctx)

      assert result =~ "(none)"
    end
  end

  describe "integration: realistic inference scenarios" do
    test "type checking a let expression with scoping" do
      # let x = 5 in let y = x + 1 in y
      ctx = Context.empty()
      |> Context.enter_scope()  # enter let scope for x
      |> Context.add(:x, :int)
      |> Context.enter_scope()  # enter let scope for y
      |> Context.add(:y, :int)

      assert Context.has_binding?(ctx, :x)
      assert Context.has_binding?(ctx, :y)
      assert ctx.scope_level == 2
    end

    test "tracking effects through function composition" do
      # Functions that compose effects
      ctx = Context.empty()
      |> Context.add(:read_file, {:function, :string, {:effect_label, :file}, :string})
      |> Context.add(:print, {:function, :string, {:effect_label, :io}, {:tuple, []}})

      # Compose them
      ctx = ctx
      |> Context.add_effect({:effect_label, :file})
      |> Context.add_effect({:effect_label, :io})

      effects = Context.get_effects(ctx)

      assert {:effect_label, :file} in effects
      assert {:effect_label, :io} in effects
    end

    test "applying substitution updates all bindings" do
      ctx = Context.empty()
      |> Context.add(:x, {:type_var, :a})
      |> Context.add(:y, {:list, {:type_var, :a}})
      |> Context.add(:z, {:type_var, :b})

      # Infer that a = Int, b = String
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string
      }

      ctx = Context.apply_substitution(ctx, subst)

      assert {:ok, :int} = Context.lookup(ctx, :x)
      assert {:ok, {:list, :int}} = Context.lookup(ctx, :y)
      assert {:ok, :string} = Context.lookup(ctx, :z)
    end

    test "polymorphic function instantiation" do
      # Start with polymorphic map: ∀a b. (a -> b, List[a]) -> List[b]
      ctx = Context.with_stdlib()

      map_type = {:forall, [{:type_var, :a}, {:type_var, :b}],
                   {:function,
                     {:tuple, [
                       {:function, {:type_var, :a}, Core.empty_effect(), {:type_var, :b}},
                       {:list, {:type_var, :a}}
                     ]},
                     Core.empty_effect(),
                     {:list, {:type_var, :b}}}}

      ctx = Context.add(ctx, :map, map_type)

      assert {:ok, ^map_type} = Context.lookup(ctx, :map)
    end
  end
end
