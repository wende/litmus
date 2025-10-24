# OBJECTIVE.md - Complete Purity Enforcement Roadmap

> **Goal**: Achieve complete purity enforcement across project code and dependencies, eliminating all unknowns and preventing any effects from slipping through the `pure do...catch...end` construct.

**Created**: 2025-10-22
**Status**: Planning Phase

---

## Executive Summary

The Litmus project currently relies on three separate analysis systems (PURITY, AST Walker, CPS Transformer) that don't integrate properly, leading to incomplete purity enforcement. This document outlines a comprehensive plan to:

1. **Replace PURITY** with a complete AST-based analyzer
2. **Fix dependency analysis** to handle all Elixir/Erlang code
3. **Complete CPS transformation** for all language constructs
4. **Implement runtime BEAM modification** for dependency purity enforcement
5. **Build dependency graph** for complete effect tracking

**Critical Finding**: Currently, **7 major paths** allow effects to slip through, and **5 root causes** create "unknown" classifications. This plan addresses all identified issues.

---

## 1. Current State Assessment

### Component Status

| Component | Completeness | Critical Issues |
|-----------|--------------|-----------------|
| **PURITY** | 60% | Cannot handle maps (2014+), marks modern code as `:unknown` |
| **AST Walker** | 85% | Works locally but fails on dependencies, no graph analysis |
| **CPS Transformer** | 70% | Missing `cond`, `with`, recursive functions, dependency transformation |
| **Pure Macro** | 50% | No dynamic dispatch detection, captured functions skip checks |
| **Dependency Analysis** | 40% | No dependency graph, arbitrary analysis order, cache invalidation issues |

### Effect Leakage Points

1. **Dynamic dispatch** (`apply/3`) - Not detected by pure macro
2. **Captured functions** (`&IO.puts/1`) - Explicitly skipped in analysis
3. **Macro-generated code** - Expanded before purity checking
4. **Unregistered effects** - CPS transformer only tracks known effects
5. **Handler function calls** - Not transformed for effects
6. **Dependency boundaries** - No runtime enforcement
7. **Higher-order propagation** - Incomplete lambda effect tracking

---

## 2. Root Cause Analysis

### Why "Unknown" Classifications Occur

#### Cause 1: PURITY Version Incompatibility
- **Impact**: 40% of unknowns
- **Details**: PURITY from 2011 cannot parse Elixir maps (added 2014)
- **Example**: `%{key: value}` crashes PURITY → marked `:unknown`

#### Cause 2: Analysis Order Dependencies
- **Impact**: 30% of unknowns
- **Details**: Functions analyzed before their dependencies
- **Example**: `A calls B calls C`, but C not in cache yet → B marked `:unknown`

#### Cause 3: Dynamic Dispatch
- **Impact**: 15% of unknowns
- **Details**: `apply(module, function, args)` with variables
- **Example**: `apply(handler, :handle, [event])` → cannot statically resolve

#### Cause 4: Missing Source Code
- **Impact**: 10% of unknowns
- **Details**: Compiled-only dependencies, no `.ex` files
- **Example**: NIFs, Erlang stdlib modules

#### Cause 5: Macro Complexity
- **Impact**: 5% of unknowns
- **Details**: Complex macros generate code at compile-time
- **Example**: Phoenix router macros, Ecto query macros

### Why Dependencies Fail

1. **No Dependency Graph**
   - Cannot determine analysis order
   - Circular dependencies not detected
   - Forward references create unknowns

2. **Source Discovery Limitations**
   ```elixir
   # Current: Only finds deps/*/lib/**/*.ex
   # Missing: .erl files, nested deps, non-standard layouts
   Path.wildcard("#{deps_path}/*/lib/**/*.ex")
   ```

3. **Cache Invalidation Strategy**
   - All-or-nothing: One dep changes → entire cache invalid
   - No incremental updates
   - Re-analyzes everything on version changes

4. **Runtime vs Compile-Time Gap**
   - Registry empty during macro expansion
   - Effects determined at runtime, not compile-time
   - No way to modify dependency bytecode

### Why Effects Slip Through

1. **Macro Expansion Timing**
   ```elixir
   # Macros expanded BEFORE purity checking
   expanded_block = Macro.expand(block, __CALLER__)
   # If macro generates IO.puts, not detected!
   ```

2. **Captured Functions Skipped**
   ```elixir
   # Line 485-494 in pure.ex
   defp extract_call({{:., _}, _, args}) when is_atom(args) do
     nil  # Captures like &IO.puts/1 return nil → skipped!
   end
   ```

3. **Registry-Based Detection**
   ```elixir
   # Only tracks registered effects
   Registry.effect?(mfa) or Registry.effect_module?(module)
   # Unregistered effects pass through
   ```

4. **No Flow Sensitivity**
   - Cannot distinguish context-dependent purity
   - Local vs remote calls treated identically
   - No path-sensitive analysis

---

## 3. Complete Solution Architecture

### Phase Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Unified Effect System                  │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │  Dependency      │  │  Complete AST    │              │
│  │  Graph Builder   │→ │  Analyzer        │              │
│  └─────────────────┘  └─────────────────┘              │
│           ↓                     ↓                        │
│  ┌─────────────────────────────────────┐                │
│  │     Effect Registry (Complete)       │                │
│  └─────────────────────────────────────┘                │
│           ↓                     ↓                        │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │  CPS Transformer │  │  BEAM Modifier   │              │
│  │  (All Constructs)│  │  (Runtime)       │              │
│  └─────────────────┘  └─────────────────┘              │
│                                                           │
└─────────────────────────────────────────────────────────┘
```

### Key Principles

1. **Single Source of Truth**: One unified effect registry
2. **Complete Coverage**: Every function in every dependency analyzed
3. **No Escape Hatches**: All effect paths blocked
4. **Fail-Safe**: Analysis failure = compilation failure
5. **Incremental**: Per-module/per-function caching

---

## 3.1 Critical Technical Spikes

Before implementation begins, these technical experiments must validate the approach:

### Spike 1: BEAM Modification Feasibility (3 days)
**Purpose**: Determine if runtime BEAM modification is safe and performant

**Experiment**:
```elixir
defmodule BeamModificationSpike do
  def test_modify_stdlib_module do
    # 1. Try to modify String.upcase/1
    {String, beam_binary, _} = :code.get_object_code(String)
    {:ok, {_, chunks}} = :beam_lib.chunks(beam_binary, [:abstract_code])

    # 2. Attempt to inject wrapper
    # Expected: This will likely fail or corrupt the module
    # NIFs and BIFs cannot be wrapped this way

    # 3. Measure performance impact
    # If successful, benchmark 1000 calls before/after
  end

  def test_modify_user_module do
    # Test on a simple user-defined module
    # This is more likely to succeed than stdlib
  end

  def test_concurrent_modification do
    # What happens if module is being executed during :code.purge?
    # Spawn 100 processes calling the function
    # Modify module mid-execution
    # Check for crashes/deadlocks
  end
end
```

**Success Criteria**:
- Can modify user modules without crashes
- Performance overhead < 5% per call
- No concurrency issues in 10,000 iterations

**Fallback if Spike Fails**:
- Use compile-time macro transformation only
- Implement `pure` blocks as GenServer with effect tracking
- Accept that dependency effects cannot be fully controlled

### Spike 2: Erlang Abstract Format Conversion (2 days)
**Purpose**: Validate ability to analyze `.erl` files

**Experiment**:
```elixir
defmodule ErlangAnalysisSpike do
  def parse_erlang_module(module) do
    # Get abstract format from BEAM
    {:ok, {_, [{:abstract_code, {_, abstract_code}}]}} =
      :beam_lib.chunks(:code.which(module), [:abstract_code])

    # Convert to something analyzable
    # Options:
    # 1. Convert to Elixir AST (lossy)
    # 2. Analyze Erlang abstract format directly
    # 3. Use erl_syntax tools

    analyze_forms(abstract_code)
  end

  def test_common_modules do
    # Test on :lists, :maps, :ets, :gen_server
    # Can we detect their effects accurately?
  end
end
```

**Success Criteria**:
- Parse 50 common Erlang stdlib modules
- Correctly identify pure vs impure functions in 90% of cases
- Handle Erlang-specific constructs (receive, '!', etc.)

### Spike 3: Protocol Dispatch Resolution (2 days)
**Purpose**: Determine if we can statically resolve protocol implementations

**Experiment**:
```elixir
defmodule ProtocolResolutionSpike do
  def resolve_enumerable(data_type) do
    # Given a data type at compile time
    # Can we determine which Enumerable implementation?

    # Test cases:
    # - List → Enumerable.List
    # - Range → Enumerable.Range
    # - Map → Enumerable.Map
    # - Custom struct → ???

    # Key challenge: Structs defined in other modules
  end

  def analyze_enum_map_effects do
    # Enum.map([1,2,3], &IO.puts/1)
    # Can we trace through protocol to detect IO.puts effect?
  end
