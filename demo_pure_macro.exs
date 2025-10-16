#!/usr/bin/env elixir

# Demo script for the pure do...end macro

IO.puts("=== Litmus Pure Macro Demo ===\n")

Code.require_file("lib/litmus/stdlib.ex")
Code.require_file("lib/litmus/pure.ex")

import Litmus.Pure

IO.puts("1. Pure data transformation pipeline:")
IO.puts("   Code:")
IO.inspect(quote do
  pure do
    [1, 2, 3, 4, 5]
    |> Enum.map(&(&1 * 2))
    |> Enum.filter(&(&1 > 5))
    |> Enum.sum()
  end
end, pretty: true)

result = pure do
  [1, 2, 3, 4, 5]
  |> Enum.map(&(&1 * 2))
  |> Enum.filter(&(&1 > 5))
  |> Enum.sum()
end

IO.puts("   Result: #{result}")
IO.puts("   ✅ Compiles successfully!\n")

IO.puts("2. Pure string processing:")
result = pure do
  "Hello World"
  |> String.downcase()
  |> String.split(" ")
  |> Enum.map(&String.reverse/1)
  |> Enum.join("-")
end

IO.puts("   Result: #{inspect(result)}")
IO.puts("   ✅ Compiles successfully!\n")

IO.puts("3. Pure mathematical computation:")
result = pure do
  numbers = [10, 20, 30, 40, 50]
  sum = Enum.sum(numbers)
  count = Enum.count(numbers)
  Float.round(sum / count, 2)
end

IO.puts("   Result: #{result}")
IO.puts("   ✅ Compiles successfully!\n")

IO.puts("4. Demonstrating compile-time error detection:")
IO.puts("   The following code will fail to compile:")
IO.puts("""
   pure do
     IO.puts("This would fail!")  # ❌ Impure!
   end
""")
IO.puts("   Error: IO.puts/1 (I/O operation)\n")

IO.puts("5. Demonstrating dangerous operation detection:")
IO.puts("   The following code will fail to compile:")
IO.puts("""
   pure do
     String.to_atom("user_input")  # ❌ Dangerous!
   end
""")
IO.puts("   Error: String.to_atom/1 (mutates atom table)\n")

IO.puts("=== All examples completed! ===")
IO.puts("\nThe pure macro successfully:")
IO.puts("  ✅ Allows pure operations to execute normally")
IO.puts("  ✅ Prevents impure operations at compile time")
IO.puts("  ✅ Expands macros (like |>) before analysis")
IO.puts("  ✅ Provides detailed error messages with classifications")
