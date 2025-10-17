#!/usr/bin/env elixir

# Demonstrate the algebraic effects system with beautiful do...catch...end syntax

import Litmus.Effects

IO.puts "=== Algebraic Effects Demo ===\n"

# Example 1: Simple file reading with mock
IO.puts "1. Simple effect with inline handler:"
result1 = effect do
  File.read!("config.json")
catch
  {File, :read!, ["config.json"]} -> ~s({"name": "test"})
end
IO.puts "   Result: #{result1}\n"

# Example 2: Sequential effects
IO.puts "2. Sequential effects:"
result2 = effect do
  content = File.read!("input.txt")
  processed = String.upcase(content)
  File.write!("output.txt", processed)
  processed
catch
  {File, :read!, ["input.txt"]} -> "hello world"
  {File, :write!, ["output.txt", "HELLO WORLD"]} -> :ok
end
IO.puts "   Result: #{result2}\n"

# Example 3: External handler for reusability
IO.puts "3. Reusable external handler:"
file_mock = fn
  {File, :read!, [path]} -> "mocked content from #{path}"
  {File, :write!, [path, _content]} ->
    IO.puts "   [Mock] Would write to #{path}"
    :ok
end

result3a = effect(
  do: File.read!("data.txt"),
  catch: file_mock
)

result3b = effect(
  do: File.write!("output.txt", "some data"),
  catch: file_mock
)

IO.puts "   Read result: #{result3a}"
IO.puts "   Write result: #{inspect(result3b)}\n"

# Example 4: Wildcard patterns
IO.puts "4. Wildcard patterns:"
result4 = effect do
  File.read!("any-file.txt")
  File.write!("any-output.txt", "data")
catch
  {File, :read!, _} -> "wildcard file content"
  {File, :write!, _} -> :ok
end
IO.puts "   Result: #{inspect(result4)}\n"

# Example 5: Variable capture in handlers
IO.puts "5. Variable capture:"
result5 = effect do
  File.write!("log.txt", "Important message")
catch
  {File, :write!, [path, content]} ->
    IO.puts "   [Handler] Captured path: #{path}"
    IO.puts "   [Handler] Captured content: #{content}"
    :ok
end
IO.puts "   Result: #{inspect(result5)}\n"

# Example 6: Effect tracking options
IO.puts "6. Selective effect tracking (only :file effects):"
result6 = effect track: [:file] do
  content = File.read!("data.txt")
  IO.puts("Debug: #{content}")  # IO.puts won't be intercepted
  content
catch
  {File, :read!, _} -> "tracked file content"
end
IO.puts "   Result: #{result6}\n"

IO.puts "=== All examples completed successfully! ==="