end
```

**Success Criteria**:
- Resolve built-in types (List, Map, Range) → 100% accuracy
- Resolve user structs in same project → 80% accuracy
- Gracefully fall back to :unknown for unresolvable cases

### Spike 4: Recursive Dependency Analysis Performance (2 days)
**Purpose**: Validate that recursive analysis scales

**Experiment**:
```elixir
defmodule PerformanceSpike do
  def analyze_phoenix_project do
    # Download and analyze a full Phoenix app
    # Measure: time, memory, cache size

    # Test scenarios:
    # 1. Cold analysis (no cache)
    # 2. Warm analysis (full cache)
    # 3. Incremental (change 1 file)
  end

  def measure_memory_usage do
    # Track memory during analysis of 1000+ modules
    # Identify memory leaks or excessive allocation
  end
end
```

**Success Criteria**:
- Phoenix app (500+ modules) analyzed in < 30 seconds
- Memory usage < 500MB for large projects
- Incremental analysis < 1 second for single file change

---

## 4. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-2)

#### Task 1: Build Complete Dependency Graph
**File**: `lib/litmus/dependency/graph.ex`
```elixir
defmodule Litmus.Dependency.Graph do
  @moduledoc """
  Builds complete dependency graph for all code in project and deps.
  """

  defstruct [:nodes, :edges, :reverse_edges, :source_map, :analysis_order]

  def build do
    # Phase 1: Discover all sources
    sources = discover_all_sources()

    # Phase 2: Build module dependency graph
    graph = build_module_graph(sources)

    # Phase 3: Detect cycles
    cycles = detect_cycles(graph)

    # Phase 4: Compute analysis order
    order = topological_sort(graph)

    %__MODULE__{
      nodes: graph.nodes,
      edges: graph.edges,
      reverse_edges: build_reverse_edges(graph),
      source_map: sources,
      analysis_order: order
    }
  end

  @doc """
  Discovers all source files in project and dependencies.
  """
  def discover_all_sources do
    %{
      project: discover_project_sources(),
      deps: discover_dependency_sources(),
      erlang: discover_erlang_sources()
    }
  end

  defp discover_dependency_sources do
    # 1. Parse mix.lock for dependency info
    {:ok, lock} = read_mix_lock()

    deps_path = Mix.Project.deps_path()

    Enum.flat_map(lock, fn {dep_name, dep_info} ->
      case dep_info do
        # Hex dependency
        {:hex, _package, version, _hash, _managers, _deps, _hexpm, _hash2} ->
          find_hex_sources(deps_path, dep_name, version)

        # Git dependency
        {:git, url, ref, _opts} ->
          find_git_sources(deps_path, dep_name, url, ref)

        # Path dependency
        {:path, path, _opts} ->
          find_path_sources(path)

        # Umbrella app
        {:umbrella, app_name, _opts} ->
          find_umbrella_sources(app_name)
      end
    end)
  end

  defp find_hex_sources(deps_path, name, version) do
    base = Path.join(deps_path, to_string(name))

    # Priority order for source discovery
    sources = []

    # 1. Elixir source files
    sources = sources ++ Path.wildcard("#{base}/lib/**/*.ex")

    # 2. Erlang source files (some deps are Erlang)
    sources = sources ++ Path.wildcard("#{base}/src/**/*.erl")

    # 3. Check for .app.src for Erlang projects
    app_src = Path.join([base, "src", "#{name}.app.src"])
    if File.exists?(app_src) do
      sources = [{:app_src, app_src} | sources]
    end

    # 4. Compiled BEAM files (fallback if no source)
    if sources == [] do
      beam_files = Path.wildcard("#{base}/ebin/*.beam")
      Enum.map(beam_files, &{:beam_only, &1})
    else
      Enum.map(sources, &{:source, &1})
    end
  end

  defp find_git_sources(deps_path, name, url, ref) do
    # Git dependencies may have subdirectories
    base = Path.join(deps_path, to_string(name))

    # Check if this is an umbrella project
    if File.exists?(Path.join(base, "apps")) do
      Path.wildcard("#{base}/apps/*/lib/**/*.ex")
      |> Enum.map(&{:source, &1})
    else
      find_hex_sources(deps_path, name, "git:#{ref}")
    end
  end
end
```

**Detailed Implementation**:
1. **Source Discovery Algorithm**:
   ```elixir
   # Priority order for finding sources:
   # 1. .ex files in lib/ (Elixir)
   # 2. .erl files in src/ (Erlang)
   # 3. .beam files in ebin/ (compiled only)
   # 4. Handle special cases:
   #    - Umbrella apps (apps/*/lib/**/*.ex)
   #    - Rebar3 projects (different structure)
   #    - Archives (.ez files)
   ```

2. **Module Dependency Extraction**:
   ```elixir
   def extract_dependencies(ast) do
     # Find all:
     # - import Module
     # - use Module
     # - alias Module
     # - Module.function() calls
     # - Kernel.apply/3 calls (mark as dynamic)
     # - Protocol implementations
   end
   ```

3. **Cycle Detection (Tarjan's Algorithm)**:
   ```elixir
   def detect_cycles(graph) do
     # Returns list of strongly connected components
     # Each SCC with >1 node is a cycle
   end
   ```

4. **Analysis Order Computation**:
   ```elixir
   def topological_sort(graph) do
     # Modified Kahn's algorithm that handles:
     # - Cycles (analyze as single unit)
     # - Missing dependencies (defer to end)
     # - Priority weights (analyze common deps first)
   end
   ```

#### Task 2: Fix AST Walker Dependency Resolution
**File**: `lib/litmus/analyzer/ast_walker.ex`
```elixir
# Current (line 219):
Registry.runtime_cache()[mfa]  # Returns nil if not cached

# Fixed:
analyze_dependency_if_needed(mfa)  # Recursively analyze
Registry.runtime_cache()[mfa]      # Now guaranteed in cache
```

**Changes**:
1. Add `analyze_dependency_if_needed/1` function
2. Recursively analyze missing dependencies
3. Cache results immediately
4. Handle circular dependencies with provisional types

#### Task 3: Implement Recursive Analysis with Memoization
**File**: `lib/litmus/analyzer/recursive_analyzer.ex`
```elixir
defmodule Litmus.Analyzer.RecursiveAnalyzer do
  use GenServer

  # Maintains analysis stack to detect cycles
  # Memoizes results to avoid re-analysis
  # Handles provisional typing for recursion
end
```

#### Task 4: Complete Source Discovery
**File**: `lib/litmus/discovery/source_finder.ex`
```elixir
defmodule Litmus.Discovery.SourceFinder do
  def find_all_sources do
    # Find .ex files in deps/*/lib
    # Find .erl files in deps/*/src
    # Find .beam files without source
    # Handle umbrella apps
    # Handle path dependencies
  end
end
```

#### Task 5: Per-Module Cache Strategy
**File**: `lib/litmus/cache/module_cache.ex`
```elixir
defmodule Litmus.Cache.ModuleCache do
  # Per-module checksums
  # Incremental updates
  # Dependency tracking
  # Invalidation on upstream changes
end
```

### Phase 2: Complete Analysis (Weeks 3-4)

#### Task 6: Replace PURITY with Enhanced AST Walker
**Action**: Remove all PURITY dependencies
```elixir
# Remove:
- lib/litmus.ex lines calling PURITY
- purity_source/ directory
- PURITY references in pure.ex

# Replace with:
Litmus.Analyzer.Complete.analyze_beam/1  # For compiled modules
Litmus.Analyzer.Complete.analyze_ast/1   # For source modules
```

**New Analyzer Features**:
1. Handle all Elixir constructs (maps, structs, protocols)
2. Analyze Erlang modules via abstract format
3. Complete pattern matching support
4. Guard analysis for exceptions
5. Macro expansion with proper context

#### Task 7: Eliminate All Unknown Classifications
**Strategy**:
```elixir
defmodule Litmus.Analyzer.Complete do
  def analyze(mfa) do
    case find_source(mfa) do
      {:ok, source} -> analyze_source(source)
      {:error, :no_source} -> analyze_beam(mfa)
      {:error, :no_beam} -> conservative_inference(mfa)
    end
  end

  defp conservative_inference(mfa) do
    # Use naming conventions as HINTS not conclusions
    # Check arity and common patterns
    # Default to :side_effects not :unknown
  end
