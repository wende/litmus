#!/usr/bin/env elixir

# Simplified Spike 4 Benchmark
# Tests just dependency graph building (Task 1) without full analysis

alias Litmus.Analyzer.DependencyGraph

IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("SPIKE 4: DEPENDENCY GRAPH PERFORMANCE (SIMPLIFIED)")
IO.puts(String.duplicate("=", 80))
IO.puts("")

# Test on litmus project
files = Path.wildcard("lib/**/*.ex")
IO.puts("Found #{length(files)} files to analyze")
IO.puts("")

# Phase 1: Cold analysis - build graph from scratch
IO.puts("Phase 1: Cold dependency graph building...")
{time_cold_us, graph} = :timer.tc(fn ->
  DependencyGraph.from_files(files)
end)

time_cold_s = time_cold_us / 1_000_000
module_count = MapSet.size(graph.modules)
edge_count = Enum.reduce(graph.edges, 0, fn {_, deps}, acc -> acc + MapSet.size(deps) end)
cycles = DependencyGraph.find_cycles(graph)

IO.puts("✅ Graph built in #{Float.round(time_cold_s, 3)}s")
IO.puts("   Modules: #{module_count}")
IO.puts("   Dependencies: #{edge_count}")
IO.puts("   Cycles: #{length(cycles)}")
IO.puts("   Speed: #{Float.round(module_count / time_cold_s, 2)} modules/second")
IO.puts("")

# Phase 2: Topological sort
IO.puts("Phase 2: Topological sorting...")
{time_sort_us, sort_result} = :timer.tc(fn ->
  DependencyGraph.topological_sort(graph)
end)

time_sort_ms = time_sort_us / 1_000

case sort_result do
  {:ok, ordered} ->
    IO.puts("✅ Sorted #{length(ordered)} modules in #{Float.round(time_sort_ms, 2)}ms")
    IO.puts("   No cycles detected")

  {:cycles, linear, cycles} ->
    IO.puts("✅ Sorted #{length(linear)} linear modules in #{Float.round(time_sort_ms, 2)}ms")
    IO.puts("   ⚠  Detected #{length(cycles)} cycle(s):")
    Enum.each(cycles, fn cycle ->
      IO.puts("      - #{inspect(cycle)}")
    end)
end

IO.puts("")

# Phase 3: Memory usage
:erlang.garbage_collect()
memory_before = :erlang.memory(:total)

# Rebuild graph
_graph2 = DependencyGraph.from_files(files)

memory_after = :erlang.memory(:total)
delta_mb = (memory_after - memory_before) / 1_024 / 1_024

IO.puts("Phase 3: Memory usage")
IO.puts("✅ Peak memory: #{Float.round(memory_after / 1_024 / 1_024, 2)} MB")
IO.puts("   Delta: #{Float.round(delta_mb, 2)} MB")
IO.puts("")

# Phase 4: Cache size
serialized = :erlang.term_to_binary(graph)
cache_mb = byte_size(serialized) / 1_024 / 1_024

IO.puts("Phase 4: Graph serialization size")
IO.puts("✅ Serialized: #{Float.round(cache_mb, 2)} MB")
IO.puts("   Per module: #{div(byte_size(serialized), module_count)} bytes")
IO.puts("")

# Decision
IO.puts(String.duplicate("=", 80))
IO.puts("DECISION")
IO.puts(String.duplicate("=", 80))
IO.puts("")

# Criteria for Task 1 (Dependency Graph Builder)
# For 35 modules, we expect <<1s. Scale to 500 modules: <15s reasonable
target_cold_s = 30.0  # For 500 modules
target_sort_ms = 100.0  # Tarjan should be very fast
target_memory_mb = 500.0

# Scale projection to 500 modules
projected_time_500 = time_cold_s * (500 / module_count)
projected_memory_500 = (memory_after / 1_024 / 1_024) * (500 / module_count)

IO.puts("Current performance (#{module_count} modules):")
IO.puts("  Cold graph building: #{Float.round(time_cold_s, 3)}s")
IO.puts("  Topological sort: #{Float.round(time_sort_ms, 2)}ms")
IO.puts("  Memory usage: #{Float.round(memory_after / 1_024 / 1_024, 2)} MB")
IO.puts("")

IO.puts("Projected for 500 modules:")
IO.puts("  Cold graph building: #{Float.round(projected_time_500, 2)}s (target: <#{target_cold_s}s)")
IO.puts("  Memory usage: #{Float.round(projected_memory_500, 2)} MB (target: <#{target_memory_mb} MB)")
IO.puts("")

cold_pass = projected_time_500 < target_cold_s
sort_pass = time_sort_ms < target_sort_ms
memory_pass = projected_memory_500 < target_memory_mb

if cold_pass and sort_pass and memory_pass do
  IO.puts("✅ GO DECISION")
  IO.puts("")
  IO.puts("Task 1 (Dependency Graph Builder) meets all performance criteria:")
  IO.puts("  ✓ Can build graph for 500 modules in <30s")
  IO.puts("  ✓ Topological sort is fast (<100ms)")
  IO.puts("  ✓ Memory usage is reasonable (<500MB)")
  IO.puts("")
  IO.puts("Recommendation: Proceed with Task 1 implementation as planned")
elsif projected_time_500 < 60.0 and projected_memory_500 < 1000.0 do
  IO.puts("⚠️  CONDITIONAL GO")
  IO.puts("")
  IO.puts("Performance is acceptable but could be improved:")
  cold_icon = if cold_pass, do: "✓", else: "⚠"
  sort_icon = if sort_pass, do: "✓", else: "⚠"
  mem_icon = if memory_pass, do: "✓", else: "⚠"
  IO.puts("  #{cold_icon} Graph building: #{Float.round(projected_time_500, 2)}s")
  IO.puts("  #{sort_icon} Topological sort: #{Float.round(time_sort_ms, 2)}ms")
  IO.puts("  #{mem_icon} Memory: #{Float.round(projected_memory_500, 2)} MB")
  IO.puts("")
  IO.puts("Recommendation: Proceed with Task 1 but consider optimization:")
  IO.puts("  - Parallelize file reading and AST parsing")
  IO.puts("  - Optimize dependency extraction")
else
  IO.puts("❌ NO-GO")
  IO.puts("")
  IO.puts("Performance does not meet criteria:")
  cold_icon = if cold_pass, do: "✓", else: "❌"
  sort_icon = if sort_pass, do: "✓", else: "❌"
  mem_icon = if memory_pass, do: "✓", else: "❌"
  IO.puts("  #{cold_icon} Graph building: #{Float.round(projected_time_500, 2)}s (target: <30s)")
  IO.puts("  #{sort_icon} Topological sort: #{Float.round(time_sort_ms, 2)}ms (target: <100ms)")
  IO.puts("  #{mem_icon} Memory: #{Float.round(projected_memory_500, 2)} MB (target: <500MB)")
  IO.puts("")
  IO.puts("Recommendation: Redesign Task 1 approach")
end

IO.puts(String.duplicate("=", 80))
IO.puts("")

IO.puts("NOTE: Full AST analysis (Tasks 2-3) not tested due to existing analyzer bug.")
IO.puts("The analyzer crashes on {:unquote, ...} AST nodes when analyzing itself.")
IO.puts("This is a separate issue to be fixed before running full performance tests.")
IO.puts("")
