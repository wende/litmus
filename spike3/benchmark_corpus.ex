defmodule Spike3.BenchmarkCorpus do
  @moduledoc """
  Comprehensive benchmark corpus for protocol effect tracing.

  50 test cases covering:
  - Enum operations (20 cases)
  - String.Chars protocol (10 cases)
  - Inspect protocol (5 cases)
  - String operations (10 cases)
  - Edge cases (5 cases)

  Each case includes:
  - Source code
  - Expected struct type
  - Expected lambda effect
  - Expected combined effect
  """

  #################################################################
  # Enum Operations (20 cases)
  #################################################################

  @doc "Case 1: List map with pure lambda"
  def case_01 do
    [1, 2, 3] |> Enum.map(&(&1 * 2))
  end

  # Metadata for case 1
  def meta_01 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure list + pure lambda = pure"
    }
  end

  @doc "Case 2: List filter with pure lambda"
  def case_02 do
    [1, 2, 3, 4, 5] |> Enum.filter(&(&1 > 2))
  end

  def meta_02 do
    %{
      category: :enum,
      function: :filter,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure list + pure lambda = pure"
    }
  end

  @doc "Case 3: List reduce with pure lambda"
  def case_03 do
    [1, 2, 3] |> Enum.reduce(0, &+/2)
  end

  def meta_03 do
    %{
      category: :enum,
      function: :reduce,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure list + pure operator = pure"
    }
  end

  @doc "Case 4: List each with effectful lambda"
  def case_04 do
    [1, 2, 3] |> Enum.each(&IO.puts/1)
  end

  def meta_04 do
    %{
      category: :enum,
      function: :each,
      struct_type: {:list, :integer},
      lambda_effect: :s,
      expected_effect: :s,
      description: "Pure list + effectful lambda = effectful"
    }
  end

  @doc "Case 5: List map with effectful lambda"
  def case_05 do
    [1, 2, 3] |> Enum.map(fn x -> IO.puts(x); x * 2 end)
  end

  def meta_05 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:list, :integer},
      lambda_effect: :s,
      expected_effect: :s,
      description: "Pure list + effectful lambda = effectful"
    }
  end

  @doc "Case 6: Map enumeration with pure lambda"
  def case_06 do
    %{a: 1, b: 2, c: 3} |> Enum.map(fn {k, v} -> {k, v * 2} end)
  end

  def meta_06 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:map, []},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure map + pure lambda = pure"
    }
  end

  @doc "Case 7: Map filter with pure lambda"
  def case_07 do
    %{a: 1, b: 2, c: 3} |> Enum.filter(fn {_k, v} -> v > 1 end)
  end

  def meta_07 do
    %{
      category: :enum,
      function: :filter,
      struct_type: {:map, []},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure map + pure lambda = pure"
    }
  end

  @doc "Case 8: MapSet map with pure lambda"
  def case_08 do
    MapSet.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
  end

  def meta_08 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:struct, MapSet, %{}},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure MapSet + pure lambda = pure"
    }
  end

  @doc "Case 9: Range map with pure lambda"
  def case_09 do
    (1..10) |> Enum.map(&(&1 * 2))
  end

  def meta_09 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:struct, Range, %{}},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure Range + pure lambda = pure"
    }
  end

  @doc "Case 10: List count (no lambda)"
  def case_10 do
    [1, 2, 3, 4, 5] |> Enum.count()
  end

  def meta_10 do
    %{
      category: :enum,
      function: :count,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure list count = pure (no lambda)"
    }
  end

  @doc "Case 11: User struct MyList with pure lambda"
  def case_11 do
    Spike3.MyList.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
  end

  def meta_11 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:struct, Spike3.MyList, %{}},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure user struct + pure lambda = pure"
    }
  end

  @doc "Case 12: User struct EffectfulList with pure lambda"
  def case_12 do
    Spike3.EffectfulList.new([1, 2, 3]) |> Enum.map(&(&1 * 2))
  end

  def meta_12 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:struct, Spike3.EffectfulList, %{}},
      lambda_effect: :p,
      expected_effect: :s,
      description: "Effectful user struct + pure lambda = effectful"
    }
  end

  @doc "Case 13: User struct EffectfulList with effectful lambda"
  def case_13 do
    Spike3.EffectfulList.new([1, 2, 3]) |> Enum.map(fn x -> IO.puts(x); x * 2 end)
  end

  def meta_13 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:struct, Spike3.EffectfulList, %{}},
      lambda_effect: :s,
      expected_effect: :s,
      description: "Effectful user struct + effectful lambda = effectful"
    }
  end

  @doc "Case 14: Pipeline - pure operations"
  def case_14 do
    [1, 2, 3, 4, 5]
    |> Enum.map(&(&1 * 2))
    |> Enum.filter(&(&1 > 5))
    |> Enum.sum()
  end

  def meta_14 do
    %{
      category: :enum,
      function: :pipeline,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure pipeline (map -> filter -> sum)"
    }
  end

  @doc "Case 15: Pipeline - mixed pure/effectful"
  def case_15 do
    [1, 2, 3]
    |> Enum.map(fn x -> IO.puts(x); x * 2 end)
    |> Enum.filter(&(&1 > 2))
  end

  def meta_15 do
    %{
      category: :enum,
      function: :pipeline,
      struct_type: {:list, :integer},
      lambda_effect: :s,
      expected_effect: :s,
      description: "Mixed pipeline (effectful map -> pure filter)"
    }
  end

  @doc "Case 16: List reject with pure lambda"
  def case_16 do
    [1, 2, 3, 4, 5] |> Enum.reject(&(&1 > 3))
  end

  def meta_16 do
    %{
      category: :enum,
      function: :reject,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure list + pure lambda = pure"
    }
  end

  @doc "Case 17: List take (no lambda)"
  def case_17 do
    [1, 2, 3, 4, 5] |> Enum.take(3)
  end

  def meta_17 do
    %{
      category: :enum,
      function: :take,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure list take = pure (no lambda)"
    }
  end

  @doc "Case 18: List drop (no lambda)"
  def case_18 do
    [1, 2, 3, 4, 5] |> Enum.drop(2)
  end

  def meta_18 do
    %{
      category: :enum,
      function: :drop,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure list drop = pure (no lambda)"
    }
  end

  @doc "Case 19: Map reduce with pure lambda"
  def case_19 do
    %{a: 1, b: 2} |> Enum.reduce(0, fn {_k, v}, acc -> acc + v end)
  end

  def meta_19 do
    %{
      category: :enum,
      function: :reduce,
      struct_type: {:map, []},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure map + pure reduce = pure"
    }
  end

  @doc "Case 20: Range filter with pure lambda"
  def case_20 do
    (1..20) |> Enum.filter(&(rem(&1, 2) == 0))
  end

  def meta_20 do
    %{
      category: :enum,
      function: :filter,
      struct_type: {:struct, Range, %{}},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Pure Range + pure lambda = pure"
    }
  end

  #################################################################
  # String.Chars Protocol (10 cases)
  #################################################################

  @doc "Case 21: to_string on integer"
  def case_21 do
    to_string(42)
  end

  def meta_21 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: :integer,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.Chars.Integer = pure"
    }
  end

  @doc "Case 22: to_string on atom"
  def case_22 do
    to_string(:hello)
  end

  def meta_22 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: :atom,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.Chars.Atom = pure"
    }
  end

  @doc "Case 23: to_string on float"
  def case_23 do
    to_string(3.14)
  end

  def meta_23 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: :float,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.Chars.Float = pure"
    }
  end

  @doc "Case 24: to_string on list"
  def case_24 do
    to_string([72, 101, 108, 108, 111])
  end

  def meta_24 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.Chars.List = pure"
    }
  end

  @doc "Case 25: to_string on binary"
  def case_25 do
    to_string("hello")
  end

  def meta_25 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.Chars.BitString = pure"
    }
  end

  @doc "Case 26: Kernel.to_string in pipeline"
  def case_26 do
    42 |> to_string() |> String.upcase()
  end

  def meta_26 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: :integer,
      lambda_effect: :p,
      expected_effect: :p,
      description: "to_string pipeline = pure"
    }
  end

  @doc "Case 27: String interpolation (uses to_string)"
  def case_27 do
    x = 42
    "The answer is #{x}"
  end

  def meta_27 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: :integer,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String interpolation = pure"
    }
  end

  @doc "Case 28: Map Enum.map to_string"
  def case_28 do
    [1, 2, 3] |> Enum.map(&to_string/1)
  end

  def meta_28 do
    %{
      category: :enum,
      function: :map,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "List map with to_string = pure"
    }
  end

  @doc "Case 29: Multiple to_string calls"
  def case_29 do
    a = to_string(1)
    b = to_string(2)
    a <> b
  end

  def meta_29 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: :integer,
      lambda_effect: :p,
      expected_effect: :p,
      description: "Multiple to_string = pure"
    }
  end

  @doc "Case 30: to_string in comprehension"
  def case_30 do
    for x <- [1, 2, 3], do: to_string(x)
  end

  def meta_30 do
    %{
      category: :string_chars,
      function: :to_string,
      struct_type: :integer,
      lambda_effect: :p,
      expected_effect: :p,
      description: "to_string in comprehension = pure"
    }
  end

  #################################################################
  # Inspect Protocol (5 cases)
  #################################################################

  @doc "Case 31: inspect on map"
  def case_31 do
    inspect(%{a: 1, b: 2})
  end

  def meta_31 do
    %{
      category: :inspect,
      function: :inspect,
      struct_type: {:map, []},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Inspect.Map = pure"
    }
  end

  @doc "Case 32: inspect on list"
  def case_32 do
    inspect([1, 2, 3])
  end

  def meta_32 do
    %{
      category: :inspect,
      function: :inspect,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Inspect.List = pure"
    }
  end

  @doc "Case 33: inspect on atom"
  def case_33 do
    inspect(:hello)
  end

  def meta_33 do
    %{
      category: :inspect,
      function: :inspect,
      struct_type: :atom,
      lambda_effect: :p,
      expected_effect: :p,
      description: "Inspect.Atom = pure"
    }
  end

  @doc "Case 34: inspect on integer"
  def case_34 do
    inspect(42)
  end

  def meta_34 do
    %{
      category: :inspect,
      function: :inspect,
      struct_type: :integer,
      lambda_effect: :p,
      expected_effect: :p,
      description: "Inspect.Integer = pure"
    }
  end

  @doc "Case 35: inspect in pipeline"
  def case_35 do
    %{a: 1, b: 2} |> inspect() |> String.upcase()
  end

  def meta_35 do
    %{
      category: :inspect,
      function: :inspect,
      struct_type: {:map, []},
      lambda_effect: :p,
      expected_effect: :p,
      description: "inspect pipeline = pure"
    }
  end

  #################################################################
  # String Operations (10 cases)
  #################################################################

  @doc "Case 36: String.upcase"
  def case_36 do
    String.upcase("hello")
  end

  def meta_36 do
    %{
      category: :string,
      function: :upcase,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.upcase = pure"
    }
  end

  @doc "Case 37: String.downcase"
  def case_37 do
    String.downcase("HELLO")
  end

  def meta_37 do
    %{
      category: :string,
      function: :downcase,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.downcase = pure"
    }
  end

  @doc "Case 38: String.trim"
  def case_38 do
    String.trim("  hello  ")
  end

  def meta_38 do
    %{
      category: :string,
      function: :trim,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.trim = pure"
    }
  end

  @doc "Case 39: String.split"
  def case_39 do
    String.split("a,b,c", ",")
  end

  def meta_39 do
    %{
      category: :string,
      function: :split,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.split = pure"
    }
  end

  @doc "Case 40: String.replace"
  def case_40 do
    String.replace("hello world", "world", "elixir")
  end

  def meta_40 do
    %{
      category: :string,
      function: :replace,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.replace = pure"
    }
  end

  @doc "Case 41: String pipeline"
  def case_41 do
    "  HELLO  "
    |> String.trim()
    |> String.downcase()
    |> String.upcase()
  end

  def meta_41 do
    %{
      category: :string,
      function: :pipeline,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String pipeline = pure"
    }
  end

  @doc "Case 42: String.length"
  def case_42 do
    String.length("hello")
  end

  def meta_42 do
    %{
      category: :string,
      function: :length,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.length = pure"
    }
  end

  @doc "Case 43: String.slice"
  def case_43 do
    String.slice("hello", 1, 3)
  end

  def meta_43 do
    %{
      category: :string,
      function: :slice,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.slice = pure"
    }
  end

  @doc "Case 44: String.reverse"
  def case_44 do
    String.reverse("hello")
  end

  def meta_44 do
    %{
      category: :string,
      function: :reverse,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.reverse = pure"
    }
  end

  @doc "Case 45: String.contains?"
  def case_45 do
    String.contains?("hello world", "world")
  end

  def meta_45 do
    %{
      category: :string,
      function: :contains?,
      struct_type: :binary,
      lambda_effect: :p,
      expected_effect: :p,
      description: "String.contains? = pure"
    }
  end

  #################################################################
  # Edge Cases (5 cases)
  #################################################################

  @doc "Case 46: Empty list enumeration"
  def case_46 do
    [] |> Enum.map(&(&1 * 2))
  end

  def meta_46 do
    %{
      category: :edge_case,
      function: :map,
      struct_type: {:list, :any},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Empty list = pure"
    }
  end

  @doc "Case 47: Nested Enum operations"
  def case_47 do
    [[1, 2], [3, 4]] |> Enum.map(fn list -> Enum.map(list, &(&1 * 2)) end)
  end

  def meta_47 do
    %{
      category: :edge_case,
      function: :map,
      struct_type: {:list, {:list, :integer}},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Nested map = pure"
    }
  end

  @doc "Case 48: Enum.into (Collectable protocol)"
  def case_48 do
    [{:a, 1}, {:b, 2}] |> Enum.into(%{})
  end

  def meta_48 do
    %{
      category: :edge_case,
      function: :into,
      struct_type: {:list, :tuple},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Enum.into = pure (Collectable)"
    }
  end

  @doc "Case 49: Mixed user and built-in types"
  def case_49 do
    list1 = Spike3.MyList.new([1, 2, 3])
    list2 = [4, 5, 6]
    {Enum.map(list1, &(&1 * 2)), Enum.map(list2, &(&1 * 2))}
  end

  def meta_49 do
    %{
      category: :edge_case,
      function: :map,
      struct_type: :mixed,
      lambda_effect: :p,
      expected_effect: :p,
      description: "Mixed user/built-in = pure"
    }
  end

  @doc "Case 50: Comprehension (desugars to Enum)"
  def case_50 do
    for x <- [1, 2, 3], y <- [4, 5], x + y > 5, do: x * y
  end

  def meta_50 do
    %{
      category: :edge_case,
      function: :comprehension,
      struct_type: {:list, :integer},
      lambda_effect: :p,
      expected_effect: :p,
      description: "Comprehension = pure"
    }
  end

  #################################################################
  # Helper Functions
  #################################################################

  @doc """
  Returns all benchmark cases as a list of {function_name, metadata}.
  """
  def all_cases do
    for i <- 1..50 do
      case_fun = String.to_atom("case_#{String.pad_leading(to_string(i), 2, "0")}")
      meta_fun = String.to_atom("meta_#{String.pad_leading(to_string(i), 2, "0")}")
      {case_fun, apply(__MODULE__, meta_fun, [])}
    end
  end

  @doc """
  Returns metadata for all cases grouped by category.
  """
  def by_category do
    all_cases()
    |> Enum.group_by(fn {_fun, meta} -> meta.category end)
  end

  @doc """
  Returns total count by category.
  """
  def category_counts do
    by_category()
    |> Enum.map(fn {category, cases} -> {category, length(cases)} end)
    |> Map.new()
  end
end