end
```

#### Task 8: Complete Exception Type Tracking
**Enhancement**:
```elixir
# Track specific exception types through:
- raise statements
- throw statements
- exit statements
- Guard failures (new!)
- Kernel.!/1 functions
- Pattern match failures

# Propagate through:
- Function calls
- try/catch boundaries
- Higher-order functions
```

#### Task 9: Dynamic Dispatch Analysis
**File**: `lib/litmus/analyzer/dynamic_dispatch.ex`
```elixir
defmodule Litmus.Analyzer.DynamicDispatch do
  # Track apply/3 calls
  # Analyze possible values via data flow
  # Use type inference to narrow possibilities
  # Mark as :dynamic_dispatch effect type
end
```

#### Task 10: Captured Function Detection
**Fix in**: `lib/litmus/pure.ex`
```elixir
# Current: Skips captures
defp extract_call({{:., _}, _, args}) when is_atom(args), do: nil

# Fixed: Analyze captures
defp extract_call({{:., _, [module, function]}, _, args}) when is_atom(args) do
  arity = :erlang.fun_info(args)[:arity]
  {module, function, arity}  # Return MFA for checking
end
```

### Phase 3: Complete CPS Transformation (Weeks 5-6)

#### Task 11: Support All Control Flow Constructs
**File**: `lib/litmus/effects/transformer.ex`

**Complete CPS Transformation Specifications**:

```elixir
defmodule Litmus.Effects.Transformer.ControlFlow do
  @moduledoc """
  CPS transformation for all Elixir control flow constructs.
  """

  # 1. COND EXPRESSIONS
  @doc """
  Transform cond to thread continuation through all branches.
  Key challenge: Short-circuit evaluation must be preserved.
  """
  defp transform_ast({:cond, meta, [[do: clauses]]}, opts) do
    cont_var = Macro.var(:__litmus_cont, __MODULE__)

    transformed_clauses = Enum.map(clauses, fn {:->, clause_meta, [[condition], body]} ->
      # Transform condition (may have effects!)
      {transformed_condition, condition_effects} = transform_expression(condition, opts)

      # Transform body with continuation
      transformed_body = transform_block(body, opts)

      # If condition has effects, wrap in effect handler
      if has_effects?(condition_effects) do
        quote do
          unquote(condition_effects).(fn condition_result ->
            if condition_result do
              unquote(transformed_body).(unquote(cont_var))
            else
              # Continue to next clause
              :litmus_continue_cond
            end
          end)
        end
      else
        {:->, clause_meta, [[transformed_condition],
          quote do: unquote(transformed_body).(unquote(cont_var))
        ]}
      end
    end)

    # Build the cond with proper continuation threading
    quote do
      fn unquote(cont_var) ->
        result = cond do
          unquote_splicing(transformed_clauses)
        end

        # Handle the case where no clause matched
        case result do
          :litmus_continue_cond -> raise CondClauseError
          other -> other
        end
      end
    end
  end

  # 2. WITH EXPRESSIONS
  @doc """
  Transform with to handle pattern matching and early returns.
  Complex because of <- operator and else clauses.
  """
  defp transform_ast({:with, meta, args}, opts) do
    # Extract steps and else clause
    {steps, [[do: do_block] | rest]} = Enum.split_while(args, fn
      {:do, _} -> false
      {:else, _} -> false
      _ -> true
    end)

    else_clauses = Keyword.get(rest, :else, [])

    # Transform each step into nested continuations
    transform_with_steps(steps, do_block, else_clauses, opts)
  end

  defp transform_with_steps([], do_block, _else_clauses, opts) do
    # Base case: all steps succeeded, execute do block
    transform_block(do_block, opts)
  end

  defp transform_with_steps([step | rest], do_block, else_clauses, opts) do
    case step do
      # Pattern matching step: pattern <- expression
      {:<-, _meta, [pattern, expression]} ->
        {transformed_expr, expr_effects} = transform_expression(expression, opts)
        rest_transformation = transform_with_steps(rest, do_block, else_clauses, opts)

        quote do
          fn __cont ->
            # Evaluate expression with effects
            unquote(expr_effects).(fn expr_result ->
              # Try to match pattern
              case expr_result do
                unquote(pattern) ->
                  # Pattern matched, continue with rest
                  unquote(rest_transformation).(__cont)

                other ->
                  # Pattern failed, execute else clause
                  unquote(transform_else_clauses(else_clauses, opts)).(__cont, other)
              end
            end)
          end
        end

      # Regular expression step (no pattern matching)
      expression ->
        {transformed_expr, expr_effects} = transform_expression(expression, opts)
        rest_transformation = transform_with_steps(rest, do_block, else_clauses, opts)

        quote do
          fn __cont ->
            unquote(expr_effects).(fn _result ->
              unquote(rest_transformation).(__cont)
            end)
          end
        end
    end
  end

  defp transform_else_clauses([], _opts) do
    # No else clauses, return error
    quote do
      fn _cont, value ->
        {:error, {:nomatch, value}}
      end
    end
  end

  defp transform_else_clauses(clauses, opts) do
    transformed = Enum.map(clauses, fn {:->, meta, [[pattern], body]} ->
      transformed_body = transform_block(body, opts)

      {:->, meta, [[pattern],
        quote do: unquote(transformed_body).(__cont)
      ]}
    end)

    quote do
      fn __cont, value ->
        case value do
          unquote_splicing(transformed)
        end
      end
    end
  end

  # 3. RECURSIVE FUNCTIONS
  @doc """
  Transform recursive functions to pass recursion point through CPS.
  Critical: Must handle tail recursion properly for performance.
  """
  defp transform_ast({:def, meta, [name, args, [do: body]]}, opts) when is_list(args) do
    # Add continuation and recursion parameters
    cont_param = Macro.var(:__cont, __MODULE__)
    rec_param = Macro.var(:__rec, __MODULE__)

    # Create recursive wrapper
    rec_name = :"#{name}_rec"

    # Transform body with recursion context
    rec_opts = Map.put(opts, :recursion_point, {rec_name, length(args)})
    transformed_body = transform_block(body, rec_opts)

    quote do
      # Public function initiates recursion
      def unquote(name)(unquote_splicing(args)) do
        # Create initial continuation
        initial_cont = fn result -> result end

        # Create recursion point
        rec_point = fn unquote_splicing(args), unquote(cont_param) ->
          unquote(rec_name)(unquote_splicing(args), unquote(cont_param), rec_point)
        end

        # Start recursion
        unquote(rec_name)(unquote_splicing(args), initial_cont, rec_point)
      end

      # Private recursive implementation
      defp unquote(rec_name)(unquote_splicing(args), unquote(cont_param), unquote(rec_param)) do
        # Body has access to recursion point via rec_param
        unquote(transformed_body)
      end
    end
  end

  # Handle recursive calls within transformed body
  defp transform_call({name, meta, args}, %{recursion_point: {name, arity}} = opts)
       when length(args) == arity do
    # This is a recursive call
    rec_param = Macro.var(:__rec, __MODULE__)
    cont_param = Macro.var(:__cont, __MODULE__)

    # Transform arguments (may have effects)
    {transformed_args, arg_effects} = transform_arguments(args, opts)

    quote do
      # Evaluate arguments, then make recursive call
      unquote(arg_effects).(fn evaluated_args ->
        # Tail-recursive call passes current continuation
        unquote(rec_param).(unquote_splicing(evaluated_args), unquote(cont_param))
      end)
    end
  end

  # 4. MULTI-CLAUSE FUNCTIONS
  @doc """
  Transform functions with multiple clauses.
  Each clause gets same continuation structure.
  """
  defp transform_ast({:def, meta, [name, clauses]}, opts) when is_list(clauses) do
    transformed_clauses = Enum.map(clauses, fn
      {:->, clause_meta, [args, body]} ->
        cont_param = Macro.var(:__cont, __MODULE__)
        transformed_body = transform_block(body, opts)

        {:->, clause_meta, [args ++ [cont_param],
          quote do: unquote(transformed_body).(unquote(cont_param))
        ]}
    end)

    quote do
      def unquote(name) do
        fn unquote_splicing(transformed_clauses) end
      end
    end
  end

  # 5. TRY-CATCH-RESCUE-AFTER
  @doc """
  Transform exception handling to work with CPS.
  Complex: Must preserve exception semantics while threading continuations.
  """
  defp transform_ast({:try, meta, [[do: do_block] | rest]}, opts) do
    rescue_clauses = Keyword.get(rest, :rescue, [])
    catch_clauses = Keyword.get(rest, :catch, [])
    else_clauses = Keyword.get(rest, :else, [])
    after_block = Keyword.get(rest, :after, nil)

    cont_var = Macro.var(:__cont, __MODULE__)

    # Transform main block
    transformed_do = transform_block(do_block, opts)

    # Build protected execution
    quote do
      fn unquote(cont_var) ->
        try do
          # Execute transformed block with special error-catching continuation
          error_cont = fn
            {:litmus_effect_error, effect} ->
              # Effect wasn't handled, propagate
              raise Litmus.Effects.UnhandledError, effect: effect

            {:litmus_exception, kind, reason, stacktrace} ->
              # Exception occurred during effect execution
              :erlang.raise(kind, reason, stacktrace)

            result ->
              # Normal completion
              unquote(cont_var).(result)
          end

          unquote(transformed_do).(error_cont)
        unquote_splicing(
          transform_exception_clauses(rescue_clauses, :rescue, cont_var, opts)
        )
        unquote_splicing(
          transform_exception_clauses(catch_clauses, :catch, cont_var, opts)
        )
        unquote(
          if after_block do
            quote do
              after
                unquote(transform_block(after_block, opts)).(fn _ -> :ok end)
            end
          end
        )
        end
      end
    end
  end

  # 6. RECEIVE BLOCKS (for GenServer and process communication)
  @doc """
  Transform receive blocks while preserving message ordering.
  Critical for OTP compatibility.
  """
  defp transform_ast({:receive, meta, [[do: clauses] | rest]}, opts) do
    after_clause = Keyword.get(rest, :after, nil)
    cont_var = Macro.var(:__cont, __MODULE__)

    transformed_clauses = Enum.map(clauses, fn {:->, clause_meta, [[pattern], body]} ->
      transformed_body = transform_block(body, opts)

      {:->, clause_meta, [[pattern],
        quote do: unquote(transformed_body).(unquote(cont_var))
      ]}
    end)

    quote do
      fn unquote(cont_var) ->
        receive do
          unquote_splicing(transformed_clauses)
        unquote(
          if after_clause do
            {timeout, after_body} = after_clause
            transformed_after = transform_block(after_body, opts)

            quote do
              after
                unquote(timeout) ->
                  unquote(transformed_after).(unquote(cont_var))
            end
          end
        )
        end
      end
    end
  end
