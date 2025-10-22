# Objective 003: Recursive Dependency Analysis

## Objective
Implement recursive, on-demand dependency analysis that automatically analyzes called functions when they're not in the cache, eliminating forward reference problems and ensuring complete effect information.

## Description
Currently, when AST walker encounters a function call to an uncached dependency, it returns nil and marks the calling function as :unknown. This creates a cascade of unknowns through the codebase. Recursive analysis will follow function calls, analyze dependencies on-demand, and cache results, ensuring every function has complete information about its callees.

### Key Problems Solved
- Functions marked :unknown due to uncached dependencies (30% of unknowns)
- Forward reference problems in analysis order
- Incomplete effect propagation
- Manual dependency resolution requirements

## Testing Criteria
1. **Recursive Analysis**
   - Automatically analyzes dependencies when encountered
   - Handles deep call chains (10+ levels)
   - Detects and handles circular dependencies
   - Caches results to avoid re-analysis

2. **Performance**
   - No exponential analysis time for deep chains
   - Memoization prevents duplicate work
   - Circular dependencies don't cause infinite loops
   - Analysis completes in O(n) time for n functions

3. **Accuracy**
   - All reachable functions analyzed
   - Effect propagation complete through all paths
   - No functions left as :unknown due to missing dependencies
   - Provisional typing for circular dependencies

## Detailed Implementation Guidance

### File: `lib/litmus/analyzer/recursive_analyzer.ex`

```elixir
defmodule Litmus.Analyzer.RecursiveAnalyzer do
  use GenServer

  @moduledoc """
  Recursive analyzer with cycle detection and memoization.
  """

  defstruct [
    :cache,           # Completed analyses
    :in_progress,     # Currently analyzing (for cycle detection)
    :provisional,     # Provisional types for cycles
    :call_stack      # For debugging and error messages
  ]

  def analyze_function(mfa, opts \\ []) do
    GenServer.call(__MODULE__, {:analyze, mfa, opts})
  end

  def handle_call({:analyze, mfa, opts}, _from, state) do
    case analyze_with_state(mfa, state, opts) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, new_state}
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  defp analyze_with_state(mfa, state, opts) do
    cond do
      # Already analyzed
      Map.has_key?(state.cache, mfa) ->
        {:ok, state.cache[mfa], state}

      # Currently analyzing (circular dependency)
      MapSet.member?(state.in_progress, mfa) ->
        handle_circular_dependency(mfa, state)

      # New function to analyze
      true ->
        analyze_new_function(mfa, state, opts)
    end
  end
end
```

### Key Algorithms

1. **Cycle Detection**
   ```elixir
   defp handle_circular_dependency(mfa, state) do
     # Use provisional type for now
     provisional = get_provisional_type(mfa, state)
     {:ok, provisional, state}
   end
   ```

2. **Recursive Analysis**
   ```elixir
   defp analyze_new_function(mfa, state, opts) do
     # Mark as in progress
     state = %{state | in_progress: MapSet.put(state.in_progress, mfa)}

     # Get function source
     {:ok, source} = get_function_source(mfa)

     # Analyze with recursive callback
     result = analyze_ast(source, fn called_mfa ->
       {:ok, result, _} = analyze_with_state(called_mfa, state, opts)
       result
     end)

     # Cache and return
     state = %{state |
       cache: Map.put(state.cache, mfa, result),
       in_progress: MapSet.delete(state.in_progress, mfa)
     }

     {:ok, result, state}
   end
   ```

3. **Fixed-Point Iteration for Cycles**
   ```elixir
   defp resolve_circular_dependencies(cycle_members, state) do
     # Start with provisional types
     # Iterate until fixed point reached
     # Update all members with final types
   end
   ```

### Integration with AST Walker

Modify `lib/litmus/analyzer/ast_walker.ex`:
```elixir
# Current (line 219)
Registry.runtime_cache()[mfa]  # Returns nil if not cached

# New
RecursiveAnalyzer.analyze_function(mfa)  # Recursively analyzes if needed
```

### Memoization Strategy
- Cache at function granularity
- Store both intermediate and final results
- Invalidate on source changes
- Persistent cache between runs

## State of Project After Implementation

### Improvements
- **Unknown classifications**: Reduced from ~10% to ~5%
- **Analysis completeness**: 100% of reachable functions analyzed
- **Effect propagation**: Complete through all call paths
- **Circular dependency handling**: Proper provisional typing

### New Capabilities
- On-demand analysis during development
- Incremental analysis of changed functions
- Call graph visualization with cycles highlighted
- Better error messages showing analysis path

### Files Modified
- Created: `lib/litmus/analyzer/recursive_analyzer.ex`
- Modified: `lib/litmus/analyzer/ast_walker.ex` (line 219)
- Modified: `lib/litmus/analyzer/project_analyzer.ex`
- Created: `test/analyzer/recursive_analyzer_test.exs`

### Performance Impact
- Initial analysis: ~10% slower due to recursion overhead
- Subsequent analyses: 50% faster due to caching
- Memory usage: +20MB for typical project cache

## Next Recommended Objective

**Objective 005: Module Cache Strategy**

With recursive analysis in place, implement a sophisticated per-module caching strategy with checksums, incremental updates, and dependency tracking. This will make the recursive analyzer performant for large codebases and enable near-instant re-analysis during development.