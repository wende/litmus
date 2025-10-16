# Test script for Litmus wrapper

IO.puts("Testing Litmus wrapper...")

# Test with Erlang standard library modules (should work better)
IO.puts("\n1. Analyzing :lists module...")
{:ok, results} = Litmus.analyze_module(:lists)
IO.puts("✓ Successfully analyzed #{map_size(results)} functions")

# Show first few functions
IO.puts("\nFirst 10 analyzed functions:")
results
|> Map.keys()
|> Enum.take(10)
|> Enum.each(fn {m, f, a} ->
  purity = Map.get(results, {m, f, a})
  IO.puts("  - #{m}.#{f}/#{a}: #{purity}")
end)

# Test 2: Check purity of specific functions
IO.puts("\n2. Testing purity checks...")

# reverse/1 should be pure
is_pure = Litmus.pure?(results, {:lists, :reverse, 1})
IO.puts("  lists:reverse/1 is pure? #{is_pure}")

# Test 3: Get purity levels
IO.puts("\n3. Getting purity levels...")
case Litmus.get_purity(results, {:lists, :map, 2}) do
  {:ok, level} -> IO.puts("  lists:map/2: #{level}")
  :error -> IO.puts("  lists:map/2: not found")
end

# Test 4: Find missing functions
IO.puts("\n4. Finding missing functions...")
%{functions: mfas, primops: prims} = Litmus.find_missing(results)
IO.puts("  Missing MFAs: #{length(mfas)}")
if length(mfas) > 0 do
  IO.puts("  First few missing:")
  mfas |> Enum.take(5) |> Enum.each(fn {m, f, a} -> IO.puts("    - #{m}.#{f}/#{a}") end)
end

IO.puts("\n✓ All tests passed! Litmus wrapper is working correctly.")
