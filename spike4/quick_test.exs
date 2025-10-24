#!/usr/bin/env elixir

# Quick Spike 4 Test - Dependency Graph Performance

alias Litmus.Analyzer.DependencyGraph

IO.puts "\n=================================================================================="
IO.puts "SPIKE 4: DEPENDENCY GRAPH PERFORMANCE TEST"
IO.puts "================================================================================\n"

# Count files
files = Path.wildcard("lib/**/*.ex")
IO.puts "Found #{length(files)} files"

# Build graph and measure time
{time_us, graph} = :timer.tc(fn -> DependencyGraph.from_files(files) end)
time_s = time_us / 1_000_000

# Get statistics
modules = MapSet.size(graph.modules)
edges = Enum.reduce(graph.edges, 0, fn {_, deps}, acc -> acc + MapSet.size(deps) end)

IO.puts "\nResults:"
IO.puts "  Modules: #{modules}"
IO.puts "  Edges: #{edges}"
IO.puts "  Time: #{Float.round(time_s, 3)}s"
IO.puts "  Speed: #{Float.round(modules / time_s, 2)} modules/s"

# Project to 500 modules
projected = time_s * (500 / modules)
IO.puts "\nProjected for 500 modules: #{Float.round(projected, 2)}s"

# Decision
status = if projected < 30.0, do: "✅ PASS", else: "❌ FAIL"
IO.puts "Status: #{status} (target: <30s)"

IO.puts "\n==================================================================================\n"
