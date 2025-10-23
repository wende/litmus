#!/usr/bin/env elixir

# Investigation script for understanding Elixir protocol implementation
# Run with: mix run spike3/investigate_protocols.exs

IO.puts("=== Spike 3: Protocol System Investigation ===\n")

# 1. Built-in protocol metadata
IO.puts("1. Enumerable Protocol Metadata:")
IO.puts("   Functions: #{inspect(Enumerable.__protocol__(:functions))}")
IO.puts("   Module type: #{inspect(Enumerable.__protocol__(:module))}")

# Check if protocol is consolidated
IO.puts("   Consolidated: #{inspect(Enumerable.__protocol__(:consolidated?))}")

# Get implementations
impls_raw = Enumerable.__protocol__(:impls)

# Handle consolidated protocols
impls =
  case impls_raw do
    {:consolidated, list} -> list
    list when is_list(list) -> list
    _ -> []
  end

IO.puts("   Implementations: #{inspect(impls)}\n")

# 2. Check what metadata is available for each implementation
IO.puts("2. Implementation Details:")

for impl <- Enum.take(impls, 5) do
  IO.puts("   #{inspect(impl)}:")

  # Check if module exists and is loaded
  case Code.ensure_loaded(impl) do
    {:module, _} ->
      # Check if implementation module exists
      impl_module = Module.concat([Enumerable, impl])

      case Code.ensure_loaded(impl_module) do
        {:module, _} ->
          IO.puts("     Implementation module: #{inspect(impl_module)}")

          # Get exported functions
          exports = impl_module.__info__(:functions)
          IO.puts("     Exported functions: #{inspect(exports)}")

        {:error, reason} ->
          IO.puts("     Implementation module not found: #{inspect(reason)}")
      end

    {:error, reason} ->
      IO.puts("     Type module not loadable: #{inspect(reason)}")
  end

  IO.puts("")
end

# 3. How does protocol dispatch work?
IO.puts("3. Protocol Dispatch Mechanism:")
IO.puts("   For a call like Enum.map([1,2,3], fn), Elixir:")
IO.puts("   1. Calls Enumerable.impl_for([1,2,3])")
IO.puts("   2. Returns implementation module based on type")
IO.puts("   3. Delegates to that module's functions")

# Test impl_for
test_values = [
  [1, 2, 3],
  %{a: 1},
  MapSet.new([1, 2]),
  1..10,
  %File.Stream{path: "test", modes: [], raw: true, line_or_bytes: :line}
]

IO.puts("\n4. Testing impl_for with different types:")

for value <- test_values do
  impl = Enumerable.impl_for(value)

  type_name =
    cond do
      is_list(value) -> "List"
      is_map(value) and not is_struct(value) -> "Map"
      is_struct(value) -> inspect(value.__struct__)
      is_tuple(value) -> "Range"
      true -> inspect(value)
    end

  IO.puts("   #{type_name} -> #{inspect(impl)}")
end

# 5. Can we get struct module from struct?
IO.puts("\n5. Extracting type information from values:")
IO.puts("   For structs, __struct__ key contains the module name")
IO.puts("   Example: %MapSet{} has __struct__: MapSet")

mapset_example = MapSet.new([1, 2, 3])
IO.puts("   MapSet.__struct__: #{inspect(mapset_example.__struct__)}")
IO.puts("   MapSet keys: #{inspect(Map.keys(mapset_example))}")

# 6. What about protocol consolidation?
IO.puts("\n6. Protocol Consolidation:")
IO.puts("   Consolidated protocols are pre-computed for performance")
IO.puts("   Enumerable consolidated? #{inspect(Enumerable.__protocol__(:consolidated?))}")
IO.puts("   When consolidated, impl_for uses fast lookup table")

# 7. How to detect protocol implementations in source code?
IO.puts("\n7. Detecting Protocol Implementations in Source:")
IO.puts("   AST pattern: {:defimpl, _, [protocol_name, [for: type], [do: body]]}")
IO.puts("   Example: defimpl Enumerable, for: MyStruct do ... end")

IO.puts("\n=== End Investigation ===")
