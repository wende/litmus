defmodule Litmus.Analyzer.DependencyGraph do
  @moduledoc """
  Builds and analyzes dependency graphs for Elixir projects.

  This module creates a directed graph of module dependencies by analyzing:
  - Explicit imports (`import MyModule`)
  - Aliases (`alias MyModule`)
  - Remote function calls (`MyModule.function()`)

  The graph is used to determine the correct order for analyzing modules,
  ensuring that dependencies are analyzed before their dependents.

  ## Examples

      # Build graph from source files
      files = ["lib/a.ex", "lib/b.ex", "lib/c.ex"]
      graph = DependencyGraph.from_files(files)

      # Get topologically sorted modules
      {:ok, ordered} = DependencyGraph.topological_sort(graph)
      #=> [ModuleC, ModuleB, ModuleA]  # If A depends on B, B depends on C

      # Detect cycles
      cycles = DependencyGraph.find_cycles(graph)
      #=> [[ModuleX, ModuleY]]  # If X and Y depend on each other
  """

  alias Litmus.Analyzer.DependencyGraph

  @type module_name :: module()
  @type t :: %__MODULE__{
          # Forward edges: module => modules it depends on
          edges: %{module_name() => MapSet.t(module_name())},
          # Reverse edges: module => modules that depend on it (for invalidation)
          reverse_edges: %{module_name() => MapSet.t(module_name())},
          # All modules in the graph
          modules: MapSet.t(module_name()),
          # File path for each module
          module_files: %{module_name() => String.t()},
          # Strongly connected components (cycles)
          sccs: list(list(module_name())),
          # Missing modules: module => [referring modules]
          missing_modules: %{module_name() => list(module_name())}
        }

  defstruct edges: %{},
            reverse_edges: %{},
            modules: MapSet.new(),
            module_files: %{},
            sccs: [],
            missing_modules: %{}

  @doc """
  Creates an empty dependency graph.
  """
  def new do
    %DependencyGraph{}
  end

  @doc """
  Builds a dependency graph from a list of source files.

  ## Examples

      files = ["lib/my_module.ex", "lib/other.ex"]
      graph = DependencyGraph.from_files(files)
  """
  def from_files(files) when is_list(files) do
    # Parse all files and extract module info
    module_infos =
      files
      |> Enum.flat_map(&parse_file/1)
      |> Enum.reject(&(&1 == :error))

    # Build graph from module infos
    build_graph(module_infos)
  end

  @doc """
  Adds a dependency edge: from_module depends on to_module.

  ## Examples

      graph = DependencyGraph.new()
      graph = DependencyGraph.add_dependency(graph, ModuleA, ModuleB)
  """
  def add_dependency(graph, from_module, to_module) do
    # Don't add self-dependencies
    if from_module == to_module do
      graph
    else
      # Add modules to the set
      modules = MapSet.put(graph.modules, from_module) |> MapSet.put(to_module)

      # Add forward edge
      edges = Map.update(graph.edges, from_module, MapSet.new([to_module]), &MapSet.put(&1, to_module))

      # Add reverse edge
      reverse_edges =
        Map.update(graph.reverse_edges, to_module, MapSet.new([from_module]), &MapSet.put(&1, from_module))

      %{graph | edges: edges, reverse_edges: reverse_edges, modules: modules}
    end
  end

  @doc """
  Returns all modules that the given module depends on.

  ## Examples

      deps = DependencyGraph.dependencies(graph, MyModule)
      #=> MapSet.new([OtherModule, ThirdModule])
  """
  def dependencies(graph, module) do
    Map.get(graph.edges, module, MapSet.new())
  end

  @doc """
  Returns all modules that depend on the given module.

  ## Examples

      dependents = DependencyGraph.dependents(graph, MyModule)
      #=> MapSet.new([ModuleA, ModuleB])
  """
  def dependents(graph, module) do
    Map.get(graph.reverse_edges, module, MapSet.new())
  end

  @doc """
  Performs topological sort on the dependency graph.

  Returns modules in an order such that if A depends on B, B appears before A.
  If the graph has cycles, returns those separately.

  ## Return values

  - `{:ok, ordered_modules}` - Linear ordering (no cycles)
  - `{:cycles, linear_modules, cycles}` - Contains cycles

  ## Examples

      {:ok, ordered} = DependencyGraph.topological_sort(graph)
      #=> [ModuleC, ModuleB, ModuleA]

      {:cycles, linear, cycles} = DependencyGraph.topological_sort(cyclic_graph)
      #=> {[ModuleA], [[ModuleX, ModuleY]]}
  """
  def topological_sort(graph) do
    # Find strongly connected components (Tarjan's algorithm)
    # Note: Tarjan returns SCCs in reverse topological order
    sccs = find_sccs(graph)

    # Separate single-node SCCs (acyclic) from multi-node SCCs (cycles)
    {acyclic, cycles} = Enum.split_with(sccs, &(length(&1) == 1))

    # Flatten acyclic SCCs and reverse to get correct topological order
    # (Tarjan's algorithm returns in reverse topological order)
    linear = Enum.map(acyclic, &hd/1) |> Enum.reverse()

    if Enum.empty?(cycles) do
      {:ok, linear}
    else
      {:cycles, linear, cycles}
    end
  end

  @doc """
  Finds all cycles (strongly connected components) in the graph.

  Returns a list of cycles, where each cycle is a list of modules.

  ## Examples

      cycles = DependencyGraph.find_cycles(graph)
      #=> [[ModuleX, ModuleY], [ModuleA, ModuleB, ModuleC]]
  """
  def find_cycles(graph) do
    sccs = find_sccs(graph)
    Enum.filter(sccs, &(length(&1) > 1))
  end

  @doc """
  Computes all modules that transitively depend on the given module.

  This is useful for cache invalidation: when a module changes,
  all transitively dependent modules need to be re-analyzed.

  ## Examples

      affected = DependencyGraph.transitive_dependents(graph, MyModule)
      #=> MapSet.new([ModuleA, ModuleB, ModuleC])
  """
  def transitive_dependents(graph, module) do
    compute_transitive_closure(graph, module, :dependents)
  end

  @doc """
  Computes all modules that the given module transitively depends on.

  ## Examples

      deps = DependencyGraph.transitive_dependencies(graph, MyModule)
      #=> MapSet.new([ModuleX, ModuleY, ModuleZ])
  """
  def transitive_dependencies(graph, module) do
    compute_transitive_closure(graph, module, :dependencies)
  end

  # Private implementation

  # Parse a single file and extract module info
  # Returns a list of module infos (since a file can have multiple modules)
  defp parse_file(path) do
    with {:ok, source} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(source) do
      extract_all_modules(ast, path)
    else
      _ -> [:error]
    end
  end

  # Extract all modules from a file's AST
  # Returns a list of module infos
  defp extract_all_modules(ast, file_path) do
    case ast do
      # Single defmodule at top level
      {:defmodule, _, [module_name_ast, [do: body]]} ->
        [extract_single_module(module_name_ast, body, file_path)]

      # Single defprotocol at top level
      {:defprotocol, _, [module_name_ast, [do: body]]} ->
        [extract_single_module(module_name_ast, body, file_path)]

      # Multiple modules/protocols in a block
      {:__block__, _, items} ->
        items
        |> Enum.flat_map(fn item ->
          case item do
            {:defmodule, _, [module_name_ast, [do: body]]} ->
              [extract_single_module(module_name_ast, body, file_path)]

            {:defprotocol, _, [module_name_ast, [do: body]]} ->
              [extract_single_module(module_name_ast, body, file_path)]

            # Skip defimpl, defexception, etc.
            _ ->
              []
          end
        end)

      _ ->
        [:error]
    end
  end

  # Extract a single module's info
  defp extract_single_module(module_name_ast, body, file_path) do
    module = extract_module_name(module_name_ast)

    if module do
      dependencies = extract_dependencies(body)
      %{module: module, file: file_path, dependencies: dependencies}
    else
      :error
    end
  end

  # Extract module name from AST
  defp extract_module_name({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp extract_module_name(atom) when is_atom(atom) do
    atom
  end

  defp extract_module_name(_), do: nil

  # Extract all module dependencies from module body
  defp extract_dependencies(body) do
    dependencies = MapSet.new()

    {_ast, dependencies} =
      Macro.prewalk(body, dependencies, fn node, acc ->
        case extract_dependency(node) do
          nil -> {node, acc}
          dep -> {node, MapSet.put(acc, dep)}
        end
      end)

    dependencies
  end

  # Extract dependency from various AST node types

  # import MyModule
  defp extract_dependency({:import, _, [module_ast | _]}) do
    extract_module_name(module_ast)
  end

  # alias MyModule
  defp extract_dependency({:alias, _, [module_ast | _]}) do
    extract_module_name(module_ast)
  end

  # use MyModule
  defp extract_dependency({:use, _, [module_ast | _]}) do
    extract_module_name(module_ast)
  end

  # Remote function call: MyModule.function()
  defp extract_dependency({{:., _, [module_ast, _function]}, _, _args}) do
    case module_ast do
      {:__aliases__, _, _parts} -> extract_module_name(module_ast)
      # Skip calls on variables or other non-module expressions
      _ -> nil
    end
  end

  defp extract_dependency(_), do: nil

  # Build graph from list of module infos
  defp build_graph(module_infos) do
    graph = new()

    # First pass: add all modules and their files
    graph =
      Enum.reduce(module_infos, graph, fn info, g ->
        %{
          g
          | modules: MapSet.put(g.modules, info.module),
            module_files: Map.put(g.module_files, info.module, info.file)
        }
      end)

    # Second pass: add dependencies and track missing ones
    {graph, missing} =
      Enum.reduce(module_infos, {graph, MapSet.new()}, fn info, {g, missing_acc} ->
        Enum.reduce(info.dependencies, {g, missing_acc}, fn dep, {acc, miss} ->
          # Only add edge if dependent module is in our graph
          if MapSet.member?(graph.modules, dep) do
            {add_dependency(acc, info.module, dep), miss}
          else
            # Track missing dependency if it looks like an app module
            # (not Elixir/Erlang stdlib)
            if is_app_module?(dep) do
              {acc, MapSet.put(miss, {dep, info.module})}
            else
              {acc, miss}
            end
          end
        end)
      end)

    # Store missing modules in the graph (don't IO during compilation)
    missing_map =
      if not Enum.empty?(missing) do
        report_missing_modules(missing)
      else
        %{}
      end

    %{graph | missing_modules: missing_map}
  end

  # Check if a module looks like an application module (not stdlib)
  defp is_app_module?(module) do
    module_str = inspect(module)

    # Only include Elixir modules (not Erlang)
    cond do
      # Erlang modules (lowercase atoms) are stdlib
      not String.starts_with?(module_str, "Elixir.") ->
        false

      # Check if it's in our stdlib registry
      is_stdlib_module?(module_str) ->
        false

      # Otherwise it's an app module
      true ->
        true
    end
  end

  # Check if a module is in the stdlib by consulting the effects registry
  defp is_stdlib_module?(module_str) do
    # Load stdlib modules from .effects.explicit.json
    # These are modules we've explicitly classified as stdlib
    stdlib_modules = get_stdlib_modules()

    # Check both the full module name and without "Elixir." prefix
    Map.has_key?(stdlib_modules, module_str) or
      Map.has_key?(stdlib_modules, String.replace_prefix(module_str, "Elixir.", ""))
  end

  # Load and cache stdlib module list from .effects.explicit.json
  defp get_stdlib_modules do
    # Use persistent term for caching across calls
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        stdlib = load_stdlib_modules()
        :persistent_term.put(__MODULE__, stdlib)
        stdlib

      cached ->
        cached
    end
  end

  defp load_stdlib_modules do
    path = ".effects.explicit.json"

    case File.read(path) do
      {:ok, content} ->
        # Avoid Jason.decode during compilation - do simple string parsing
        # Format: {"Module.Name": ..., "Another.Module": ...}
        # We just need the keys (module names)
        parse_json_keys(content)
      _ ->
        # If file doesn't exist, return empty map
        %{}
    end
  end

  # Simple JSON key parser that doesn't require Jason (avoids compile-time dependency)
  defp parse_json_keys(json_string) do
    # Match all keys in format "key":
    Regex.scan(~r/"([^"]+)"\s*:/, json_string)
    |> Enum.map(fn [_, key] -> key end)
    |> Enum.reject(&(&1 == "_metadata"))
    |> Map.new(fn mod -> {mod, true} end)
  end

  # Report missing modules that are referenced but not found
  # Returns the grouped missing modules map for storage
  defp report_missing_modules(missing) do
    # Group by missing module
    missing
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort_by(fn {mod, _} -> inspect(mod) end)
    |> Map.new()
  end

  @doc """
  Print warning about missing modules.
  Call this from mix tasks after the graph is built.
  """
  def print_missing_modules_warning(graph) do
    if not Enum.empty?(graph.missing_modules) do
      IO.puts("\n⚠️  Warning: Found #{map_size(graph.missing_modules)} referenced module(s) not in analysis:\n")

      Enum.each(graph.missing_modules, fn {missing_mod, referring_mods} ->
        IO.puts("  • #{inspect(missing_mod)}")
        IO.puts("    Referenced by: #{Enum.map(referring_mods, &inspect/1) |> Enum.join(", ")}")
      end)

      IO.puts("\n  These modules may cause 'unknown' effects in the analysis.")
      IO.puts("  Consider including their source files in the analysis.\n")
    end
  end

  # Tarjan's algorithm for finding strongly connected components
  defp find_sccs(graph) do
    state = %{
      index: 0,
      stack: [],
      indices: %{},
      lowlinks: %{},
      on_stack: MapSet.new(),
      sccs: []
    }

    # Run Tarjan's algorithm on all modules
    {state, _} =
      Enum.reduce(graph.modules, {state, graph}, fn module, {st, gr} ->
        if Map.has_key?(st.indices, module) do
          {st, gr}
        else
          tarjan_strongconnect(module, st, gr)
        end
      end)

    state.sccs
  end

  # Tarjan's strongconnect procedure
  defp tarjan_strongconnect(module, state, graph) do
    # Set depth index
    state = %{
      state
      | indices: Map.put(state.indices, module, state.index),
        lowlinks: Map.put(state.lowlinks, module, state.index),
        index: state.index + 1,
        stack: [module | state.stack],
        on_stack: MapSet.put(state.on_stack, module)
    }

    # Consider successors
    successors = dependencies(graph, module)

    state =
      Enum.reduce(successors, state, fn succ, st ->
        cond do
          # Successor not yet visited
          not Map.has_key?(st.indices, succ) ->
            {new_st, _} = tarjan_strongconnect(succ, st, graph)
            lowlink = min(new_st.lowlinks[module], new_st.lowlinks[succ])
            %{new_st | lowlinks: Map.put(new_st.lowlinks, module, lowlink)}

          # Successor is on stack (part of current SCC)
          MapSet.member?(st.on_stack, succ) ->
            lowlink = min(st.lowlinks[module], st.indices[succ])
            %{st | lowlinks: Map.put(st.lowlinks, module, lowlink)}

          # Successor already processed
          true ->
            st
        end
      end)

    # If module is a root node, pop the stack to get SCC
    state =
      if state.lowlinks[module] == state.indices[module] do
        {scc, new_stack} = pop_scc(state.stack, module, [])

        %{
          state
          | sccs: [scc | state.sccs],
            stack: new_stack,
            on_stack: Enum.reduce(scc, state.on_stack, &MapSet.delete(&2, &1))
        }
      else
        state
      end

    {state, graph}
  end

  # Pop modules from stack until we reach the root
  defp pop_scc([top | rest], root, acc) do
    new_acc = [top | acc]

    if top == root do
      {new_acc, rest}
    else
      pop_scc(rest, root, new_acc)
    end
  end

  # Compute transitive closure using BFS
  defp compute_transitive_closure(graph, start_module, direction) do
    # Get immediate neighbors based on direction
    get_neighbors =
      case direction do
        :dependents -> &dependents(graph, &1)
        :dependencies -> &dependencies(graph, &1)
      end

    # BFS to find all reachable modules
    queue = :queue.from_list([start_module])
    visited = MapSet.new([start_module])

    result = bfs_closure(queue, visited, get_neighbors)

    # Remove the start module from results (we want transitive, not reflexive+transitive)
    MapSet.delete(result, start_module)
  end

  defp bfs_closure(queue, visited, get_neighbors) do
    case :queue.out(queue) do
      {{:value, current}, rest} ->
        neighbors = get_neighbors.(current)

        # Find unvisited neighbors
        new_neighbors = MapSet.difference(neighbors, visited)

        # Add to queue and visited set
        new_queue = Enum.reduce(new_neighbors, rest, &:queue.in(&1, &2))
        new_visited = MapSet.union(visited, new_neighbors)

        bfs_closure(new_queue, new_visited, get_neighbors)

      {:empty, _} ->
        visited
    end
  end

  @doc """
  Returns a human-readable summary of the graph.

  ## Examples

      summary = DependencyGraph.summary(graph)
      IO.puts(summary)
      #=> Dependency Graph Summary:
      #=> Modules: 42
      #=> Dependencies: 156
      #=> Cycles: 2
  """
  def summary(graph) do
    module_count = MapSet.size(graph.modules)
    edge_count = Enum.reduce(graph.edges, 0, fn {_, deps}, acc -> acc + MapSet.size(deps) end)
    cycle_count = length(find_cycles(graph))

    """
    Dependency Graph Summary:
    ├─ Modules: #{module_count}
    ├─ Dependencies: #{edge_count}
    └─ Cycles: #{cycle_count}
    """
  end
end
