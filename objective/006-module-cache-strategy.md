# Objective 006: Module Cache Strategy

## Objective
Implement a sophisticated per-module caching system with checksums, incremental updates, dependency tracking, and invalidation strategies to enable near-instant re-analysis during development.

## Description
Current caching is all-or-nothing: when one dependency changes, the entire cache is invalidated. This causes full re-analysis of hundreds of modules even for single-line changes. The new cache will track individual module versions, dependencies, and provide fine-grained invalidation, making iterative development with Litmus practical for large codebases.

### Key Problems Solved
- Full cache invalidation on any change (inefficient)
- No tracking of module dependencies for invalidation
- Re-analyzes unchanged modules repeatedly
- No persistence between sessions

## Testing Criteria
1. **Cache Operations**
   - Store analysis results per module with checksums
   - Detect module changes via MD5/SHA hashing
   - Invalidate only affected modules on change
   - Track transitive dependencies for invalidation

2. **Performance**
   - Cache lookup: <1ms per module
   - Incremental update: <100ms for single module change
   - Full cache rebuild: Same as initial analysis
   - Memory usage: <100MB for 1000 modules

3. **Persistence**
   - Save cache to disk between sessions
   - Load cache on startup
   - Handle cache version migrations
   - Compress cache files

## Detailed Implementation Guidance

### File: `lib/litmus/cache/module_cache.ex`

```elixir
defmodule Litmus.Cache.ModuleCache do
  @moduledoc """
  Per-module cache with dependency tracking and incremental updates.
  """

  use GenServer

  defstruct [
    :cache,           # Module -> CacheEntry map
    :dependencies,    # Module -> Set of dependencies
    :reverse_deps,    # Module -> Set of dependents
    :checksums,       # Module -> checksum
    :version          # Cache format version
  ]

  defmodule CacheEntry do
    defstruct [
      :module,
      :checksum,
      :analysis_result,
      :dependencies,
      :analyzed_at,
      :source_path
    ]
  end

  def get(module) do
    GenServer.call(__MODULE__, {:get, module})
  end

  def put(module, result, dependencies) do
    GenServer.cast(__MODULE__, {:put, module, result, dependencies})
  end

  def invalidate(module) do
    GenServer.cast(__MODULE__, {:invalidate, module})
  end
end
```

### Key Algorithms

1. **Checksum Calculation**
   ```elixir
   defp calculate_checksum(module) do
     case get_source_path(module) do
       {:ok, path} ->
         File.read!(path)
         |> :crypto.hash(:sha256)
         |> Base.encode16()

       {:error, :no_source} ->
         # Use BEAM file checksum
         beam_checksum(module)
     end
   end
   ```

2. **Dependency Tracking**
   ```elixir
   defp track_dependencies(module, dependencies) do
     # Update forward dependencies
     state = put_in(state.dependencies[module], MapSet.new(dependencies))

     # Update reverse dependencies
     Enum.reduce(dependencies, state, fn dep, acc ->
       update_in(acc.reverse_deps[dep], fn
         nil -> MapSet.new([module])
         set -> MapSet.put(set, module)
       end)
     end)
   end
   ```

3. **Cascade Invalidation**
   ```elixir
   defp invalidate_cascade(module, state) do
     # Find all modules that depend on this one
     affected = find_affected_modules(module, state.reverse_deps)

     # Invalidate all affected modules
     Enum.reduce(affected, state, fn mod, acc ->
       %{acc | cache: Map.delete(acc.cache, mod)}
     end)
   end

   defp find_affected_modules(module, reverse_deps, visited \\ MapSet.new()) do
     if MapSet.member?(visited, module) do
       visited
     else
       visited = MapSet.put(visited, module)
       dependents = Map.get(reverse_deps, module, MapSet.new())

       Enum.reduce(dependents, visited, fn dep, acc ->
         find_affected_modules(dep, reverse_deps, acc)
       end)
     end
   end
   ```

### Persistence Strategy

```elixir
defmodule Litmus.Cache.Persistence do
  @cache_file ".litmus_cache"
  @cache_version 1

  def save(cache) do
    data = %{
      version: @cache_version,
      cache: cache,
      saved_at: DateTime.utc_now()
    }

    binary = :erlang.term_to_binary(data, [:compressed])
    File.write!(@cache_file, binary)
  end

  def load do
    case File.read(@cache_file) do
      {:ok, binary} ->
        data = :erlang.binary_to_term(binary)
        if data.version == @cache_version do
          validate_checksums(data.cache)
        else
          {:error, :version_mismatch}
        end

      {:error, _} ->
        {:error, :no_cache}
    end
  end

  defp validate_checksums(cache) do
    # Verify modules haven't changed
    valid_entries = Enum.filter(cache, fn {module, entry} ->
      current_checksum = calculate_checksum(module)
      current_checksum == entry.checksum
    end)

    {:ok, Map.new(valid_entries)}
  end
end
```

### Integration Points

1. **With AST Walker**
   ```elixir
   # Before analysis
   case ModuleCache.get(module) do
     {:ok, cached} when cached.checksum == current_checksum ->
       cached.analysis_result
     _ ->
       result = analyze_module(module)
       ModuleCache.put(module, result, extract_dependencies(result))
       result
   end
   ```

2. **With File Watcher**
   ```elixir
   # On file change
   def handle_file_change(path) do
     module = path_to_module(path)
     ModuleCache.invalidate(module)
   end
   ```

## State of Project After Implementation

### Improvements
- **Re-analysis time**: From minutes to seconds for single changes
- **Memory efficiency**: Only changed modules in memory
- **Development experience**: Near-instant feedback
- **CI performance**: Cache reuse between runs

### New Capabilities
- Incremental analysis during development
- Cache statistics and debugging
- Module dependency visualization
- Cache warming on startup
- Distributed cache sharing (team development)

### Files Modified
- Created: `lib/litmus/cache/module_cache.ex`
- Created: `lib/litmus/cache/persistence.ex`
- Modified: `lib/litmus/analyzer/ast_walker.ex`
- Modified: `lib/litmus/analyzer/project_analyzer.ex`
- Created: `lib/mix/tasks/litmus.cache.ex`

### Cache Management Commands
```bash
# Clear cache
mix litmus.cache.clear

# Show cache statistics
mix litmus.cache.stats

# Warm cache
mix litmus.cache.warm

# Export/import cache
mix litmus.cache.export > cache.dump
mix litmus.cache.import < cache.dump
```

## Next Recommended Objective

**Objective 007: Source Discovery System**

With caching in place, implement a comprehensive source discovery system that finds all analyzable files across different dependency types, build systems, and project structures. This ensures the cache covers 100% of available sources and enables complete project analysis.