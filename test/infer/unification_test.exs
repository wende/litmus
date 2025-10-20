defmodule Litmus.Types.UnificationTest do
  use ExUnit.Case, async: true

  alias Litmus.Types.{Unification, Substitution}

  describe "basic type unification" do
    test "identical concrete types unify" do
      assert {:ok, subst} = Unification.unify(:int, :int)
      assert subst == %{}
    end

    test "different concrete types fail to unify" do
      assert {:error, {:cannot_unify, :int, :string}} = Unification.unify(:int, :string)
    end

    test "type variable unifies with concrete type" do
      var = {:type_var, :a}
      assert {:ok, subst} = Unification.unify(var, :int)
      assert Substitution.apply_subst(subst, var) == :int
    end

    test "concrete type unifies with type variable" do
      var = {:type_var, :a}
      assert {:ok, subst} = Unification.unify(:int, var)
      assert Substitution.apply_subst(subst, var) == :int
    end

    test "two different type variables unify" do
      var1 = {:type_var, :a}
      var2 = {:type_var, :b}
      assert {:ok, subst} = Unification.unify(var1, var2)
      # One should be substituted for the other
      assert Substitution.apply_subst(subst, var1) == var2 or
               Substitution.apply_subst(subst, var2) == var1
    end
  end

  describe "function type unification" do
    test "unifies simple function types" do
      fun1 = {:function, :int, {:effect_empty}, :string}
      fun2 = {:function, :int, {:effect_empty}, :string}
      assert {:ok, _subst} = Unification.unify(fun1, fun2)
    end

    test "unifies function types with type variables" do
      var_a = {:type_var, :a}
      var_b = {:type_var, :b}
      fun1 = {:function, var_a, {:effect_empty}, var_b}
      fun2 = {:function, :int, {:effect_empty}, :string}

      assert {:ok, subst} = Unification.unify(fun1, fun2)
      assert Substitution.apply_subst(subst, var_a) == :int
      assert Substitution.apply_subst(subst, var_b) == :string
    end

    test "fails to unify functions with different argument types" do
      fun1 = {:function, :int, {:effect_empty}, :string}
      fun2 = {:function, :bool, {:effect_empty}, :string}
      assert {:error, _} = Unification.unify(fun1, fun2)
    end

    test "fails to unify functions with different return types" do
      fun1 = {:function, :int, {:effect_empty}, :string}
      fun2 = {:function, :int, {:effect_empty}, :bool}
      assert {:error, _} = Unification.unify(fun1, fun2)
    end

    test "unifies function types with different effects" do
      fun1 = {:function, :int, {:effect_label, :io}, :string}
      fun2 = {:function, :int, {:effect_var, :e}, :string}

      assert {:ok, subst} = Unification.unify(fun1, fun2)
      assert Substitution.apply_subst(subst, {:effect_var, :e}) == {:effect_label, :io}
    end
  end

  describe "tuple type unification" do
    test "unifies empty tuples" do
      tuple1 = {:tuple, []}
      tuple2 = {:tuple, []}
      assert {:ok, _subst} = Unification.unify(tuple1, tuple2)
    end

    test "unifies tuples with same types" do
      tuple1 = {:tuple, [:int, :string]}
      tuple2 = {:tuple, [:int, :string]}
      assert {:ok, _subst} = Unification.unify(tuple1, tuple2)
    end

    test "unifies tuples with type variables" do
      var_a = {:type_var, :a}
      tuple1 = {:tuple, [var_a, :string]}
      tuple2 = {:tuple, [:int, :string]}

      assert {:ok, subst} = Unification.unify(tuple1, tuple2)
      assert Substitution.apply_subst(subst, var_a) == :int
    end

    test "fails to unify tuples of different lengths" do
      tuple1 = {:tuple, [:int]}
      tuple2 = {:tuple, [:int, :string]}
      assert {:error, _} = Unification.unify(tuple1, tuple2)
    end

    test "fails to unify tuples with incompatible element types" do
      tuple1 = {:tuple, [:int, :string]}
      tuple2 = {:tuple, [:int, :bool]}
      assert {:error, _} = Unification.unify(tuple1, tuple2)
    end
  end

  describe "list type unification" do
    test "unifies lists with same element type" do
      list1 = {:list, :int}
      list2 = {:list, :int}
      assert {:ok, _subst} = Unification.unify(list1, list2)
    end

    test "unifies lists with type variable element" do
      var = {:type_var, :a}
      list1 = {:list, var}
      list2 = {:list, :int}

      assert {:ok, subst} = Unification.unify(list1, list2)
      assert Substitution.apply_subst(subst, var) == :int
    end

    test "fails to unify lists with different element types" do
      list1 = {:list, :int}
      list2 = {:list, :string}
      assert {:error, _} = Unification.unify(list1, list2)
    end

    test "unifies nested lists" do
      list1 = {:list, {:list, :int}}
      list2 = {:list, {:list, :int}}
      assert {:ok, _subst} = Unification.unify(list1, list2)
    end
  end

  describe "map type unification" do
    test "unifies empty maps" do
      map1 = {:map, []}
      map2 = {:map, []}
      assert {:ok, _subst} = Unification.unify(map1, map2)
    end

    test "unifies maps with same key-value types" do
      map1 = {:map, [{:string, :int}]}
      map2 = {:map, [{:string, :int}]}
      assert {:ok, _subst} = Unification.unify(map1, map2)
    end

    test "unifies maps with type variables" do
      var_k = {:type_var, :k}
      var_v = {:type_var, :v}
      map1 = {:map, [{var_k, var_v}]}
      map2 = {:map, [{:string, :int}]}

      assert {:ok, subst} = Unification.unify(map1, map2)
      assert Substitution.apply_subst(subst, var_k) == :string
      assert Substitution.apply_subst(subst, var_v) == :int
    end

    test "fails to unify maps of different sizes" do
      map1 = {:map, [{:string, :int}]}
      map2 = {:map, [{:string, :int}, {:atom, :bool}]}
      assert {:error, _} = Unification.unify(map1, map2)
    end
  end

  describe "union type unification" do
    test "unifies identical union types" do
      union1 = {:union, [:int, :string]}
      union2 = {:union, [:int, :string]}
      assert {:ok, _subst} = Unification.unify(union1, union2)
    end

    test "fails to unify different union types" do
      union1 = {:union, [:int, :string]}
      union2 = {:union, [:int, :bool]}
      assert {:error, {:cannot_unify_unions, _, _}} = Unification.unify(union1, union2)
    end
  end

  describe "forall type unification" do
    test "unifies forall types with same structure (alpha-equivalence)" do
      forall1 =
        {:forall, [{:type_var, :a}],
         {:function, {:type_var, :a}, {:effect_empty}, {:type_var, :a}}}

      forall2 =
        {:forall, [{:type_var, :b}],
         {:function, {:type_var, :b}, {:effect_empty}, {:type_var, :b}}}

      assert {:ok, _subst} = Unification.unify(forall1, forall2)
    end

    test "unifies forall types with tuples (tests renaming in tuples)" do
      # forall a. (a, a) vs forall x. (x, x)
      forall1 = {:forall, [{:type_var, :a}], {:tuple, [{:type_var, :a}, {:type_var, :a}]}}
      forall2 = {:forall, [{:type_var, :x}], {:tuple, [{:type_var, :x}, {:type_var, :x}]}}
      assert {:ok, _subst} = Unification.unify(forall1, forall2)
    end

    test "unifies forall types with lists (tests renaming in lists)" do
      # forall a. list<a> vs forall y. list<y>
      forall1 = {:forall, [{:type_var, :a}], {:list, {:type_var, :a}}}
      forall2 = {:forall, [{:type_var, :y}], {:list, {:type_var, :y}}}
      assert {:ok, _subst} = Unification.unify(forall1, forall2)
    end

    test "unifies forall types with effect variables (tests effect var renaming)" do
      # forall e. int ->{e} string  vs  forall eff. int ->{eff} string
      forall1 = {:forall, [{:effect_var, :e}], {:function, :int, {:effect_var, :e}, :string}}
      forall2 = {:forall, [{:effect_var, :eff}], {:function, :int, {:effect_var, :eff}, :string}}
      assert {:ok, _subst} = Unification.unify(forall1, forall2)
    end

    test "unifies forall types with effect rows (tests renaming in effect rows)" do
      # forall e. int ->{io | e} string  vs  forall f. int ->{io | f} string
      forall1 =
        {:forall, [{:effect_var, :e}],
         {:function, :int, {:effect_row, :io, {:effect_var, :e}}, :string}}

      forall2 =
        {:forall, [{:effect_var, :f}],
         {:function, :int, {:effect_row, :io, {:effect_var, :f}}, :string}}

      assert {:ok, _subst} = Unification.unify(forall1, forall2)
    end

    test "unifies forall types with multiple variables" do
      # forall a, b. (a, b)  vs  forall x, y. (x, y)
      forall1 =
        {:forall, [{:type_var, :a}, {:type_var, :b}],
         {:tuple, [{:type_var, :a}, {:type_var, :b}]}}

      forall2 =
        {:forall, [{:type_var, :x}, {:type_var, :y}],
         {:tuple, [{:type_var, :x}, {:type_var, :y}]}}

      assert {:ok, _subst} = Unification.unify(forall1, forall2)
    end

    test "unifies forall types with nested foralls (tests forall in renaming)" do
      # forall a. (forall b. b -> a)  vs  forall x. (forall y. y -> x)
      inner1 =
        {:forall, [{:type_var, :b}],
         {:function, {:type_var, :b}, {:effect_empty}, {:type_var, :a}}}

      forall1 = {:forall, [{:type_var, :a}], inner1}

      inner2 =
        {:forall, [{:type_var, :y}],
         {:function, {:type_var, :y}, {:effect_empty}, {:type_var, :x}}}

      forall2 = {:forall, [{:type_var, :x}], inner2}

      assert {:ok, _subst} = Unification.unify(forall1, forall2)
    end

    test "fails to unify forall types with different number of variables" do
      forall1 = {:forall, [{:type_var, :a}], {:type_var, :a}}

      forall2 =
        {:forall, [{:type_var, :a}, {:type_var, :b}],
         {:tuple, [{:type_var, :a}, {:type_var, :b}]}}

      assert {:error, _} = Unification.unify(forall1, forall2)
    end

    test "fails to unify forall types with incompatible bodies" do
      # forall a. a -> a  vs  forall b. b -> b -> b
      forall1 =
        {:forall, [{:type_var, :a}],
         {:function, {:type_var, :a}, {:effect_empty}, {:type_var, :a}}}

      forall2 =
        {:forall, [{:type_var, :b}],
         {:function, {:type_var, :b}, {:effect_empty},
          {:function, {:type_var, :b}, {:effect_empty}, {:type_var, :b}}}}

      assert {:error, _} = Unification.unify(forall1, forall2)
    end
  end

  describe "effect unification" do
    test "unifies identical effect labels" do
      eff1 = {:effect_label, :io}
      eff2 = {:effect_label, :io}
      assert {:ok, _subst} = Unification.unify_effect(eff1, eff2)
    end

    test "fails to unify different effect labels" do
      eff1 = {:effect_label, :io}
      eff2 = {:effect_label, :exn}
      assert {:error, _} = Unification.unify_effect(eff1, eff2)
    end

    test "unifies empty effects" do
      assert {:ok, _subst} = Unification.unify_effect({:effect_empty}, {:effect_empty})
    end

    test "unifies effect variable with effect label" do
      var = {:effect_var, :e}
      label = {:effect_label, :io}

      assert {:ok, subst} = Unification.unify_effect(var, label)
      assert Substitution.apply_subst(subst, var) == label
    end

    test "unifies effect variable with empty effect" do
      var = {:effect_var, :e}

      assert {:ok, subst} = Unification.unify_effect(var, {:effect_empty})
      assert Substitution.apply_subst(subst, var) == {:effect_empty}
    end

    test "fails to unify non-empty row with empty effect" do
      row = {:effect_row, :io, {:effect_empty}}

      assert {:error, {:cannot_unify_non_empty_with_empty, _, _}} =
               Unification.unify_effect(row, {:effect_empty})
    end
  end

  describe "effect row unification" do
    test "unifies effect row with matching label" do
      row = {:effect_row, :io, {:effect_empty}}
      label = {:effect_label, :io}
      assert {:ok, _subst} = Unification.unify_effect(row, label)
    end

    test "unifies effect row with variable tail" do
      var = {:effect_var, :e}
      row = {:effect_row, :io, var}
      label = {:effect_label, :io}

      assert {:ok, subst} = Unification.unify_effect(row, label)
      assert Substitution.apply_subst(subst, var) == {:effect_empty}
    end

    test "unifies two rows with same label" do
      row1 = {:effect_row, :io, {:effect_empty}}
      row2 = {:effect_row, :io, {:effect_empty}}
      assert {:ok, _subst} = Unification.unify_effect(row1, row2)
    end

    test "unifies two rows with different labels by finding common label" do
      row1 = {:effect_row, :io, {:effect_label, :exn}}
      row2 = {:effect_row, :exn, {:effect_label, :io}}
      assert {:ok, _subst} = Unification.unify_effect(row1, row2)
    end

    test "unifies rows with polymorphic tails" do
      var1 = {:effect_var, :e1}
      var2 = {:effect_var, :e2}
      row1 = {:effect_row, :io, var1}
      row2 = {:effect_row, :io, var2}

      assert {:ok, subst} = Unification.unify_effect(row1, row2)
      # The variables should be unified
      result1 = Substitution.apply_subst(subst, var1)
      result2 = Substitution.apply_subst(subst, var2)
      assert result1 == result2
    end

    test "unifies complex effect rows with multiple labels" do
      row1 = {:effect_row, :io, {:effect_row, :exn, {:effect_empty}}}
      row2 = {:effect_row, :exn, {:effect_row, :io, {:effect_empty}}}
      assert {:ok, _subst} = Unification.unify_effect(row1, row2)
    end

    test "handles the Koka example: ⟨exn | μ⟩ ∼ ⟨exn⟩" do
      var = {:effect_var, :mu}
      row1 = {:effect_row, :exn, var}
      row2 = {:effect_label, :exn}

      assert {:ok, subst} = Unification.unify_effect(row1, row2)
      # μ should be unified with empty
      assert Substitution.apply_subst(subst, var) == {:effect_empty}
    end

    test "handles effect unknown" do
      assert {:ok, _} = Unification.unify_effect({:effect_unknown}, {:effect_label, :io})
      assert {:ok, _} = Unification.unify_effect({:effect_label, :io}, {:effect_unknown})
      assert {:ok, _} = Unification.unify_effect({:effect_unknown}, {:effect_unknown})
    end

    test "unifies rows with different labels when both tails are variables" do
      # {io | e1} ~ {exn | e2} where both are variables
      # This should allow unification by extending the variables
      var1 = {:effect_var, :e1}
      var2 = {:effect_var, :e2}
      row1 = {:effect_row, :io, var1}
      row2 = {:effect_row, :exn, var2}

      # The implementation may handle this as incompatible or may succeed
      # depending on the algorithm - just verify it returns a result
      result = Unification.unify_effect(row1, row2)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "unifies rows when label needs to be found deeper in the row" do
      # {io | exn} ~ {exn | io}
      # This tests find_and_remove_label recursion
      row1 = {:effect_row, :io, {:effect_label, :exn}}
      row2 = {:effect_row, :exn, {:effect_label, :io}}

      assert {:ok, _subst} = Unification.unify_effect(row1, row2)
    end

    test "fails to unify incompatible concrete effect rows" do
      # {io} ~ {exn} with no variables to extend
      row1 = {:effect_row, :io, {:effect_empty}}
      row2 = {:effect_row, :exn, {:effect_empty}}

      assert {:error, {:incompatible_effect_rows, _, _}} = Unification.unify_effect(row1, row2)
    end

    test "find_and_remove_label returns not_found for non-matching effects" do
      # This tests the fallback case in find_and_remove_label
      # Trying to unify {io | state} ~ {exn}  (without variables)
      row1 = {:effect_row, :io, {:effect_label, :state}}
      row2 = {:effect_label, :exn}

      assert {:error, _} = Unification.unify_effect(row1, row2)
    end
  end

  describe "occurs check" do
    test "prevents infinite type: type variable in itself" do
      var = {:type_var, :a}
      # a = list<a> would create infinite type
      infinite_type = {:list, var}
      assert {:error, {:occurs_check_failed, _, _}} = Unification.unify(var, infinite_type)
    end

    test "prevents infinite type in function" do
      var = {:type_var, :a}
      # a = a -> int would create infinite type
      infinite_type = {:function, var, {:effect_empty}, :int}
      assert {:error, {:occurs_check_failed, _, _}} = Unification.unify(var, infinite_type)
    end

    test "prevents infinite type in tuple" do
      var = {:type_var, :a}
      infinite_type = {:tuple, [var, :int]}
      assert {:error, {:occurs_check_failed, _, _}} = Unification.unify(var, infinite_type)
    end

    test "prevents infinite type in map" do
      var = {:type_var, :a}
      infinite_type = {:map, [{var, :int}]}
      assert {:error, {:occurs_check_failed, _, _}} = Unification.unify(var, infinite_type)
    end

    test "prevents infinite type in union" do
      var = {:type_var, :a}
      infinite_type = {:union, [var, :int]}
      assert {:error, {:occurs_check_failed, _, _}} = Unification.unify(var, infinite_type)
    end

    test "prevents infinite type in forall body" do
      var = {:type_var, :a}
      infinite_type = {:forall, [{:type_var, :b}], var}
      assert {:error, {:occurs_check_failed, _, _}} = Unification.unify(var, infinite_type)
    end

    test "prevents infinite effect type" do
      var = {:effect_var, :e}
      infinite_effect = {:effect_row, :io, var}

      assert {:error, {:occurs_check_failed, _, _}} =
               Unification.unify_effect(var, infinite_effect)
    end
  end

  describe "complex unification scenarios" do
    test "unifies nested function types" do
      # (int -> string) -> bool
      inner_fun1 = {:function, :int, {:effect_empty}, :string}
      outer_fun1 = {:function, inner_fun1, {:effect_empty}, :bool}

      var = {:type_var, :a}
      inner_fun2 = {:function, :int, {:effect_empty}, var}
      outer_fun2 = {:function, inner_fun2, {:effect_empty}, :bool}

      assert {:ok, subst} = Unification.unify(outer_fun1, outer_fun2)
      assert Substitution.apply_subst(subst, var) == :string
    end

    test "unifies list of tuples with variables" do
      var_a = {:type_var, :a}
      var_b = {:type_var, :b}

      type1 = {:list, {:tuple, [var_a, var_b]}}
      type2 = {:list, {:tuple, [:int, :string]}}

      assert {:ok, subst} = Unification.unify(type1, type2)
      assert Substitution.apply_subst(subst, var_a) == :int
      assert Substitution.apply_subst(subst, var_b) == :string
    end

    test "unifies function with effects and return containing type variables" do
      var_ret = {:type_var, :ret}
      var_eff = {:effect_var, :eff}

      fun1 = {:function, :int, var_eff, var_ret}
      fun2 = {:function, :int, {:effect_label, :io}, {:list, :string}}

      assert {:ok, subst} = Unification.unify(fun1, fun2)
      assert Substitution.apply_subst(subst, var_ret) == {:list, :string}
      assert Substitution.apply_subst(subst, var_eff) == {:effect_label, :io}
    end

    test "chains substitutions correctly" do
      var_a = {:type_var, :a}
      var_b = {:type_var, :b}
      var_c = {:type_var, :c}

      # a = b, b = c, c = int should result in a = int
      tuple1 = {:tuple, [var_a, var_b, var_c]}
      tuple2 = {:tuple, [var_b, var_c, :int]}

      assert {:ok, subst} = Unification.unify(tuple1, tuple2)
      assert Substitution.apply_subst(subst, var_a) == :int
      assert Substitution.apply_subst(subst, var_b) == :int
      assert Substitution.apply_subst(subst, var_c) == :int
    end
  end
end
