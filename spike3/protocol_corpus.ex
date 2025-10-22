defmodule Spike3.ProtocolCorpus do
  @moduledoc """
  Test corpus for protocol dispatch resolution spike.

  Contains 10+ examples covering:
  - Built-in types (List, Map, MapSet, Range)
  - User structs with protocol implementations
  - Protocol call pipelines
  - Mixed pure/effectful implementations
  """

  # Example 1: Simple list enumeration (built-in)
  def example_1_list_map do
    [1, 2, 3]
    |> Enum.map(&(&1 * 2))
  end

  # Example 2: Map enumeration (built-in)
  def example_2_map_map do
    %{a: 1, b: 2, c: 3}
    |> Enum.map(fn {k, v} -> {k, v * 2} end)
  end

  # Example 3: MapSet enumeration (built-in)
  def example_3_mapset_map do
    MapSet.new([1, 2, 3])
    |> Enum.map(&(&1 * 2))
  end

  # Example 4: Range enumeration (built-in)
  def example_4_range_map do
    1..10
    |> Enum.map(&(&1 * 2))
  end

  # Example 5: Pipeline with multiple protocol calls
  def example_5_pipeline do
    [1, 2, 3, 4, 5]
    |> Enum.map(&(&1 * 2))
    |> Enum.filter(&(&1 > 5))
    |> Enum.sum()
  end

  # Example 6: Effectful lambda (should be effectful overall)
  def example_6_effectful_lambda do
    [1, 2, 3]
    |> Enum.each(&IO.puts/1)
  end

  # Example 7: String.Chars protocol
  def example_7_string_chars do
    to_string(42)
  end

  # Example 8: Inspect protocol
  def example_8_inspect do
    inspect(%{a: 1, b: 2})
  end

  # Example 9: Collectable protocol
  def example_9_collectable do
    Enum.into([{:a, 1}, {:b, 2}], %{})
  end

  # Example 10: Mixed - pure structure, pure operation
  def example_10_pure_pipeline do
    [1, 2, 3]
    |> Enum.map(&(&1 * 2))
    |> Enum.reduce(0, &+/2)
  end
end

# User-defined struct examples
defmodule Spike3.MyList do
  @moduledoc """
  Simple list wrapper to test user struct protocol resolution.
  """
  defstruct items: []

  def new(items \\ []) do
    %__MODULE__{items: items}
  end
end

defimpl Enumerable, for: Spike3.MyList do
  def count(%Spike3.MyList{items: items}) do
    {:ok, length(items)}
  end

  def member?(%Spike3.MyList{items: items}, element) do
    {:ok, element in items}
  end

  def slice(%Spike3.MyList{items: items}) do
    size = length(items)
    {:ok, size, &Enumerable.List.slice(items, &1, &2, size)}
  end

  def reduce(%Spike3.MyList{items: items}, acc, fun) do
    Enumerable.List.reduce(items, acc, fun)
  end
end

defmodule Spike3.EffectfulList do
  @moduledoc """
  List wrapper with effectful protocol implementation.
  Tests effect tracking through custom implementations.
  """
  defstruct items: []

  def new(items \\ []) do
    %__MODULE__{items: items}
  end
end

defimpl Enumerable, for: Spike3.EffectfulList do
  def count(%Spike3.EffectfulList{items: items}) do
    IO.puts("Counting items: #{length(items)}")
    {:ok, length(items)}
  end

  def member?(%Spike3.EffectfulList{items: items}, element) do
    result = element in items
    IO.puts("Checking membership: #{element} -> #{result}")
    {:ok, result}
  end

  def slice(%Spike3.EffectfulList{items: items}) do
    size = length(items)
    {:ok, size, &Enumerable.List.slice(items, &1, &2, size)}
  end

  def reduce(%Spike3.EffectfulList{items: items}, acc, fun) do
    IO.puts("Reducing over #{length(items)} items")
    Enumerable.List.reduce(items, acc, fun)
  end
end

defmodule Spike3.UserStructExamples do
  @moduledoc """
  Examples using user-defined structs with protocols.
  """

  # Example 11: User struct with pure implementation
  def example_11_user_struct_pure do
    Spike3.MyList.new([1, 2, 3])
    |> Enum.map(&(&1 * 2))
  end

  # Example 12: User struct with effectful implementation
  def example_12_user_struct_effectful do
    Spike3.EffectfulList.new([1, 2, 3])
    |> Enum.map(&(&1 * 2))
  end

  # Example 13: User struct in pipeline
  def example_13_user_struct_pipeline do
    Spike3.MyList.new([1, 2, 3, 4, 5])
    |> Enum.filter(&(&1 > 2))
    |> Enum.map(&(&1 * 2))
  end

  # Example 14: Mixed user struct and built-in
  def example_14_mixed do
    list1 = Spike3.MyList.new([1, 2, 3])
    list2 = [4, 5, 6]

    result1 = Enum.map(list1, &(&1 * 2))
    result2 = Enum.map(list2, &(&1 * 2))

    {result1, result2}
  end
end