end
```

**Critical Implementation Details**:

1. **Effect Detection in Conditions**:
   - Guards may contain effects (e.g., `when IO.puts(x)`)
   - Must evaluate conditions with effect handling
   - Preserve short-circuit evaluation

2. **Pattern Matching Semantics**:
   - Failed patterns in `with` must trigger else clauses
   - Variables bound in patterns must be available in continuation
   - Anonymous variables `_` must not create bindings

3. **Tail Call Optimization**:
   - Recursive calls in tail position must not grow stack
   - Use trampoline pattern if needed
   - Detect tail position accurately

4. **Exception Propagation**:
   - Exceptions in effects must propagate correctly
   - Maintain proper stacktraces
   - After blocks must always execute

5. **Performance Considerations**:
   - Minimize closure allocation
   - Inline simple continuations
   - Detect and optimize pure expressions

#### Task 12: Transform Dependency Code at Compile Time
**File**: `lib/litmus/compiler/dependency_transformer.ex`
```elixir
defmodule Litmus.Compiler.DependencyTransformer do
  def transform_dependency(module) do
    # Get module AST
    {:ok, {_, [{:abstract_code, {_, ac}}]}} =
      :beam_lib.chunks(module, [:abstract_code])

    # Convert to Elixir AST
    ast = :erl_syntax.form_list(ac) |> erlang_to_elixir()

    # Apply CPS transformation
    transformed = Litmus.Effects.Transformer.transform(ast)

    # Recompile module
    Code.compile_quoted(transformed)
  end
