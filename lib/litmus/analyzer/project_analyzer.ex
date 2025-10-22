defmodule Litmus.Analyzer.ProjectAnalyzer do
  @moduledoc """
  Project-wide analyzer that handles dependency-ordered analysis.

  This module orchestrates the analysis of entire Elixir projects by:
  1. Building a dependency graph of all modules
  2. Analyzing modules in topological order
  3. Handling circular dependencies with fixed-point iteration
  4. Maintaining a shared cache across all analyses

  ## Usage

      # Analyze all files in a project
      files = ["lib/a.ex", "lib/b.ex", "lib/c.ex"]
      {:ok, results} = Litmus.Analyzer.ProjectAnalyzer.analyze_project(files)

      # Results is a map: %{module => analysis_result}
  """

  alias Litmus.Analyzer.DependencyGraph
  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Effects.Registry
  alias Litmus.Types.Core

  @type analysis_cache :: %{
          mfa() => %{
            effect: Core.effect_type(),
            type: Core.elixir_type(),
            calls: list(mfa())
          }
        }

  @type project_results :: %{
          module() => ASTWalker.analysis_result()
        }

  # Maximum iterations for fixed-point analysis of cycles
  @max_iterations 10

  @doc """
  Analyzes a project from a list of source files.

  Returns a map of module names to analysis results.

  ## Examples

      {:ok, results} = Analyzer.analyze_project(["lib/my_module.ex"])
      results[MyModule].functions
      #=> %{{MyModule, :func, 1} => %{effect: :p, ...}}
  """
  def analyze_project(files, opts \\ []) do
    # Build dependency graph
    graph = DependencyGraph.from_files(files)

    # Get topological ordering
    case DependencyGraph.topological_sort(graph) do
      {:ok, ordered_modules} ->
        # No cycles - simple linear analysis
        analyze_linear(ordered_modules, graph, opts)

      {:cycles, linear_modules, cycles} ->
        # Has cycles - need fixed-point iteration
        analyze_with_cycles(linear_modules, cycles, graph, opts)
    end
  end

  @doc """
  Analyzes modules in dependency order without cycles.

  This is the fast path when there are no circular dependencies.
  """
  def analyze_linear(modules, graph, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)

    # Set permissive mode for analysis
    Registry.set_permissive_mode(true)

    # Group modules by file (multiple modules can be in same file)
    modules_by_file =
      modules
      |> Enum.group_by(fn module -> graph.module_files[module] end)

    # Analyze each unique file once
    {results, _cache} =
      Enum.reduce(modules_by_file, {%{}, %{}}, fn {file, file_modules}, {results_acc, cache_acc} ->
        if verbose do
          IO.puts("Analyzing file: #{file} (modules: #{inspect(file_modules)})")
        end

        case analyze_file_all_modules(file, cache_acc) do
          {:ok, all_analyses} ->
            # all_analyses is a list of analysis results, one per module in the file
            new_cache =
              Enum.reduce(all_analyses, cache_acc, fn analysis, acc ->
                merge_analysis_into_cache(analysis, acc)
              end)

            # Store results for all modules from this file
            new_results =
              Enum.reduce(all_analyses, results_acc, fn analysis, acc ->
                Map.put(acc, analysis.module, analysis)
              end)

            {new_results, new_cache}

          {:error, _reason} ->
            # Failed to analyze - skip all modules in this file
            {results_acc, cache_acc}
        end
      end)

    Registry.set_permissive_mode(false)

    {:ok, results}
  end

  @doc """
  Analyzes modules with circular dependencies using fixed-point iteration.

  The algorithm:
  1. Analyze linear (acyclic) modules first
  2. For each cycle:
     a. Start with conservative assumptions (all functions unknown)
     b. Analyze all modules in the cycle
     c. Check if effects have changed
     d. Repeat until effects stabilize or max iterations reached
  """
  def analyze_with_cycles(linear_modules, cycles, graph, opts \\ []) do
    verbose = Keyword.get(opts, :verbose, false)

    if verbose do
      IO.puts("\nDetected #{length(cycles)} circular dependency group(s)")

      Enum.each(cycles, fn cycle ->
        IO.puts("  Cycle: #{inspect(cycle)}")
      end)

      IO.puts("")
    end

    Registry.set_permissive_mode(true)

    # Step 1: Analyze linear modules first
    {:ok, linear_results} = analyze_linear(linear_modules, graph, opts)

    # Step 2: Build initial cache from linear results
    initial_cache =
      Enum.reduce(linear_results, %{}, fn {_module, analysis}, cache ->
        merge_analysis_into_cache(analysis, cache)
      end)

    # Step 3: Analyze each cycle with fixed-point iteration
    {cycle_results, _final_cache} =
      Enum.reduce(cycles, {%{}, initial_cache}, fn cycle, {results_acc, cache_acc} ->
        if verbose do
          IO.puts("Analyzing cycle: #{inspect(cycle)}")
        end

        # Analyze this cycle until effects stabilize
        {cycle_result, cycle_cache} = analyze_cycle_fixpoint(cycle, graph, cache_acc, verbose)

        # Merge cycle results
        new_results = Map.merge(results_acc, cycle_result)

        {new_results, cycle_cache}
      end)

    # Combine linear and cycle results
    all_results = Map.merge(linear_results, cycle_results)

    Registry.set_permissive_mode(false)

    {:ok, all_results}
  end

  # Fixed-point iteration for a single cycle
  defp analyze_cycle_fixpoint(cycle_modules, graph, initial_cache, verbose, iteration \\ 1) do
    if iteration > @max_iterations do
      if verbose do
        IO.puts("  Warning: Reached max iterations (#{@max_iterations}) for cycle")
      end

      # Return current results even if not converged
      analyze_cycle_once(cycle_modules, graph, initial_cache)
    else
      # Analyze all modules in the cycle
      {results, new_cache} = analyze_cycle_once(cycle_modules, graph, initial_cache)

      # Check if effects have stabilized
      if effects_stabilized?(initial_cache, new_cache, cycle_modules) do
        if verbose do
          IO.puts("  Converged after #{iteration} iteration(s)")
        end

        {results, new_cache}
      else
        if verbose do
          IO.puts("  Iteration #{iteration}: Effects changed, continuing...")
        end

        # Continue iterating
        analyze_cycle_fixpoint(cycle_modules, graph, new_cache, verbose, iteration + 1)
      end
    end
  end

  # Analyze all modules in a cycle once
  defp analyze_cycle_once(cycle_modules, graph, cache) do
    Enum.reduce(cycle_modules, {%{}, cache}, fn module, {results_acc, cache_acc} ->
      file = graph.module_files[module]

      case analyze_file(file, cache_acc) do
        {:ok, analysis} ->
          # Update cache with new effects
          new_cache = merge_analysis_into_cache(analysis, cache_acc)

          # Store result
          new_results = Map.put(results_acc, module, analysis)

          {new_results, new_cache}

        {:error, _reason} ->
          {results_acc, cache_acc}
      end
    end)
  end

  # Check if effects have stabilized between iterations
  defp effects_stabilized?(old_cache, new_cache, modules) do
    # For each module in the cycle, check if any function's effect changed
    modules
    |> Enum.all?(fn module ->
      # Get all MFAs for this module
      module_mfas =
        new_cache
        |> Map.keys()
        |> Enum.filter(fn {m, _f, _a} -> m == module end)

      # Check if effects are the same
      Enum.all?(module_mfas, fn mfa ->
        old_effect = get_in(old_cache, [mfa, :effect])
        new_effect = get_in(new_cache, [mfa, :effect])

        effects_equal?(old_effect, new_effect)
      end)
    end)
  end

  # Compare two effects for equality (accounting for semantically equivalent forms)
  defp effects_equal?(nil, nil), do: true
  defp effects_equal?(nil, _), do: false
  defp effects_equal?(_, nil), do: false

  defp effects_equal?(e1, e2) do
    # Use compact notation for comparison
    Core.to_compact_effect(e1) == Core.to_compact_effect(e2)
  end

  # Analyze a single file
  defp analyze_file(file, cache) do
    # Set runtime cache before analysis
    Registry.set_runtime_cache(cache_to_registry_format(cache))

    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, file: file, line: 1),
         {:ok, analysis} <- ASTWalker.analyze_ast(ast) do
      {:ok, analysis}
    else
      error -> error
    end
  end

  # Analyze a file that may contain multiple modules
  # Returns {:ok, [analysis1, analysis2, ...]} for all modules in the file
  defp analyze_file_all_modules(file, cache) do
    # Update runtime cache (merge with existing deps cache, don't overwrite!)
    update_runtime_cache(cache)

    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, file: file, line: 1) do
      # Extract all defmodule nodes from the AST
      modules = extract_all_defmodules(ast)

      # Analyze each module, catching errors for already-compiled modules
      analyses =
        Enum.map(modules, fn {:defmodule, _, [module_name_ast, [do: body]]} ->
          module = extract_module_name_from_ast(module_name_ast)

          try do
            ASTWalker.analyze_module_body(module, body)
          rescue
            ArgumentError ->
              # Module is already compiled - can't analyze from source
              # This happens when analyzing dependencies that are already loaded
              {:error, :already_compiled}
          end
        end)

      # Filter out errors and return successful analyses
      successful =
        analyses
        |> Enum.filter(fn
          {:ok, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:ok, analysis} -> analysis end)

      {:ok, successful}
    else
      error -> error
    end
  end

  # Extract all defmodule nodes from AST
  defp extract_all_defmodules({:defmodule, _, _} = node), do: [node]

  defp extract_all_defmodules({:__block__, _, items}) do
    Enum.filter(items, fn item ->
      match?({:defmodule, _, _}, item)
    end)
  end

  defp extract_all_defmodules(_), do: []

  # Extract module name from AST
  defp extract_module_name_from_ast({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp extract_module_name_from_ast(atom) when is_atom(atom), do: atom
  defp extract_module_name_from_ast(_), do: nil

  # Convert our cache format to registry format (MFA => compact effect)
  defp cache_to_registry_format(cache) do
    Map.new(cache, fn {mfa, info} ->
      {mfa, Core.to_compact_effect(info.effect)}
    end)
  end

  # Merge analysis results into cache
  defp merge_analysis_into_cache(analysis, cache) do
    Enum.reduce(analysis.functions, cache, fn {{_m, _f, _a} = mfa, func_analysis}, acc ->
      Map.put(acc, mfa, %{
        effect: func_analysis.effect,
        type: func_analysis.type,
        calls: func_analysis.calls
      })
    end)
  end

  # Update runtime cache by merging (preserves existing deps cache from mix task)
  defp update_runtime_cache(cache) do
    # Get existing runtime cache (may contain deps effects from mix task)
    existing = Registry.runtime_cache()
    # Merge new cache with existing (new values override)
    merged = Map.merge(existing, cache_to_registry_format(cache))
    # Set merged cache
    Registry.set_runtime_cache(merged)
  end

  @doc """
  Returns statistics about a project analysis.

  ## Examples

      {:ok, results} = analyze_project(files)
      stats = statistics(results)
      #=> %{
      #=>   modules: 10,
      #=>   functions: 245,
      #=>   pure: 180,
      #=>   effectful: 45,
      #=>   unknown: 20
      #=> }
  """
  def statistics(results) do
    total_functions =
      results
      |> Map.values()
      |> Enum.flat_map(& &1.functions)
      |> length()

    # Count by effect type
    effect_counts =
      results
      |> Map.values()
      |> Enum.flat_map(fn analysis ->
        Enum.map(analysis.functions, fn {_mfa, func} ->
          Core.to_compact_effect(func.effect)
        end)
      end)
      |> Enum.frequencies()

    %{
      modules: map_size(results),
      functions: total_functions,
      pure: Map.get(effect_counts, :p, 0),
      lambda: Map.get(effect_counts, :l, 0),
      dependent: Map.get(effect_counts, :d, 0),
      side_effects: Map.get(effect_counts, :s, 0),
      exceptions: Map.get(effect_counts, :e, 0),
      unknown: Map.get(effect_counts, :u, 0),
      nif: Map.get(effect_counts, :n, 0)
    }
  end
end
