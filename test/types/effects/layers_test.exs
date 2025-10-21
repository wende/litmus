defmodule Litmus.Types.Effects.LayersTest do
  use ExUnit.Case, async: true
  doctest Litmus.Types.Effects.Layers

  alias Litmus.Types.Effects.Layers

  describe "precedence/1 - correct severity ordering" do
    test "pure has lowest precedence (1)" do
      assert Layers.precedence(:p) == 1
    end

    test "lambda has precedence 2" do
      assert Layers.precedence(:l) == 2
    end

    test "exception has precedence 3" do
      assert Layers.precedence(:exn) == 3
      assert Layers.precedence({:e, ["Elixir.ArgumentError"]}) == 3
      assert Layers.precedence({:e, [:dynamic]}) == 3
    end

    test "dependent has precedence 4" do
      assert Layers.precedence(:d) == 4
    end

    test "side effects has precedence 5" do
      assert Layers.precedence(:s) == 5
    end

    test "nif has precedence 6" do
      assert Layers.precedence(:n) == 6
    end

    test "unknown has highest precedence (7)" do
      assert Layers.precedence(:u) == 7
    end

    test "nil has precedence 0" do
      assert Layers.precedence(nil) == 0
    end
  end

  describe "precedence/1 - ordering relationships" do
    test "pure < lambda" do
      assert Layers.precedence(:p) < Layers.precedence(:l)
    end

    test "lambda < exception" do
      assert Layers.precedence(:l) < Layers.precedence(:exn)
    end

    test "exception < dependent" do
      assert Layers.precedence(:exn) < Layers.precedence(:d)
    end

    test "dependent < side effects" do
      assert Layers.precedence(:d) < Layers.precedence(:s)
    end

    test "side effects < nif" do
      assert Layers.precedence(:s) < Layers.precedence(:n)
    end

    test "nif < unknown" do
      assert Layers.precedence(:n) < Layers.precedence(:u)
    end

    test "unknown is most severe (highest precedence)" do
      all_effects = [:p, :exn, {:e, []}, :l, :d, :s, :n, :u]
      assert :u == Enum.max_by(all_effects, &Layers.precedence/1)
    end

    test "pure is least severe (lowest precedence)" do
      all_effects = [:p, :exn, {:e, []}, :l, :d, :s, :n, :u]
      assert :p == Enum.min_by(all_effects, &Layers.precedence/1)
    end
  end

  describe "combine/2 - always picks more severe effect" do
    test "combines pure with anything -> returns that thing" do
      assert Layers.combine(:p, :s) == :s
      assert Layers.combine(:s, :p) == :s
      assert Layers.combine(:p, :exn) == :exn
      assert Layers.combine(:p, :l) == :l
      assert Layers.combine(:p, :d) == :d
      assert Layers.combine(:p, :n) == :n
      assert Layers.combine(:p, :u) == :u
    end

    test "combines unknown with anything -> returns unknown" do
      assert Layers.combine(:u, :p) == :u
      assert Layers.combine(:u, :exn) == :u
      assert Layers.combine(:u, :l) == :u
      assert Layers.combine(:u, :d) == :u
      assert Layers.combine(:u, :s) == :u
      assert Layers.combine(:u, :n) == :u
      assert Layers.combine(:s, :u) == :u
    end

    test "combines lambda with exception -> returns exception" do
      assert Layers.combine(:l, :exn) == :exn
      assert Layers.combine(:exn, :l) == :exn
    end

    test "combines exception with dependent -> returns dependent" do
      assert Layers.combine(:exn, :d) == :d
      assert Layers.combine(:d, :exn) == :d
    end

    test "combines exception with side effects -> returns side effects" do
      assert Layers.combine(:exn, :s) == :s
      assert Layers.combine(:s, :exn) == :s
    end

    test "combines dependent with side effects -> returns side effects" do
      assert Layers.combine(:d, :s) == :s
      assert Layers.combine(:s, :d) == :s
    end

    test "combines side effects with nif -> returns nif" do
      assert Layers.combine(:s, :n) == :n
      assert Layers.combine(:n, :s) == :n
    end

    test "combines nif with unknown -> returns unknown" do
      assert Layers.combine(:n, :u) == :u
      assert Layers.combine(:u, :n) == :u
    end

    test "combines same effect -> returns that effect" do
      assert Layers.combine(:p, :p) == :p
      assert Layers.combine(:exn, :exn) == :exn
      assert Layers.combine(:l, :l) == :l
      assert Layers.combine(:d, :d) == :d
      assert Layers.combine(:s, :s) == :s
      assert Layers.combine(:n, :n) == :n
      assert Layers.combine(:u, :u) == :u
    end
  end

  describe "combine_all/1 - picks most severe from list" do
    test "empty list returns pure" do
      assert Layers.combine_all([]) == :p
    end

    test "single element returns that element" do
      assert Layers.combine_all([:s]) == :s
      assert Layers.combine_all([:exn]) == :exn
      assert Layers.combine_all([:u]) == :u
    end

    test "returns most severe effect from list" do
      assert Layers.combine_all([:p, :s, :l]) == :s
      assert Layers.combine_all([:exn, :d, :p]) == :d
      assert Layers.combine_all([:l, :exn, :p]) == :exn
      assert Layers.combine_all([:p, :p, :p]) == :p
    end

    test "unknown always wins" do
      assert Layers.combine_all([:p, :s, :u, :l]) == :u
      assert Layers.combine_all([:n, :s, :u, :d]) == :u
      assert Layers.combine_all([:u, :p]) == :u
    end

    test "handles nil values in list" do
      assert Layers.combine_all([nil, :s, nil, :l]) == :s
      assert Layers.combine_all([nil, nil, :p]) == :p
      assert Layers.combine_all([nil, :u, :s]) == :u
    end

    test "all nils returns pure" do
      assert Layers.combine_all([nil, nil, nil]) == :p
    end

    test "complex scenario: all effect types" do
      # Should return :u (most severe)
      all_effects = [:p, :exn, :l, :d, :s, :n, :u]
      assert Layers.combine_all(all_effects) == :u
    end

    test "without unknown, nif is most severe" do
      effects = [:p, :exn, :l, :d, :s, :n]
      assert Layers.combine_all(effects) == :n
    end

    test "without unknown or nif, side effects is most severe" do
      effects = [:p, :exn, :l, :d, :s]
      assert Layers.combine_all(effects) == :s
    end
  end

  describe "real-world scenarios" do
    test "File.write!/2 has both side effects and exceptions - side effects more severe" do
      # File.write! has both {:s, ...} and {:e, ...}
      # When forced to pick one, should pick :s (more severe than :exn)
      result = Layers.combine_all([:s, :exn])
      assert result == :s
    end

    test "Map.fetch!/2 has only exceptions" do
      # Map.fetch! has only {:e, ...}
      result = Layers.combine_all([:exn])
      assert result == :exn
    end

    test "function with lambda and exception - exception more severe" do
      result = Layers.combine_all([:l, :exn])
      assert result == :exn
    end

    test "function with exception and dependent - dependent more severe" do
      result = Layers.combine_all([:exn, :d])
      assert result == :d
    end

    test "function with all three: side effects, dependent, exception" do
      # Should pick side effects as most severe
      result = Layers.combine_all([:s, :d, :exn])
      assert result == :s
    end

    test "unannotated function is unknown - most severe" do
      result = Layers.combine_all([:u, :s, :exn])
      assert result == :u
    end
  end

  describe "boolean predicates" do
    test "pure?/1 only true for :p" do
      assert Layers.pure?(:p) == true
      assert Layers.pure?(:exn) == false
      assert Layers.pure?(:l) == false
      assert Layers.pure?(:d) == false
      assert Layers.pure?(:s) == false
      assert Layers.pure?(:n) == false
      assert Layers.pure?(:u) == false
    end

    test "has_side_effects?/1 only true for :s" do
      assert Layers.has_side_effects?(:s) == true
      assert Layers.has_side_effects?(:p) == false
      assert Layers.has_side_effects?(:exn) == false
      assert Layers.has_side_effects?(:l) == false
      assert Layers.has_side_effects?(:d) == false
      assert Layers.has_side_effects?(:n) == false
      assert Layers.has_side_effects?(:u) == false
    end

    test "dependent?/1 only true for :d" do
      assert Layers.dependent?(:d) == true
      assert Layers.dependent?(:p) == false
      assert Layers.dependent?(:exn) == false
      assert Layers.dependent?(:l) == false
      assert Layers.dependent?(:s) == false
      assert Layers.dependent?(:n) == false
      assert Layers.dependent?(:u) == false
    end

    test "lambda_dependent?/1 only true for :l" do
      assert Layers.lambda_dependent?(:l) == true
      assert Layers.lambda_dependent?(:p) == false
      assert Layers.lambda_dependent?(:exn) == false
      assert Layers.lambda_dependent?(:d) == false
      assert Layers.lambda_dependent?(:s) == false
      assert Layers.lambda_dependent?(:n) == false
      assert Layers.lambda_dependent?(:u) == false
    end
  end

  describe "describe/1" do
    test "returns human-readable descriptions" do
      assert Layers.describe(:p) == "pure"
      assert Layers.describe(:s) == "side effects"
      assert Layers.describe(:d) == "dependent on environment"
      assert Layers.describe(:l) == "lambda-dependent"
      assert Layers.describe(:exn) == "exception"
      assert Layers.describe({:e, [:error]}) == "exception"
      assert Layers.describe(:n) == "native code (NIF)"
      assert Layers.describe(:u) == "unknown"
      assert Layers.describe(nil) == "none"
    end
  end
end
