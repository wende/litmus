# Objective 001: Dependency Graph Builder

## Objective
Build a complete dependency graph system that discovers all source files (Elixir, Erlang, BEAM) across the project and dependencies, establishes module relationships, detects circular dependencies, and determines the optimal analysis order.

## Description
Currently, Litmus analyzes dependencies in arbitrary order, leading to forward reference problems where functions are analyzed before their dependencies are in the cache. This causes ~30% of unknown classifications. The dependency graph will ensure modules are analyzed in topological order, with circular dependencies handled as single units.

### Key Problems Solved
- Functions analyzed before their dependencies (30% of unknowns)
- No detection of circular dependencies
- Missing source files (only finds deps/*/lib/**/*.ex)
- No support for Erlang files, umbrella apps, or non-standard layouts

## Testing Criteria
1. **Source Discovery**
   - Discovers 100% of .ex files in deps/
   - Discovers 100% of .erl files in deps/
   - Handles umbrella apps correctly
   - Falls back to BEAM files when no source available
   - Handles hex, git, path, and umbrella dependencies

2. **Graph Construction**
   - Correctly identifies all module dependencies (import, use, alias, calls)
   - Detects all circular dependency cycles
   - Produces correct topological sort for acyclic portions
   - Handles missing dependencies gracefully

3. **Performance**
   - Phoenix app (500+ modules) graph built in < 5 seconds
   - Incremental updates < 100ms for single module change
   - Memory usage < 50MB for large projects

4. **Integration**
   - `mix effect` uses dependency order automatically
   - Analysis results improve (fewer unknowns)
   - No regression in existing functionality

## Detailed Implementation Guidance

### File: `lib/litmus/dependency/graph.ex`

```elixir
defmodule Litmus.Dependency.Graph do
  @moduledoc """
  Builds complete dependency graph for all code in project and deps.
  """

  defstruct [:nodes, :edges, :reverse_edges, :source_map, :analysis_order]

  def build do
    sources = discover_all_sources()
    graph = build_module_graph(sources)
    cycles = detect_cycles(graph)
    order = topological_sort(graph)

    %__MODULE__{
      nodes: graph.nodes,
      edges: graph.edges,
      reverse_edges: build_reverse_edges(graph),
      source_map: sources,
      analysis_order: order
    }
  end
end
```

### Key Algorithms

1. **Source Discovery**
   - Parse mix.lock to understand dependency types
   - Check multiple locations per dependency type
   - Priority: .ex > .erl > .beam

2. **Dependency Extraction**
   - Parse AST for imports, uses, aliases
   - Track all function calls to external modules
   - Handle dynamic dispatch conservatively

3. **Cycle Detection** (Tarjan's Algorithm)
   - Find strongly connected components
   - Each SCC with >1 node is a cycle
   - Analyze cycles as single units

4. **Topological Sort** (Modified Kahn's Algorithm)
   - Handle cycles specially
   - Defer missing dependencies to end
   - Prioritize common dependencies

### Integration Points
- Modify `lib/litmus/analyzer/project_analyzer.ex` to use graph order
- Update `lib/mix/tasks/effect.ex` to build graph first
- Cache graph for incremental analysis

## State of Project After Implementation

### Improvements
- **Unknown classifications**: Reduced from ~15% to ~10%
- **Analysis order**: Deterministic and optimal
- **Dependency coverage**: 100% of discoverable sources
- **Circular dependency handling**: Detected and handled properly

### New Capabilities
- Visualize project structure with `mix litmus.graph`
- Incremental analysis based on dependency changes
- Better error messages showing dependency chains
- Foundation for cross-module optimization

### Files Modified
- Created: `lib/litmus/dependency/graph.ex`
- Created: `lib/litmus/discovery/source_finder.ex`
- Modified: `lib/litmus/analyzer/project_analyzer.ex`
- Modified: `lib/mix/tasks/effect.ex`

### Metrics
- Source discovery: 100% coverage
- Cycle detection: 100% accuracy
- Analysis speed: 2x faster for large projects
- Memory usage: Optimized with lazy evaluation

## Next Recommended Objective

**Objective 003: Recursive Dependency Analysis**

With the dependency graph in place, the next logical step is implementing recursive analysis that follows the graph. When analyzing a function that calls an uncached dependency, the system should recursively analyze that dependency first, ensuring all functions have complete information about their callees. This will further reduce unknown classifications and enable complete effect propagation.