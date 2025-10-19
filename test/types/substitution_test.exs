defmodule Litmus.Types.SubstitutionTest do
  use ExUnit.Case, async: true

  alias Litmus.Types.Substitution

  describe "apply_subst/2 with complex types" do
    test "applies substitution to map types" do
      subst = %{{:type_var, :k} => :atom, {:type_var, :v} => :string}
      map_type = {:map, [{{:type_var, :k}, {:type_var, :v}}]}

      result = Substitution.apply_subst(subst, map_type)

      assert result == {:map, [{:atom, :string}]}
    end

    test "applies substitution to union types" do
      subst = %{{:type_var, :a} => :int}
      union_type = {:union, [{:type_var, :a}, :string, :bool]}

      result = Substitution.apply_subst(subst, union_type)

      assert result == {:union, [:int, :string, :bool]}
    end

    test "applies substitution to nested map with multiple variables" do
      subst = %{
        {:type_var, :k1} => :atom,
        {:type_var, :v1} => {:list, :int},
        {:type_var, :k2} => :string
      }

      map_type = {:map, [
        {{:type_var, :k1}, {:type_var, :v1}},
        {{:type_var, :k2}, :bool}
      ]}

      result = Substitution.apply_subst(subst, map_type)

      assert result == {:map, [
        {:atom, {:list, :int}},
        {:string, :bool}
      ]}
    end

    test "applies substitution to complex nested unions" do
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => {:list, :string}
      }

      union_type = {:union, [
        {:type_var, :a},
        {:tuple, [{:type_var, :b}, :bool]},
        {:type_var, :b}
      ]}

      result = Substitution.apply_subst(subst, union_type)

      assert result == {:union, [
        :int,
        {:tuple, [{:list, :string}, :bool]},
        {:list, :string}
      ]}
    end
  end

  describe "apply_to_env/2" do
    test "applies substitution to empty environment" do
      subst = %{{:type_var, :a} => :int}
      env = %{}

      result = Substitution.apply_to_env(subst, env)

      assert result == %{}
    end

    test "applies substitution to environment with multiple bindings" do
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string
      }

      env = %{
        x: {:type_var, :a},
        y: {:list, {:type_var, :b}},
        z: :bool
      }

      result = Substitution.apply_to_env(subst, env)

      assert result == %{
        x: :int,
        y: {:list, :string},
        z: :bool
      }
    end

    test "returns environment unchanged when substitution is empty" do
      subst = Substitution.empty()
      env = %{x: {:type_var, :a}, y: :int}

      result = Substitution.apply_to_env(subst, env)

      assert result == env
    end

    test "handles complex function types in environment" do
      subst = %{
        {:type_var, :a} => :int,
        {:effect_var, :e} => {:effect_label, :io}
      }

      env = %{
        f: {:function, {:type_var, :a}, {:effect_var, :e}, :string}
      }

      result = Substitution.apply_to_env(subst, env)

      assert result == %{
        f: {:function, :int, {:effect_label, :io}, :string}
      }
    end
  end

  describe "restrict/2 and remove/2" do
    test "restrict keeps only specified variables" do
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string,
        {:type_var, :c} => :bool
      }

      vars = MapSet.new([{:type_var, :a}, {:type_var, :c}])
      result = Substitution.restrict(subst, vars)

      assert result == %{
        {:type_var, :a} => :int,
        {:type_var, :c} => :bool
      }
    end

    test "restrict returns empty when no variables match" do
      subst = %{{:type_var, :a} => :int}
      vars = MapSet.new([{:type_var, :b}])

      result = Substitution.restrict(subst, vars)

      assert result == %{}
    end

    test "remove excludes specified variables" do
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string,
        {:type_var, :c} => :bool
      }

      vars = MapSet.new([{:type_var, :b}])
      result = Substitution.remove(subst, vars)

      assert result == %{
        {:type_var, :a} => :int,
        {:type_var, :c} => :bool
      }
    end

    test "remove returns original substitution when no variables match" do
      subst = %{{:type_var, :a} => :int}
      vars = MapSet.new([{:type_var, :b}])

      result = Substitution.remove(subst, vars)

      assert result == subst
    end
  end

  describe "domain/1 and range_vars/1" do
    test "domain returns all variables in the substitution" do
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string,
        {:effect_var, :e} => {:effect_label, :io}
      }

      domain = Substitution.domain(subst)

      assert MapSet.equal?(domain, MapSet.new([
        {:type_var, :a},
        {:type_var, :b},
        {:effect_var, :e}
      ]))
    end

    test "range_vars returns all free variables in the range" do
      subst = %{
        {:type_var, :a} => {:type_var, :b},
        {:type_var, :c} => {:list, {:type_var, :d}}
      }

      range_vars = Substitution.range_vars(subst)

      assert MapSet.equal?(range_vars, MapSet.new([
        {:type_var, :b},
        {:type_var, :d}
      ]))
    end

    test "range_vars returns empty set for concrete types" do
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string
      }

      range_vars = Substitution.range_vars(subst)

      assert MapSet.equal?(range_vars, MapSet.new())
    end

    test "range_vars handles complex nested types" do
      subst = %{
        {:type_var, :a} => {:function, {:type_var, :x}, {:effect_var, :e}, {:type_var, :y}}
      }

      range_vars = Substitution.range_vars(subst)

      assert MapSet.member?(range_vars, {:type_var, :x})
      assert MapSet.member?(range_vars, {:type_var, :y})
      assert MapSet.member?(range_vars, {:effect_var, :e})
    end
  end

  describe "idempotent?/1 and make_idempotent/1" do
    test "idempotent? returns true when domain and range are disjoint" do
      # a -> Int, b -> String (idempotent)
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string
      }

      assert Substitution.idempotent?(subst)
    end

    test "idempotent? returns false when domain variable appears in range" do
      # a -> b, b -> Int (not idempotent, a appears in domain and b in range)
      subst = %{
        {:type_var, :a} => {:type_var, :b},
        {:type_var, :b} => :int
      }

      refute Substitution.idempotent?(subst)
    end

    test "make_idempotent fixes non-idempotent substitution" do
      # a -> b, b -> c, c -> Int
      subst = %{
        {:type_var, :a} => {:type_var, :b},
        {:type_var, :b} => {:type_var, :c},
        {:type_var, :c} => :int
      }

      result = Substitution.make_idempotent(subst)

      # Should resolve to: a -> Int, b -> Int, c -> Int
      assert result == %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :int,
        {:type_var, :c} => :int
      }

      assert Substitution.idempotent?(result)
    end

    test "make_idempotent returns unchanged for already idempotent substitution" do
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string
      }

      result = Substitution.make_idempotent(subst)

      assert result == subst
    end

    test "make_idempotent handles complex chains" do
      # a -> List[b], b -> c, c -> Int
      subst = %{
        {:type_var, :a} => {:list, {:type_var, :b}},
        {:type_var, :b} => {:type_var, :c},
        {:type_var, :c} => :int
      }

      result = Substitution.make_idempotent(subst)

      assert result == %{
        {:type_var, :a} => {:list, :int},
        {:type_var, :b} => :int,
        {:type_var, :c} => :int
      }
    end
  end

  describe "format/1" do
    test "formats empty substitution" do
      assert Substitution.format(%{}) == "∅"
    end

    test "formats single substitution" do
      subst = %{{:type_var, :a} => :int}
      result = Substitution.format(subst)

      assert result =~ "a"
      assert result =~ "Int"
      assert result =~ "↦"
    end

    test "formats multiple substitutions" do
      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string
      }

      result = Substitution.format(subst)

      assert result =~ "a"
      assert result =~ "b"
      assert result =~ "Int"
      assert result =~ "String"
    end

    test "formats effect variable substitutions" do
      subst = %{
        {:effect_var, :e} => {:effect_label, :io}
      }

      result = Substitution.format(subst)

      assert result =~ "e"
      assert result =~ "io"
    end
  end

  describe "integration: realistic type inference scenarios" do
    test "unifying function types with polymorphic variables" do
      # Simulating: infer type of (fn x -> x end)
      # We want: ∀a. a -> a
      # Start with: a -> b, then unify to get b = a

      subst = Substitution.empty()
      |> Substitution.add({:type_var, :b}, {:type_var, :a})

      function_type = {:function, {:type_var, :a}, {:effect_empty}, {:type_var, :b}}
      result = Substitution.apply_subst(subst, function_type)

      assert result == {:function, {:type_var, :a}, {:effect_empty}, {:type_var, :a}}
    end

    test "composing substitutions from multiple unification steps" do
      # Step 1: infer a = Int
      s1 = %{{:type_var, :a} => :int}

      # Step 2: infer b = List[a]
      s2 = %{{:type_var, :b} => {:list, {:type_var, :a}}}

      # Compose them
      result = Substitution.compose(s2, s1)

      # Should give us: a -> Int, b -> List[Int]
      assert result[{:type_var, :a}] == :int
      assert result[{:type_var, :b}] == {:list, :int}
    end

    test "environment evolution through function application" do
      # Environment: {x: a, y: List[b]}
      # Substitution from inference: a -> Int, b -> String

      env = %{
        x: {:type_var, :a},
        y: {:list, {:type_var, :b}}
      }

      subst = %{
        {:type_var, :a} => :int,
        {:type_var, :b} => :string
      }

      result = Substitution.apply_to_env(subst, env)

      assert result == %{
        x: :int,
        y: {:list, :string}
      }
    end

    test "handling forall types with bound variables" do
      # ∀a. a -> Int, but we have a substitution for outer 'a'
      # The bound 'a' should not be substituted

      subst = %{{:type_var, :a} => :string}

      forall_type = {:forall, [{:type_var, :a}],
                     {:function, {:type_var, :a}, {:effect_empty}, :int}}

      result = Substitution.apply_subst(subst, forall_type)

      # The inner 'a' should remain unchanged (it's bound)
      assert result == {:forall, [{:type_var, :a}],
                        {:function, {:type_var, :a}, {:effect_empty}, :int}}
    end
  end
end
