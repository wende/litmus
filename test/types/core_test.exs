defmodule Litmus.Types.CoreTest do
  use ExUnit.Case, async: true
  doctest Litmus.Types.Core

  alias Litmus.Types.Core

  describe "basic constructors" do
    test "empty_effect/0 creates empty effect" do
      assert Core.empty_effect() == {:effect_empty}
    end

    test "single_effect/1 creates single effect label" do
      assert Core.single_effect(:io) == {:effect_label, :io}
      assert Core.single_effect(:exn) == {:effect_label, :exn}
    end

    test "extend_effect/2 extends effect row" do
      assert Core.extend_effect(:io, Core.empty_effect()) ==
               {:effect_row, :io, {:effect_empty}}

      assert Core.extend_effect(:exn, Core.single_effect(:io)) ==
               {:effect_row, :exn, {:effect_label, :io}}
    end

    test "function_type/3 creates function type with effects" do
      assert Core.function_type(:int, Core.single_effect(:io), :string) ==
               {:function, :int, {:effect_label, :io}, :string}
    end

    test "forall_type/2 creates polymorphic type" do
      assert Core.forall_type([{:type_var, :a}], {:type_var, :a}) ==
               {:forall, [{:type_var, :a}], {:type_var, :a}}

      assert Core.forall_type(
               [{:type_var, :a}, {:effect_var, :e}],
               {:function, {:type_var, :a}, {:effect_var, :e}, {:type_var, :a}}
             ) ==
               {:forall, [{:type_var, :a}, {:effect_var, :e}],
                {:function, {:type_var, :a}, {:effect_var, :e}, {:type_var, :a}}}
    end
  end

  describe "monomorphic?/1" do
    test "returns true for monomorphic types" do
      assert Core.monomorphic?(:int)
      assert Core.monomorphic?(:string)
      assert Core.monomorphic?(:bool)
      assert Core.monomorphic?({:effect_empty})
      assert Core.monomorphic?({:effect_label, :io})
    end

    test "returns false for types with type variables" do
      refute Core.monomorphic?({:type_var, :a})
      refute Core.monomorphic?({:effect_var, :e})
    end

    test "returns false for composite types containing variables" do
      refute Core.monomorphic?({:function, {:type_var, :a}, {:effect_empty}, :int})
      refute Core.monomorphic?({:function, :int, {:effect_var, :e}, :string})
      refute Core.monomorphic?({:tuple, [:int, {:type_var, :a}]})
      refute Core.monomorphic?({:list, {:type_var, :a}})
      refute Core.monomorphic?({:map, [{{:type_var, :k}, :int}]})
      refute Core.monomorphic?({:union, [:int, {:type_var, :a}]})
      refute Core.monomorphic?({:forall, [{:type_var, :a}], {:type_var, :a}})
      refute Core.monomorphic?({:effect_row, :io, {:effect_var, :e}})
    end

    test "returns true for composite types without variables" do
      assert Core.monomorphic?({:function, :int, {:effect_empty}, :string})
      assert Core.monomorphic?({:tuple, [:int, :string, :bool]})
      assert Core.monomorphic?({:list, :int})
      assert Core.monomorphic?({:map, [{:int, :string}]})
      assert Core.monomorphic?({:union, [:int, :string]})
      assert Core.monomorphic?({:effect_row, :io, {:effect_empty}})
    end
  end

  describe "free_variables/2" do
    test "finds free type variables" do
      assert Core.free_variables({:type_var, :a}) == MapSet.new([{:type_var, :a}])
      assert Core.free_variables({:type_var, :b}) == MapSet.new([{:type_var, :b}])
    end

    test "finds free effect variables" do
      assert Core.free_variables({:effect_var, :e}) == MapSet.new([{:effect_var, :e}])
    end

    test "returns empty set for primitive types" do
      assert Core.free_variables(:int) == MapSet.new()
      assert Core.free_variables(:string) == MapSet.new()
      assert Core.free_variables({:effect_empty}) == MapSet.new()
      assert Core.free_variables({:effect_label, :io}) == MapSet.new()
    end

    test "finds free variables in function types" do
      type = {:function, {:type_var, :a}, {:effect_var, :e}, {:type_var, :b}}
      vars = Core.free_variables(type)

      assert MapSet.member?(vars, {:type_var, :a})
      assert MapSet.member?(vars, {:type_var, :b})
      assert MapSet.member?(vars, {:effect_var, :e})
      assert MapSet.size(vars) == 3
    end

    test "finds free variables in tuple types" do
      type = {:tuple, [{:type_var, :a}, :int, {:type_var, :b}]}
      vars = Core.free_variables(type)

      assert MapSet.member?(vars, {:type_var, :a})
      assert MapSet.member?(vars, {:type_var, :b})
      assert MapSet.size(vars) == 2
    end

    test "finds free variables in list types" do
      type = {:list, {:type_var, :a}}
      vars = Core.free_variables(type)

      assert vars == MapSet.new([{:type_var, :a}])
    end

    test "finds free variables in map types" do
      type = {:map, [{{:type_var, :k}, {:type_var, :v}}]}
      vars = Core.free_variables(type)

      assert MapSet.member?(vars, {:type_var, :k})
      assert MapSet.member?(vars, {:type_var, :v})
      assert MapSet.size(vars) == 2
    end

    test "finds free variables in union types" do
      type = {:union, [{:type_var, :a}, :int, {:type_var, :b}]}
      vars = Core.free_variables(type)

      assert MapSet.member?(vars, {:type_var, :a})
      assert MapSet.member?(vars, {:type_var, :b})
      assert MapSet.size(vars) == 2
    end

    test "finds free variables in effect rows" do
      type = {:effect_row, :io, {:effect_var, :e}}
      vars = Core.free_variables(type)

      assert vars == MapSet.new([{:effect_var, :e}])
    end

    test "respects bound variables in forall" do
      # ∀a. a -> int (a is bound, so no free variables)
      type = {:forall, [{:type_var, :a}], {:function, {:type_var, :a}, {:effect_empty}, :int}}
      vars = Core.free_variables(type)

      assert vars == MapSet.new()
    end

    test "finds free variables not in forall binding" do
      # ∀a. a -> b (a is bound, b is free)
      type =
        {:forall, [{:type_var, :a}],
         {:function, {:type_var, :a}, {:effect_empty}, {:type_var, :b}}}

      vars = Core.free_variables(type)

      assert vars == MapSet.new([{:type_var, :b}])
    end

    test "handles nested forall with different bindings" do
      # ∀a. (a -> ∀b. b -> c) - only c is free
      type =
        {:forall, [{:type_var, :a}],
         {:function, {:type_var, :a}, {:effect_empty},
          {:forall, [{:type_var, :b}],
           {:function, {:type_var, :b}, {:effect_empty}, {:type_var, :c}}}}}

      vars = Core.free_variables(type)

      assert vars == MapSet.new([{:type_var, :c}])
    end

    test "handles forall with effect variables" do
      # ∀e. Int -> e String (e is bound)
      type = {:forall, [{:effect_var, :e}], {:function, :int, {:effect_var, :e}, :string}}
      vars = Core.free_variables(type)

      assert vars == MapSet.new()
    end

    test "respects pre-existing bound variables" do
      # With :a already bound, {:type_var, :a} should not be free
      bound = MapSet.new([:a])
      vars = Core.free_variables({:type_var, :a}, bound)

      assert vars == MapSet.new()
    end

    test "handles invalid variable types in forall bindings" do
      # Forall with an invalid var type (not {:type_var, _} or {:effect_var, _})
      # This tests the catch-all clause in the binding reduction
      type = {:forall, [:invalid_var_type], {:type_var, :a}}
      vars = Core.free_variables(type)

      # :a should still be free since :invalid_var_type doesn't bind anything
      assert vars == MapSet.new([{:type_var, :a}])
    end
  end

  describe "to_compact_effect/1" do
    test "converts empty effect to :p" do
      assert Core.to_compact_effect({:effect_empty}) == :p
    end

    test "converts nif effect to :n" do
      assert Core.to_compact_effect({:effect_label, :nif}) == :n
      assert Core.to_compact_effect({:effect_row, :nif, {:effect_label, :io}}) == :n
    end

    test "converts unknown effect to :u" do
      assert Core.to_compact_effect({:effect_unknown}) == :u
      assert Core.to_compact_effect({:effect_var, :e}) == :u
    end

    test "converts side effects to :s" do
      assert Core.to_compact_effect({:effect_label, :io}) == :s
      assert Core.to_compact_effect({:effect_label, :file}) == :s
      assert Core.to_compact_effect({:effect_label, :process}) == :s
      assert Core.to_compact_effect({:effect_label, :network}) == :s
      assert Core.to_compact_effect({:effect_label, :state}) == :s
      assert Core.to_compact_effect({:effect_label, :ets}) == :s
      assert Core.to_compact_effect({:effect_label, :time}) == :s
      assert Core.to_compact_effect({:effect_label, :random}) == :s
    end

    test "converts lambda effect to :l" do
      assert Core.to_compact_effect({:effect_label, :lambda}) == :l
    end

    test "converts dependent effect to :d" do
      assert Core.to_compact_effect({:effect_label, :dependent}) == :d
    end

    test "converts dependent effect with MFAs to {:d, [MFA list]}" do
      assert Core.to_compact_effect({:d, ["System.get_env/1"]}) == {:d, ["System.get_env/1"]}

      assert Core.to_compact_effect({:d, ["System.get_env/1", "Process.get/1"]}) ==
               {:d, ["System.get_env/1", "Process.get/1"]}
    end

    test "converts side effect with MFAs to {:s, [MFA list]}" do
      assert Core.to_compact_effect({:s, ["File.read/1"]}) == {:s, ["File.read/1"]}

      assert Core.to_compact_effect({:s, ["File.read/1", "IO.puts/1"]}) ==
               {:s, ["File.read/1", "IO.puts/1"]}
    end

    test "converts pure exception to exception tuple" do
      assert Core.to_compact_effect({:effect_label, :exn}) == {:e, [:exn]}
    end

    test "converts mixed exception with side effects to :s" do
      # Exception mixed with IO
      assert Core.to_compact_effect({:effect_row, :exn, {:effect_label, :io}}) == :s
      # IO mixed with exception
      assert Core.to_compact_effect({:effect_row, :io, {:effect_label, :exn}}) == :s
    end

    test "handles complex effect rows" do
      # Multiple side effects
      effect = {:effect_row, :io, {:effect_row, :file, {:effect_label, :network}}}
      assert Core.to_compact_effect(effect) == :s

      # Pure
      assert Core.to_compact_effect({:effect_empty}) == :p
    end

    test "handles unknown/invalid effects gracefully" do
      # Invalid effect structure defaults to :u
      assert Core.to_compact_effect({:some_unknown_effect}) == :u
    end

    test "handles mixed exception with other effects" do
      # Exception mixed with IO - should return :s
      effect = {:effect_row, :exn, {:effect_label, :io}}
      assert Core.to_compact_effect(effect) == :s

      # IO mixed with exception - should also return :s
      effect2 = {:effect_row, :io, {:effect_label, :exn}}
      assert Core.to_compact_effect(effect2) == :s
    end

    test "handles edge case with unknown label types in effect" do
      # An effect with a custom/unrecognized label (not in the standard set)
      # This should hit the default true branch
      effect = {:effect_label, :custom_unknown_label}
      assert Core.to_compact_effect(effect) == :s
    end
  end

  describe "extract_effect_labels/1" do
    test "extracts label from empty effect" do
      assert Core.extract_effect_labels({:effect_empty}) == []
    end

    test "extracts label from single effect" do
      assert Core.extract_effect_labels({:effect_label, :io}) == [:io]
      assert Core.extract_effect_labels({:effect_label, :exn}) == [:exn]
    end

    test "extracts side effect with MFAs" do
      assert Core.extract_effect_labels({:s, ["File.read/1"]}) == [{:s, ["File.read/1"]}]

      assert Core.extract_effect_labels({:s, ["File.read/1", "IO.puts/1"]}) ==
               [{:s, ["File.read/1", "IO.puts/1"]}]
    end

    test "extracts dependent effect with MFAs" do
      assert Core.extract_effect_labels({:d, ["System.get_env/1"]}) == [
               {:d, ["System.get_env/1"]}
             ]

      assert Core.extract_effect_labels({:d, ["System.get_env/1", "Process.get/1"]}) ==
               [{:d, ["System.get_env/1", "Process.get/1"]}]
    end

    test "extracts labels from effect row" do
      effect = {:effect_row, :io, {:effect_label, :file}}
      assert Core.extract_effect_labels(effect) == [:io, :file]

      effect = {:effect_row, :io, {:effect_row, :file, {:effect_label, :network}}}
      assert Core.extract_effect_labels(effect) == [:io, :file, :network]
    end

    test "treats effect variables as unknown" do
      assert Core.extract_effect_labels({:effect_var, :e}) == [:unknown]
    end

    test "treats effect unknown as unknown" do
      assert Core.extract_effect_labels({:effect_unknown}) == [:unknown]
    end

    test "handles unknown effect structures" do
      assert Core.extract_effect_labels({:invalid_effect}) == [:unknown]
      assert Core.extract_effect_labels(:atom) == [:unknown]
    end
  end
end