end
```

#### Task 13: Runtime BEAM Modification
**File**: `lib/litmus/runtime/beam_modifier.ex`

**CRITICAL WARNING**: BEAM modification is extremely dangerous and may not be feasible. See Spike 1 results first.

```elixir
defmodule Litmus.Runtime.BeamModifier do
  @moduledoc """
  Modifies BEAM bytecode to inject effect checking at runtime.

  IMPORTANT: This is a last-resort approach. Prefer compile-time transformation.
  """

  require Logger

  @doc """
  Timing: Called during application startup for dependencies
  """
  def inject_purity_checks(module) when is_atom(module) do
    case prepare_module_for_modification(module) do
      {:ok, prepared} -> modify_module(prepared)
      {:error, :nif_module} -> {:skip, "NIFs cannot be modified"}
      {:error, :bif_module} -> {:skip, "BIFs cannot be modified"}
      {:error, :no_abstract_code} -> fallback_modification(module)
    end
  end

  defp prepare_module_for_modification(module) do
    # 1. Check if module can be modified
    case :code.which(module) do
      :non_existing -> {:error, :module_not_loaded}
      :preloaded -> {:error, :bif_module}
      beam_path ->
        # 2. Get module info
        case :beam_lib.chunks(beam_path, [:abstract_code, :attributes]) do
          {:ok, {^module, chunks}} ->
            case chunks[:abstract_code] do
              {:abstract_code, {:raw_abstract_v1, forms}} ->
                {:ok, %{module: module, forms: forms, path: beam_path}}
              _ ->
                {:error, :no_abstract_code}
            end
          {:error, _, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Actual modification strategy - Three approaches based on feasibility
  """
  def modify_module(%{module: module, forms: forms, path: path}) do
    # Approach 1: AST-level modification (Preferred)
    case modify_via_ast(module, forms) do
      {:ok, new_module} ->
        {:ok, new_module, :ast_modified}

      {:error, :ast_modification_failed} ->
        # Approach 2: Bytecode injection (Fallback)
        case modify_via_bytecode(module, path) do
          {:ok, new_module} ->
            {:ok, new_module, :bytecode_injected}

          {:error, :bytecode_injection_failed} ->
            # Approach 3: Runtime wrapper (Last resort)
            modify_via_wrapper(module)
        end
    end
  end

  # Approach 1: Modify at AST level (safest if abstract_code available)
  defp modify_via_ast(module, forms) do
    try do
      # Transform each function to add effect checks
      new_forms = Enum.map(forms, &transform_form(&1, module))

      # Recompile the module
      case :compile.forms(new_forms, [:return_errors]) do
        {:ok, ^module, binary, _warnings} ->
          load_modified_module(module, binary)

        {:error, errors, _warnings} ->
          Logger.error("AST modification failed: #{inspect(errors)}")
          {:error, :ast_modification_failed}
      end
    rescue
      e ->
        Logger.error("AST transformation error: #{inspect(e)}")
        {:error, :ast_modification_failed}
    end
  end

  # Transform individual function forms
  defp transform_form({:function, line, name, arity, clauses} = form, module) do
    # Check if function is effectful
    mfa = {module, name, arity}

    case Registry.effect_type(mfa) do
      :p -> form  # Pure, no modification needed

      effect_type ->
        # Inject effect check at function entry
        new_clauses = Enum.map(clauses, fn {:clause, cl_line, args, guards, body} ->
          # Add effect check as first expression in body
          check_expr = quote_erlang do
            litmus_effect_check({unquote(module), unquote(name), unquote(arity)})
          end

          new_body = [check_expr | body]
          {:clause, cl_line, args, guards, new_body}
        end)

        {:function, line, name, arity, new_clauses}
    end
  end

  defp transform_form(other_form, _module), do: other_form

  # Approach 2: Direct bytecode injection (dangerous, may corrupt module)
  defp modify_via_bytecode(module, beam_path) do
    # WARNING: This is extremely fragile and version-dependent

    # Read BEAM file
    {:ok, binary} = File.read(beam_path)

    # Parse BEAM chunks
    case :beam_lib.chunks(binary, [:all]) do
      {:ok, {^module, chunks}} ->
        # Modify the Code chunk (actual bytecode)
        # This requires deep knowledge of BEAM instruction set
        # and is highly likely to break

        Logger.warn("Bytecode injection not implemented - too dangerous")
        {:error, :bytecode_injection_failed}

      _ ->
        {:error, :bytecode_injection_failed}
    end
  end

  # Approach 3: Runtime wrapper via module renaming (safest fallback)
  defp modify_via_wrapper(module) do
    # Strategy: Rename original module and create wrapper

    # 1. Get all exported functions
    exports = module.__info__(:functions)

    # 2. Create wrapper module dynamically
    wrapper_name = :"#{module}_litmus_wrapper"
    original_name = :"#{module}_litmus_original"

    # 3. Rename original module (if possible)
    case rename_module(module, original_name) do
      :ok ->
        # 4. Create wrapper module that delegates through effect checks
        create_wrapper_module(module, wrapper_name, original_name, exports)

      {:error, reason} ->
        {:error, {:wrapper_creation_failed, reason}}
    end
  end

  defp rename_module(old_name, new_name) do
    # Get module binary
    case :code.get_object_code(old_name) do
      {^old_name, binary, filename} ->
        # Purge old module
        :code.purge(old_name)
        :code.delete(old_name)

        # Load with new name
        case :code.load_binary(new_name, filename, binary) do
          {:module, ^new_name} -> :ok
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, :module_not_found}
    end
  end

  defp create_wrapper_module(wrapper_name, _original_name, original_module, exports) do
    # Generate wrapper functions dynamically
    ast = quote do
      defmodule unquote(wrapper_name) do
        unquote_splicing(
          Enum.map(exports, fn {func, arity} ->
            args = Macro.generate_arguments(arity, __MODULE__)

            quote do
              def unquote(func)(unquote_splicing(args)) do
                # Check if effect is allowed
                Litmus.Runtime.EffectGuard.check_effect(
                  {unquote(original_module), unquote(func), unquote(arity)}
                )

                # Delegate to original
                apply(unquote(original_module), unquote(func), unquote(args))
              end
            end
          end)
        )
      end
    end

    # Compile and load wrapper
    Code.eval_quoted(ast)
    {:ok, wrapper_name, :runtime_wrapper}
  end

  @doc """
  Fallback for modules without abstract code (NIFs, stripped BEAM files)
  """
  def fallback_modification(module) do
    # For modules we can't modify, we need a different strategy

    case module do
      # Known stdlib modules - use predetermined effect classifications
      mod when mod in [:file, :io, :ets, :gen_server] ->
        register_known_effects(mod)
        {:ok, mod, :effects_registered}

      # Unknown modules - mark all functions as potentially effectful
      _ ->
        mark_module_unsafe(module)
        {:ok, module, :marked_unsafe}
    end
  end

  @doc """
  Load modified module safely with rollback capability
  """
  defp load_modified_module(module, binary) do
    # Save original for rollback
    original = :code.get_object_code(module)

    # Purge old version (DANGEROUS - in-flight calls may crash)
    :code.purge(module)

    # Load new version
    case :code.load_binary(module, ~c"litmus_modified", binary) do
      {:module, ^module} ->
        # Test the modified module
        if test_modified_module(module) do
          {:ok, module}
        else
          # Rollback
          rollback_module(module, original)
          {:error, :modification_test_failed}
        end

      {:error, reason} ->
        # Rollback
        rollback_module(module, original)
        {:error, reason}
    end
  end

  defp test_modified_module(module) do
    # Run basic sanity checks
    try do
      # Check module still exports expected functions
      _exports = module.__info__(:functions)
      true
    rescue
      _ -> false
    end
  end

  defp rollback_module(module, {module, original_binary, filename}) do
    :code.purge(module)
    :code.load_binary(module, filename, original_binary)
  end
end
```

**Critical Implementation Considerations**:

1. **When Modification Happens**:
   - **Option A**: Application startup (one-time cost, but delays startup)
   - **Option B**: On-demand during first `pure` block (lazy, but runtime cost)
   - **Option C**: During dependency compilation (requires Mix compiler hook)
   - **Recommended**: Option C with fallback to Option A

2. **Concurrency Safety**:
   ```elixir
   # Must handle modules being called during modification
   def safe_modify(module) do
     # 1. Create modified version with new name first
     temp_module = :"#{module}_temp"
     create_modified(module, temp_module)

     # 2. Atomic swap using code server
     :global.trans(
       {{:litmus_modify, module}, self()},
       fn ->
         :code.purge(module)
         rename_module(temp_module, module)
       end
     )
   end
   ```

3. **Rollback Strategy**:
   - Keep original BEAM files in `.litmus/rollback/`
   - Provide `mix litmus.rollback` command
   - Auto-rollback on startup failures

4. **Performance Impact**:
   - One-time cost during modification: ~10ms per module
   - Runtime cost per effect check: ~0.1μs
   - Memory overhead: ~5KB per modified module

5. **Limitations**:
   - Cannot modify NIFs (native code)
   - Cannot modify BIFs (built-in functions)
   - Cannot modify preloaded modules
   - Hot code reload may restore original

### Phase 4: Integration and Validation (Weeks 7-8)

#### Task 14: Unified Pure Macro
**File**: `lib/litmus/pure.ex` (complete rewrite)
```elixir
defmodule Litmus.Pure do
  defmacro pure(opts \\ [], do: block) do
    quote do
      # 1. Build complete effect registry first
      Litmus.Analyzer.Complete.ensure_all_analyzed()

      # 2. Transform block with CPS
      transformed = Litmus.Effects.Transformer.transform(unquote(block))

      # 3. Verify NO effects can escape
      Litmus.Verifier.verify_pure(transformed)

      # 4. Execute with handlers
      Litmus.Effects.run(transformed, unquote(opts[:catch] || []))
    end
  end
end
```

**Key Changes**:
- Pre-analyze all dependencies
- Transform BEFORE verification
- Verify at AST level not call level
- Runtime enforcement via handlers

#### Task 15: Complete Test Coverage
**Files**: `test/complete_purity_test.exs`
```elixir
defmodule CompletePurityTest do
  use ExUnit.Case

  describe "no effects can escape" do
    test "direct calls blocked"
    test "apply/3 blocked"
    test "captured functions blocked"
    test "macro-generated effects blocked"
    test "handler effects transformed"
    test "dependency effects blocked"
    test "higher-order effects tracked"
  end

  describe "all constructs supported" do
    test "cond expressions"
    test "with expressions"
    test "recursive functions"
    test "multi-clause functions"
    test "try/catch/rescue/after"
    test "receive blocks"
  end
end
```

---

## 5. Technical Specifications

### Dependency Graph Algorithm

```elixir
defmodule Litmus.Dependency.Graph do
  defstruct nodes: %{}, edges: %{}, reverse: %{}

  def build do
    # 1. Parse mix.lock for all dependencies
    # 2. For each dependency:
    #    - Find all modules
    #    - Parse imports/uses/aliases
    #    - Build edges
    # 3. Detect cycles with Tarjan's algorithm
    # 4. Topological sort
    # 5. Return analysis order
  end

  def topological_sort(graph) do
    # Kahn's algorithm
    # Start with nodes with no incoming edges
    # Remove node, add to sorted list
    # Remove outgoing edges
    # Repeat until empty
  end
end
```

### AST Transformation Rules

```elixir
# Rule 1: Effect calls become continuations
File.read!(path)                    → effect({File, :read!, [path]}, fn result -> ... end)

# Rule 2: Assignments extract return value
x = File.read!(path)                → effect({File, :read!, [path]}, fn x -> ... end)

# Rule 3: Pure code passes through
String.upcase(x)                    → String.upcase(x)

# Rule 4: Control flow threads continuation
if cond, do: effect(), else: pure() → if cond, do: effect(..., cont), else: cont.(pure())

# Rule 5: Nested effects chain
effect1(); effect2()                → effect(sig1, fn _ -> effect(sig2, fn _ -> ... end) end)
```

### BEAM Modification Approach

```elixir
defmodule Litmus.Runtime.BeamModifier do
  def modify_module(module) when is_atom(module) do
    # 1. Get bytecode
    {module, binary, _} = :code.get_object_code(module)

    # 2. Parse bytecode
    {:ok, {_, chunks}} = :beam_lib.chunks(binary, [:abstract_code])

    # 3. Transform abstract code
    {:abstract_code, {_, forms}} = chunks[:abstract_code]
    new_forms = transform_forms(forms)

    # 4. Recompile
    {:ok, module, new_binary} = :compile.forms(new_forms)

    # 5. Load modified version
    :code.purge(module)
    {:module, module} = :code.load_binary(module, '', new_binary)
  end
end
```

### Effect Propagation Rules

1. **Direct Call**: Effect of callee propagates to caller
2. **Higher-Order**: Lambda effect propagates through HOF
3. **Conditional**: Union of all branch effects
4. **Try-Catch**: Caught exceptions removed from effect
5. **Sequential**: Union of all statement effects
6. **Closure**: Captured effects + body effects

---

## 5.1 Error Taxonomy

Complete specification of all error types and their user-facing messages:

### Compilation Errors

```elixir
defmodule Litmus.Errors do
  @moduledoc "All error types with user-friendly messages"

  defmodule ImpurityError do
    defexception [:mfa, :effect_type, :location, :context]

    def message(%{mfa: {m, f, a}, effect_type: type, location: loc, context: ctx}) do
      """
      Impure function call detected in pure block

      Function: #{inspect(m)}.#{f}/#{a}
      Effect type: #{format_effect(type)}
      Location: #{format_location(loc)}
      Context: #{ctx}

      Suggestions:
      #{suggestions_for(type)}
      """
    end

    defp format_effect(:s), do: "Side effects (I/O, process operations)"
    defp format_effect(:d), do: "Dependent on environment (time, process dict)"
    defp format_effect(:n), do: "Native code (NIF)"
    defp format_effect(:u), do: "Unknown (cannot be analyzed)"
    defp format_effect({:e, exceptions}), do: "May raise: #{Enum.join(exceptions, ", ")}"
    defp format_effect(:l), do: "Lambda-dependent (effect depends on function argument)"

    defp suggestions_for(:s) do
      """
      • Add a catch handler for this effect
      • Move this operation outside the pure block
      • Use a pure alternative if available
      """
    end

    defp suggestions_for(:u) do
      """
      • Ensure the module has debug_info compiled
      • Check if this is a dynamic dispatch (apply/3)
      • Consider adding explicit effect annotation
      """
    end
  end

  defmodule AnalysisError do
    defexception [:module, :reason, :suggestion]

    def message(%{module: mod, reason: reason, suggestion: sugg}) do
      """
      Failed to analyze module: #{inspect(mod)}

      Reason: #{format_reason(reason)}

      #{sugg}
      """
    end

    defp format_reason(:no_beam), do: "Module not compiled or BEAM file not found"
    defp format_reason(:no_source), do: "Source file not found"
    defp format_reason(:no_debug_info), do: "Module compiled without debug_info"
    defp format_reason({:parse_error, details}), do: "Parse error: #{details}"
    defp format_reason(:circular_dependency), do: "Circular dependency detected"
  end

  defmodule DependencyError do
    defexception [:dep_name, :issue, :suggestions]

    def message(%{dep_name: name, issue: issue, suggestions: sugg}) do
      """
      Dependency analysis failed: #{name}

      Issue: #{format_issue(issue)}

      Suggestions:
      #{sugg}
      """
    end

    defp format_issue(:not_found), do: "Dependency not found in deps/"
    defp format_issue(:no_sources), do: "No source files found (compiled-only package?)"
    defp format_issue({:incompatible_version, v}), do: "Version #{v} uses unsupported features"
    defp format_issue(:corrupted_beam), do: "BEAM file appears corrupted"
  end
end
```

### Runtime Errors

```elixir
defmodule Litmus.Runtime.Errors do
  defmodule UnhandledEffectError do
    defexception [:effect, :available_handlers, :location]

    def message(%{effect: {m, f, a}, available_handlers: handlers, location: loc}) do
      """
      Unhandled effect in pure block

      Effect: #{inspect(m)}.#{f}/#{a}
      Location: #{format_location(loc)}

      This effect was not caught by any handler.

      Available handlers:
      #{format_handlers(handlers)}

      Add a catch clause for this effect:
      catch
        {#{inspect(m)}, :#{f}, args} -> # handle the effect
      """
    end
  end

  defmodule ModificationError do
    defexception [:module, :phase, :reason]

    def message(%{module: mod, phase: phase, reason: reason}) do
      """
      Failed to modify module for purity enforcement

      Module: #{inspect(mod)}
      Phase: #{phase}
      Reason: #{format_reason(reason)}

      The system will fall back to runtime checking, which may impact performance.
      """
    end
  end

  defmodule EffectViolationError do
    defexception [:expected, :actual, :call_stack]

    def message(%{expected: exp, actual: act, call_stack: stack}) do
      """
      Effect contract violation

      Expected: #{format_effect(exp)}
      Actual: #{format_effect(act)}

      Call stack:
      #{format_stack(stack)}

      This usually indicates an incorrect effect annotation or a bug in effect inference.
      """
    end
  end
end
```

### Analysis Warnings (Non-Fatal)

```elixir
defmodule Litmus.Warnings do
  def emit_warning(type, details) do
    message = format_warning(type, details)
    IO.warn(message, Macro.Env.stacktrace(__ENV__))
  end

  defp format_warning(:conservative_classification, %{mfa: mfa, assumed: effect}) do
    """
    Conservative effect classification for #{inspect(mfa)}

    No source code or debug_info available, assuming: #{effect}

    To fix: Ensure the module is compiled with debug_info or add explicit annotation.
    """
  end

  defp format_warning(:performance_impact, %{module: mod, overhead: overhead_ms}) do
    """
    Performance warning: Module #{inspect(mod)} modification added #{overhead_ms}ms overhead

    Consider pre-compiling with purity annotations to avoid runtime modification.
    """
  end

  defp format_warning(:partial_analysis, %{module: mod, coverage: percent}) do
    """
    Partial analysis: Only #{percent}% of functions in #{inspect(mod)} could be analyzed

    Some functions may be incorrectly marked as having unknown effects.
    """
  end
end
```

---

## 5.2 Testing Strategy

### Unit Testing Approach

```elixir
defmodule Litmus.TestStrategy do
  @moduledoc """
  Comprehensive testing strategy for all components.
  """

  # 1. AST TRANSFORMATION TESTS
  describe "AST transformation correctness" do
    test "preserves semantics for all constructs" do
      # Test that transformation doesn't change behavior
      constructs = [
        {:cond, "cond expression"},
        {:with, "with expression"},
        {:try, "try-catch-rescue"},
        {:receive, "receive block"},
        {:fn, "anonymous function"},
        {:case, "case expression"}
      ]

      for {type, name} <- constructs do
        original = load_fixture("ast/#{type}_original.ex")
        transformed = transform(original)

        # Execute both and compare results
        assert execute(original) == execute(transformed),
               "Transformation changed semantics of #{name}"
      end
    end

    test "correctly threads continuations" do
      # Verify continuation passing is correct
      code = """
      effect do
        x = File.read!("a.txt")
        y = String.upcase(x)
        File.write!("b.txt", y)
      end
      """

      transformed = transform(code)

      # Check that continuations are properly chained
      assert_continuation_chain(transformed, [
        {:effect, {File, :read!, ["a.txt"]}},
        {:pure, {String, :upcase, :from_continuation}},
        {:effect, {File, :write!, ["b.txt", :from_continuation]}}
      ])
    end
  end

  # 2. EFFECT INFERENCE TESTS
  describe "effect inference accuracy" do
    test "propagates effects through lambdas" do
      test_cases = [
        {~s(Enum.map([1,2], fn x -> x + 1 end)), :p},
        {~s(Enum.map([1,2], fn x -> IO.puts(x) end)), :s},
        {~s(Enum.filter([1,2], fn x -> File.exists?("#{x}.txt") end)), :d}
      ]

      for {code, expected_effect} <- test_cases do
        assert infer_effect(code) == expected_effect
      end
    end

    test "handles all exception types" do
      test_cases = [
        {~s(raise "error"), {:e, ["Elixir.RuntimeError"]}},
        {~s(raise ArgumentError), {:e, ["Elixir.ArgumentError"]}},
        {~s(throw :error), {:e, [:throw]}},
        {~s(exit(:normal)), {:e, [:exit]}}
      ]

      for {code, expected} <- test_cases do
        assert infer_effect(code) == expected
      end
    end
  end

  # 3. BEAM MODIFICATION TESTS (Isolated)
  describe "BEAM modification safety" do
    @tag :skip_ci  # These tests modify runtime, skip in CI
    test "can modify and rollback safely" do
      # Create test module
      defmodule TestModule do
        def pure_func(x), do: x + 1
        def impure_func(x), do: IO.puts(x)
      end

      # Modify module
      {:ok, _} = BeamModifier.inject_purity_checks(TestModule)

      # Test modified behavior
      assert_raise UnhandledEffectError, fn ->
        TestModule.impure_func("test")
      end

      # Rollback
      :ok = BeamModifier.rollback(TestModule)

      # Test original behavior restored
      assert TestModule.impure_func("test") == :ok
    end

    test "handles concurrent access during modification" do
      # Spawn 100 processes calling the module
      tasks = for i <- 1..100 do
        Task.async(fn ->
          for j <- 1..100 do
            TestModule.pure_func(i * j)
          end
        end)
      end

      # Modify while processes are running
      {:ok, _} = BeamModifier.inject_purity_checks(TestModule)

      # All tasks should complete without crashes
      results = Task.await_many(tasks, 5000)
      assert length(results) == 100
    end
  end

  # 4. INTEGRATION TESTS
  describe "end-to-end purity enforcement" do
    test "pure blocks catch all effect types" do
      effects_that_must_fail = [
        "IO.puts('hello')",
        "File.read!('test.txt')",
        "Process.send(self(), :msg, [])",
        "System.get_env('HOME')",
        ":ets.new(:test, [])",
        "apply(IO, :puts, ['test'])"
      ]

      for effect_code <- effects_that_must_fail do
        assert_raise ImpurityError, fn ->
          Code.eval_string("""
          import Litmus.Pure
          pure do
            #{effect_code}
          end
          """)
        end
      end
    end

    test "dependency effects are enforced" do
      # Test that dependency functions are checked
      assert_raise UnhandledEffectError, fn ->
        pure do
          Jason.decode!("{}")  # Dependency function
        catch
          # No handler - should fail
        end
      end
    end
  end

  # 5. PERFORMANCE BENCHMARKS
  describe "performance requirements" do
    @tag :benchmark
    test "analysis completes within time budget" do
      projects = [
        {:small, "test/fixtures/small_project", 10},     # 50 modules, 10s budget
        {:medium, "test/fixtures/medium_project", 30},   # 200 modules, 30s budget
        {:large, "test/fixtures/phoenix_app", 60}        # 500+ modules, 60s budget
      ]

      for {size, path, budget_seconds} <- projects do
        {time_micros, _result} = :timer.tc(fn ->
          Litmus.analyze_project(path)
        end)

        time_seconds = time_micros / 1_000_000
        assert time_seconds < budget_seconds,
               "#{size} project analysis took #{time_seconds}s, budget was #{budget_seconds}s"
      end
    end

    test "memory usage stays within bounds" do
      # Monitor memory during analysis
      initial_memory = :erlang.memory(:total)

      Litmus.analyze_project("test/fixtures/large_project")

      final_memory = :erlang.memory(:total)
      memory_used_mb = (final_memory - initial_memory) / 1_024 / 1_024

      assert memory_used_mb < 500, "Used #{memory_used_mb}MB, limit is 500MB"
    end
  end

  # 6. PROPERTY-BASED TESTS
  use PropCheck

  property "transformation preserves types" do
    forall ast <- ast_generator() do
      original_type = infer_type(ast)
      transformed = transform(ast)
      transformed_type = infer_type(transformed)

      # Types should be preserved (modulo effects)
      types_compatible?(original_type, transformed_type)
    end
  end

  property "effect inference is monotonic" do
    forall {ast1, ast2} <- {ast_generator(), ast_generator()} do
      # If ast1 is more pure than ast2
      implies effect_less_than?(infer_effect(ast1), infer_effect(ast2)) do
        # Then their combination is at least as impure as ast2
        combined = combine_ast(ast1, ast2)
        effect_less_than?(infer_effect(ast2), infer_effect(combined))
      end
    end
  end
end
```

### Test Fixtures and Helpers

```elixir
defmodule Litmus.TestHelpers do
  @moduledoc "Shared test utilities"

  def with_test_project(name, fun) do
    # Create isolated test project
    in_tmp("litmus_test_#{name}", fn ->
      create_mix_project(name)
      add_test_dependencies()
      fun.()
    end)
  end

  def create_effect_mock(mfa, return_value) do
    # Create mock for effect testing
    :meck.new(elem(mfa, 0), [:passthrough])
    :meck.expect(elem(mfa, 0), elem(mfa, 1), fn _ -> return_value end)
  end

  def assert_pure(code) do
    assert infer_effect(code) == :p,
           "Expected pure code, got: #{inspect(infer_effect(code))}"
  end

  def assert_effectful(code, expected_effect) do
    actual = infer_effect(code)
    assert actual == expected_effect,
           "Expected effect #{inspect(expected_effect)}, got: #{inspect(actual)}"
  end
end
```

---

## 6. Migration Path

### Step 1: Parallel Development (Week 1-4)
- Develop new components alongside existing
- No breaking changes
- Feature flag for new analyzer

### Step 2: Validation Phase (Week 5-6)
- Run both analyzers in parallel
- Compare results
- Fix discrepancies
- Build confidence

### Step 3: Gradual Rollout (Week 7)
- Switch to new analyzer by default
- Keep PURITY as fallback
- Monitor for issues

### Step 4: Deprecation (Week 8)
- Remove PURITY completely
- Remove compatibility shims
- Final cleanup

---

## 7. Success Metrics

### Quantitative Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Functions marked `:unknown` | ~15% | 0% |
| Effects slipping through | 7 paths | 0 paths |
| Dependency analysis coverage | 60% | 100% |
| False positives | ~5% | 0% |
| False negatives | Unknown | 0% |
| Analysis time (average project) | 30s | <10s |

### Qualitative Goals

1. **Developer Confidence**: Can trust `pure do` blocks completely
2. **No Surprises**: All effects caught at compile-time
3. **Clear Errors**: Precise error messages with suggested fixes
4. **Fast Iteration**: Near-instant analysis feedback
5. **IDE Integration**: Real-time purity information

### Verification Tests

```elixir
# Test 1: No effect can escape
pure do
  # These MUST all fail at compile time:
  IO.puts("test")                    # Direct call
  apply(IO, :puts, ["test"])         # Dynamic dispatch
  f = &IO.puts/1; f.("test")        # Captured function
  MyMacro.effectful()                # Macro-generated
catch
  # Empty catch - nothing should be catchable
end

# Test 2: Complete dependency transformation
pure do
  # Dependency function with effects
  Jason.decode!("{}")  # Must be caught
catch
  {Jason, :decode!, _} -> %{}
end

# Test 3: All constructs supported
pure do
  cond do
    true -> pure_function()
  end

  with {:ok, x} <- pure_function() do
    x
  end

  recursive_pure_function(10)
end
```

---

## 8. Risk Mitigation

### Technical Risks

| Risk | Mitigation |
|------|------------|
| BEAM modification breaks runtime | Feature flag, gradual rollout, extensive testing |
| Performance regression | Parallel analysis, incremental caching, benchmarking |
| Backwards compatibility | Compatibility mode, migration guide, deprecation period |
| Circular dependencies | Provisional typing, cycle detection, error recovery |

### Process Risks

| Risk | Mitigation |
|------|------------|
| Scope creep | Fixed phases, clear deliverables, weekly reviews |
| Integration issues | Continuous integration, parallel development |
| User adoption | Documentation, migration tools, examples |

---

## 9. Open Questions

1. **Should we support partial effect handlers?**
   - Allow catching effect classes vs specific MFAs?
   - Example: `catch {:file, _}` for all file operations?

2. **How to handle protocol implementations?**
   - Protocols dispatch dynamically
   - Cannot statically determine implementation
   - Conservative assumption vs runtime checking?

3. **Integration with existing tools?**
   - Dialyzer integration?
   - ElixirLS integration?
   - Mix format integration?

4. **Performance vs completeness trade-off?**
   - Full analysis of all paths vs heuristics?
   - Caching strategy for large codebases?

---

## 10. Conclusion

This roadmap provides a complete path to achieving absolute purity enforcement in Litmus. By replacing PURITY with a comprehensive AST-based analyzer, building a complete dependency graph, implementing full CPS transformation, and adding runtime BEAM modification capabilities, we can guarantee that no effects slip through the `pure do...catch...end` construct.

**Total estimated time**: 8 weeks
**Team size**: 1-2 developers
**Complexity**: High
**Impact**: Transforms Litmus from partial to complete purity enforcement

---

## Appendix A: File Change Summary

### Files to Create
- `lib/litmus/dependency/graph.ex`
- `lib/litmus/analyzer/recursive_analyzer.ex`
- `lib/litmus/discovery/source_finder.ex`
- `lib/litmus/cache/module_cache.ex`
- `lib/litmus/analyzer/dynamic_dispatch.ex`
- `lib/litmus/compiler/dependency_transformer.ex`
- `lib/litmus/runtime/beam_modifier.ex`
- `lib/litmus/analyzer/complete.ex`
- `test/complete_purity_test.exs`

### Files to Modify
- `lib/litmus/analyzer/ast_walker.ex` - Add recursive analysis
- `lib/litmus/effects/transformer.ex` - Support all constructs
- `lib/litmus/pure.ex` - Complete rewrite
- `lib/mix/tasks/effect.ex` - Use dependency graph

### Files to Remove
- `purity_source/` - Entire directory
- PURITY references in `lib/litmus.ex`

---

## Appendix B: Example Implementation

### Complete Pure Macro Usage

```elixir
defmodule MyApp do
  import Litmus.Pure

  def process_data(input) do
    pure allow_exceptions: [] do
      # This is GUARANTEED pure - no effects can escape
      data = parse_input(input)
      transformed = transform_data(data)
      validate_output(transformed)
    catch
      # Can only catch effects explicitly allowed
      # Since allow_exceptions: [], nothing can be caught
    end
  end

  def process_with_io(input) do
    pure allow_exceptions: [] do
      data = parse_input(input)

      # This WILL fail at compile time
      # Even though wrapped in effect handler
      log_data(data)  # Compile error: Effect not handled!

      transform_data(data)
    catch
      {MyApp, :log_data, [data]} ->
        # Would handle the effect, but compile fails first
        :ok
    end
  end
end
```

### Runtime Enforcement Example

```elixir
# Even if someone tries to bypass with metaprogramming:
defmodule Bypass do
  def sneaky_effect do
    # Try to bypass with apply
    module = IO
    function = :puts
    apply(module, function, ["gotcha!"])
  end
end

pure do
  Bypass.sneaky_effect()  # Runtime error: Unhandled effect!
catch
  # No handler for {IO, :puts, ["gotcha!"]}
  # Runtime enforcement catches it
end
```

---

## 11. Implementation Starting Points

### Critical Code to Study First

Before implementing any tasks, thoroughly understand these existing modules:

#### 1. Core Analysis Engine
**File**: `lib/litmus/analyzer/ast_walker.ex`
```elixir
# Key functions to understand:
- analyze_file/1 (lines 297-320) - Entry point for file analysis
- analyze_module_body/2 (lines 203-240) - Core analysis logic
- classify_effect/2 (lines 340-374) - Effect classification algorithm
- extract_calls/1 - How function calls are detected

# Critical insight: This already does 85% of what we need
# Main gap: Dependency resolution (line 219) returns nil for uncached deps
```

#### 2. CPS Transformer
**File**: `lib/litmus/effects/transformer.ex`
```elixir
# Key functions to understand:
- transform_ast/2 (lines 200-300) - Main transformation dispatch
- extract_call/2 (lines 431-491) - Effect detection logic
- build_effect/3 (lines 160-166) - How continuations are built

# Critical gap: Only handles if/else and case, not cond/with/try
```

#### 3. Pure Macro
**File**: `lib/litmus/pure.ex`
```elixir
# Key functions to understand:
- pure/2 macro (lines 156-246) - Main entry point
- extract_call/1 (lines 483-495) - BUG: Skips captured functions!
- check_purity/3 (lines 260-290) - Purity checking logic

# Critical bug: Line 485-494 returns nil for captures
```

#### 4. Registry System
**File**: `lib/litmus/effects/registry.ex`
```elixir
# Key functions:
- runtime_cache/0 (line 86) - Global effect cache
- add_to_runtime_cache/2 - How effects are registered
- effect?/1 and effect_type/1 - Lookup functions

# Issue: Empty during macro expansion (compile-time vs runtime)
```

### Step-by-Step Implementation Order

#### Phase 0: Technical Spikes (Week 0)
```bash
# Run spikes in this order:
1. mix run spikes/beam_modification_spike.exs
   # If fails: Abandon BEAM modification, use compile-time only

2. mix run spikes/protocol_resolution_spike.exs
   # If <80% accuracy: Mark protocols as :unknown always

3. mix run spikes/performance_spike.exs
   # If >60s for Phoenix: Need different approach

4. mix run spikes/erlang_analysis_spike.exs
   # If fails: Whitelist common Erlang modules only
```

#### Phase 1: Fix Existing Bugs (Day 1-2)
```elixir
# 1. Fix captured function bug in pure.ex
# Change lines 485-494 from:
defp extract_call({{:., _}, _, args}) when is_atom(args), do: nil

# To:
defp extract_call({{:., _, [module, function]}, _, args}) when is_atom(args) do
  # This is a capture like &IO.puts/1
  arity = determine_arity_from_capture(args)
  {module, function, arity}
end

# 2. Fix dependency resolution in ast_walker.ex
# Add at line 220:
if effect == nil do
  # Recursively analyze dependency
  analyze_dependency_if_needed(mfa)
  Registry.runtime_cache()[mfa] || :u
end
```

#### Phase 2: Build Dependency Graph (Week 1)
```elixir
# 1. Start with existing dependency_graph.ex
# It already has cycle detection and topological sort!

# 2. Add source discovery (new file):
defmodule Litmus.Discovery.SourceFinder do
  def find_all_sources do
    # Implement the algorithm from Task 1
  end
end

# 3. Integrate with ProjectAnalyzer:
# Modify lib/litmus/analyzer/project_analyzer.ex line 56
# Change from arbitrary order to topological order
```

#### Phase 3: Complete CPS Transformation (Week 2-3)
```elixir
# Add to transformer.ex after line 300:

defp transform_ast({:cond, meta, [[do: clauses]]}, opts) do
  # Implementation from Task 11
end

defp transform_ast({:with, meta, args}, opts) do
  # Implementation from Task 11
end

# Test each construct thoroughly before moving on
```

#### Phase 4: Replace PURITY (Week 4)
```elixir
# 1. Create new analyzer that doesn't use PURITY:
defmodule Litmus.Analyzer.Complete do
  def analyze(module) do
    # Try AST first
    # Fall back to BEAM abstract code
    # Last resort: Conservative inference
  end
end

# 2. Update all references:
# - lib/litmus.ex
# - lib/litmus/pure.ex
# - lib/litmus/registry/builder.ex

# 3. Delete purity_source/ directory
```

### Critical Decision Points

#### Decision 1: BEAM Modification Feasibility (After Spike 1)
**If feasible** (can modify, <5% overhead, no crashes):
- Proceed with Task 13 as specified
- Implement runtime enforcement

**If not feasible**:
- Skip Task 13 entirely
- Focus on compile-time transformation only
- Accept that dependency effects can't be fully controlled
- Document this limitation clearly

#### Decision 2: Protocol Resolution (After Spike 3)
**If >80% accuracy**:
- Implement full protocol resolution
- Track effects through protocol dispatch

**If <80% accuracy**:
- Mark all protocol calls as `:unknown`
- Require explicit annotations
- Document common patterns

#### Decision 3: Performance (After Spike 4)
**If meets targets** (<30s for Phoenix):
- Proceed as planned

**If too slow**:
- Implement incremental analysis first
- Add parallelization (Task 16)
- Consider analysis depth limits

### Validation Milestones

#### Milestone 1: Dependency Graph Complete (End of Week 1)
```elixir
# Test: Can analyze all of Phoenix's dependencies
{:ok, graph} = Litmus.Dependency.Graph.build("path/to/phoenix")
assert length(graph.nodes) > 500
assert graph.cycles == []
```

#### Milestone 2: CPS Transformation Complete (End of Week 3)
```elixir
# Test: All control flow constructs work
test_files = ~w(cond_test.ex with_test.ex recursive_test.ex)
for file <- test_files do
  assert transform_and_execute(file) == original_result(file)
end
```

#### Milestone 3: PURITY Replaced (End of Week 4)
```elixir
# Test: No PURITY references remain
assert :os.cmd('grep -r PURITY lib/') == []
# Test: Analysis still works
assert Litmus.analyze_module(String) == {:ok, _results}
```

#### Milestone 4: Integration Complete (End of Week 6)
```elixir
# The ultimate test:
pure do
  # This must fail at compile time
  IO.puts("test")
catch
  # Empty catch - nothing should get through
end
```

### Common Pitfalls to Avoid

1. **Don't modify BEAM without rollback**
   - Always save original before :code.purge
   - Provide recovery mechanism

2. **Don't analyze in random order**
   - Use dependency graph from Day 1
   - Cycles must be handled specially

3. **Don't trust naming heuristics**
   - `get_env` sounds pure but isn't
   - Use as hints, not conclusions

4. **Don't skip captured functions**
   - Current bug in pure.ex
   - Must be fixed first

5. **Don't mix compile-time and runtime**
   - Registry must be populated at compile-time
   - Or use different lookup mechanism

### Debugging Tools to Build

```elixir
# 1. Effect path tracer
mix litmus.trace IO.puts/1
# Shows: IO.puts/1 -> :s because it's in stdlib whitelist

# 2. Dependency graph visualizer
mix litmus.graph --format=dot | dot -Tpng > graph.png

# 3. Cache inspector
mix litmus.cache --show
# Shows all cached effects with sources

# 4. Purity explainer
mix litmus.explain MyModule.my_func/2
# Shows why function has specific effect type
```

---

**END OF DOCUMENT**