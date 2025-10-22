defmodule Mix.Tasks.Effect do
  @moduledoc """
  Analyzes an Elixir file and displays all functions with their inferred effects and exceptions.

  ## Usage

      mix effect path/to/file.ex

  ## Options

      --verbose, -v     Show detailed analysis including type information
      --json            Output results in JSON format
      --exceptions      Include exception analysis
      --purity          Include purity analysis from PURITY analyzer
      --filter TYPE     Only show functions with specific effect type
                        (p=pure, s=side-effects, l=lambda, d=dependent,
                         e=exception, u=unknown)

  ## Examples

      # Basic effect analysis
      mix effect lib/my_module.ex

      # Verbose output with types
      mix effect lib/my_module.ex --verbose

      # Show only unknown functions
      mix effect lib/my_module.ex --filter u

      # Show only lambda-dependent functions
      mix effect lib/my_module.ex --filter l

      # Include exception tracking
      mix effect lib/my_module.ex --exceptions

      # JSON output for tooling
      mix effect lib/my_module.ex --json
  """

  use Mix.Task

  alias Litmus.Formatter
  alias Litmus.Types.{Core, Effects}
  alias Litmus.Project.Analyzer

  # Stateful Kernel functions that should be displayed (rest are hidden as noise)
  @stateful_kernel_functions [
    :send,
    :spawn,
    :spawn_link,
    :spawn_monitor,
    :apply,
    :exit,
    :self,
    :make_ref,
    :raise,
    :reraise,
    :throw
  ]

  @deps_cache_path ".effects/deps.cache"
  @deps_checksum_path ".effects/deps.checksum"

  @shortdoc "Analyzes effects and exceptions in an Elixir file"

  @impl Mix.Task
  def run(args) do
    # Parse options
    {opts, paths, _} =
      OptionParser.parse(args,
        switches: [
          verbose: :boolean,
          json: :boolean,
          exceptions: :boolean,
          purity: :boolean,
          filter: :string
        ],
        aliases: [v: :verbose]
      )

    case paths do
      [] ->
        Mix.shell().error("Error: No file path provided")
        Mix.shell().info("\nUsage: mix effect path/to/file.ex")
        Mix.shell().info("\nRun 'mix help effect' for more information")
        exit({:shutdown, 1})

      [path | _] ->
        analyze_file(path, opts)
    end
  end

  defp analyze_file(path, opts) do
    unless File.exists?(path) do
      Mix.shell().error("Error: File not found: #{path}")
      exit({:shutdown, 1})
    end

    # Step 1: Load or analyze dependencies
    deps_cache = load_or_analyze_deps()

    # Step 2: Discover all application source files
    app_files = discover_app_files()

    # Step 2.5: Discover files in the same directory as the requested file
    # (for test files or modules outside lib/)
    absolute_path = Path.absname(path)
    file_dir = Path.dirname(absolute_path)

    # Find all .ex files in the same directory
    sibling_files = Path.wildcard("#{file_dir}/*.ex")

    # Add requested file and siblings to the list
    app_files = (app_files ++ sibling_files ++ [absolute_path])
                |> Enum.uniq()

    Mix.shell().info(
      "Analyzing #{length(app_files)} application files for cross-module effects...\n"
    )

    # Step 2.7: Set dependency cache in registry BEFORE analysis
    Litmus.Effects.Registry.set_runtime_cache(deps_cache)

    # Step 3: Use dependency-aware project analyzer
    case Analyzer.analyze_project(app_files, verbose: false) do
      {:ok, project_results} ->
        # Note: Analyzer.analyze_project already builds the dependency graph internally
        # TODO: Refactor to return graph from Analyzer.analyze_project to avoid rebuilding
        # (Skipping redundant graph building and missing modules warning for now)

        # Extract effect cache from results
        effect_cache = extract_project_cache(project_results)
        Mix.shell().info("Built effect cache with #{map_size(effect_cache)} functions\n")

        # Step 4: Merge dependency and application caches
        full_cache = Map.merge(deps_cache, effect_cache)

        # Step 5: Set runtime cache for cross-module lookups
        Litmus.Effects.Registry.set_runtime_cache(full_cache)

        # Step 6: Get analysis for the requested file
        Mix.shell().info("Displaying results for: #{path}\n")

        # Find the module in the results
        result = find_analysis_for_file(path, project_results)

        case result do
          {:ok, analysis} ->
            if opts[:json] do
              output_json(analysis, opts)
            else
              output_text(analysis, opts)
            end

            # Clear runtime cache after displaying results
            Litmus.Effects.Registry.clear_runtime_cache()

          {:error, :not_found} ->
            Mix.shell().error("Could not find analysis for file: #{path}")
            Litmus.Effects.Registry.clear_runtime_cache()
            exit({:shutdown, 1})
        end

      {:error, reason} ->
        Mix.shell().error("Project analysis failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  # Extract cache from project results
  defp extract_project_cache(project_results) do
    Enum.reduce(project_results, %{}, fn {_module, analysis}, cache ->
      Enum.reduce(analysis.functions, cache, fn {{_m, _f, _a} = mfa, func_analysis}, acc ->
        Map.put(acc, mfa, Core.to_compact_effect(func_analysis.effect))
      end)
    end)
  end

  # Find analysis result for a specific file
  defp find_analysis_for_file(path, project_results) do
    # Parse the file to get module name
    with {:ok, source} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(source, file: path, line: 1),
         {:ok, module_name} <- extract_module_name_from_ast(ast) do
      case Map.get(project_results, module_name) do
        nil -> {:error, :not_found}
        analysis -> {:ok, analysis}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  # Extract module name from AST
  defp extract_module_name_from_ast({:defmodule, _, [module_ast, _body]}) do
    {:ok, extract_module_name(module_ast)}
  end

  defp extract_module_name_from_ast(_), do: {:error, :not_a_module}

  defp extract_module_name({:__aliases__, _, parts}) do
    Module.concat(parts)
  end

  defp extract_module_name(atom) when is_atom(atom), do: atom
  defp extract_module_name(_), do: nil

  defp discover_app_files do
    get_elixirc_paths()
    |> Enum.flat_map(&find_ex_files/1)
    |> Enum.reject(&litmus_internal_file?/1)
    |> Enum.uniq()
  end

  # Exclude Litmus's own internal files from being analyzed
  # (they use compile-time attributes that cause issues during macro expansion)
  defp litmus_internal_file?(path) do
    String.contains?(path, "lib/litmus/") or
      String.contains?(path, "lib/mix/tasks/")
  end

  defp get_elixirc_paths do
    case Mix.Project.get() do
      nil -> ["lib"]
      _ -> Mix.Project.config()[:elixirc_paths] || ["lib"]
    end
  end

  defp find_ex_files(path) do
    if File.exists?(path) do
      Path.wildcard("#{path}/**/*.ex")
    else
      []
    end
  end

  @deps_cache_path ".effects/deps.cache"
  @deps_checksum_path ".effects/deps.checksum"

  # Convert cache with string keys to MFA tuple keys
  # "Jason.encode/2" => {Jason, :encode, 2}
  defp convert_cache_keys_to_mfa(cache_map) do
    Map.new(cache_map, fn {key, value} ->
      mfa = string_to_mfa(key)
      {mfa, value}
    end)
  end

  # Parse "Module.function/arity" string to {Module, :function, arity} tuple
  defp string_to_mfa(str) do
    case Regex.run(~r/^(.+)\/(\d+)$/, str) do
      [_, func_with_module, arity] ->
        arity_int = String.to_integer(arity)

        # Split module and function
        parts = String.split(func_with_module, ".")
        {func_name, module_parts} = List.pop_at(parts, -1)

        # Convert module parts to atoms and use Module.concat to create proper alias
        module_atoms = Enum.map(module_parts, &String.to_atom/1)
        module = Module.concat(module_atoms)
        function = String.to_atom(func_name)

        {module, function, arity_int}

      _ ->
        # Fallback: return as-is if parsing fails
        raise "Failed to parse MFA string: #{str}"
    end
  end

  defp load_or_analyze_deps do
    # Calculate current dependency checksum
    current_checksum = calculate_deps_checksum()

    # Check if we have a cached checksum
    cached_checksum =
      if File.exists?(@deps_checksum_path) do
        File.read!(@deps_checksum_path) |> String.trim()
      else
        nil
      end

    # If checksum matches and cache exists, load from cache
    if current_checksum == cached_checksum and File.exists?(@deps_cache_path) do
      Mix.shell().info("Loading dependency effects from cache...")

      case File.read(@deps_cache_path) do
        {:ok, content} ->
          cache_map = Jason.decode!(content)
          convert_cache_keys_to_mfa(cache_map)

        _ ->
          # Cache corrupted, re-analyze
          analyze_and_cache_deps(current_checksum)
      end
    else
      # Checksum changed or no cache, re-analyze
      if cached_checksum do
        Mix.shell().info("Dependency checksum changed, re-analyzing dependencies...")
      else
        Mix.shell().info("Analyzing dependencies for the first time...")
      end

      analyze_and_cache_deps(current_checksum)
    end
  end

  defp calculate_deps_checksum do
    # Get Litmus version (critical: if Litmus changes, re-analyze!)
    litmus_version =
      case Mix.Project.get() do
        nil -> "0.0.0"
        _ -> Mix.Project.config()[:version] || "0.0.0"
      end

    # Get all dependency applications
    deps =
      case Mix.Project.get() do
        nil ->
          []

        _ ->
          # Get all loaded applications except the current one
          app_name = Mix.Project.config()[:app]

          Application.loaded_applications()
          |> Enum.map(&elem(&1, 0))
          |> Enum.reject(
            &(&1 == app_name or &1 in [:kernel, :stdlib, :elixir, :compiler, :logger])
          )
      end

    # Create a checksum from Litmus version + dependency names and versions
    # Format: "litmus:0.1.0,jason:1.4.4,purity:0.1.0,..."
    checksum_data =
      ["litmus:#{litmus_version}"] ++
        (deps
         |> Enum.sort()
         |> Enum.map(fn app ->
           version = Application.spec(app, :vsn) || '0.0.0'
           "#{app}:#{version}"
         end))
      |> Enum.join(",")

    # Use Erlang's built-in hash function (no external deps needed)
    :erlang.phash2(checksum_data) |> Integer.to_string(16)
  end

  defp analyze_and_cache_deps(checksum) do
    # Discover all dependency source files
    dep_files = discover_dependency_files()

    if Enum.empty?(dep_files) do
      Mix.shell().info("No dependency source files found to analyze")
      cache = %{}

      # Ensure .effects directory exists
      File.mkdir_p!(".effects")

      # Save empty cache and checksum
      File.write!(@deps_cache_path, Jason.encode!(cache, pretty: true))
      File.write!(@deps_checksum_path, checksum)

      cache
    else
      Mix.shell().info("Analyzing #{length(dep_files)} dependency source files...")

      # Analyze dependencies using project analyzer
      case Analyzer.analyze_project(dep_files, verbose: false) do
        {:ok, results} ->
          # Extract effects from results
          cache = extract_project_cache(results)

          Mix.shell().info("Cached #{map_size(cache)} dependency functions")

          # Ensure .effects directory exists
          File.mkdir_p!(".effects")

          # Convert cache to JSON-serializable format
          json_cache = serialize_cache_for_json(cache)

          # Save cache and checksum
          File.write!(@deps_cache_path, Jason.encode!(json_cache, pretty: true))
          File.write!(@deps_checksum_path, checksum)

          cache

        {:error, reason} ->
          Mix.shell().error("Warning: Dependency analysis failed: #{inspect(reason)}")

          # Return empty cache on error
          cache = %{}
          File.mkdir_p!(".effects")
          File.write!(@deps_cache_path, Jason.encode!(cache, pretty: true))
          File.write!(@deps_checksum_path, checksum)

          cache
      end
    end
  end

  defp discover_dependency_files do
    deps_path = Mix.Project.deps_path()

    if File.exists?(deps_path) do
      # Get runtime dependencies only (exclude :dev and :test only deps)
      runtime_deps = get_runtime_deps()

      # Find all .ex files in dependency lib directories
      Path.wildcard("#{deps_path}/*/lib/**/*.ex")
      # Filter to only runtime dependencies
      |> Enum.filter(fn path ->
        # Extract dep name: deps/jason/lib/... => "jason"
        dep_name = extract_dep_name_from_path(path, deps_path)
        dep_name in runtime_deps
      end)
      # Filter out test files and exclude litmus itself
      |> Enum.reject(fn path ->
        String.contains?(path, "/test/") or
          String.contains?(path, "deps/litmus/")
      end)
    else
      []
    end
  end

  # Extract dependency name from a file path
  # E.g. "/path/to/deps/jason/lib/jason.ex" => "jason"
  defp extract_dep_name_from_path(path, deps_path) do
    path
    |> String.replace_prefix(deps_path <> "/", "")
    |> String.split("/")
    |> List.first()
  end

  defp get_runtime_deps do
    case Mix.Project.get() do
      nil ->
        []

      _ ->
        Mix.Project.config()[:deps]
        |> Enum.reject(fn
          {_name, opts} when is_list(opts) ->
            only = Keyword.get(opts, :only)
            only in [:dev, :test] or only == [:dev, :test]

          {_name, _version, opts} when is_list(opts) ->
            only = Keyword.get(opts, :only)
            only in [:dev, :test] or only == [:dev, :test]

          _ ->
            false
        end)
        |> Enum.map(fn
          {name, _} -> Atom.to_string(name)
          {name, _, _} -> Atom.to_string(name)
        end)
    end
  end

  # Convert cache to JSON-serializable format
  # From: %{{Module, :func, 1} => :p}
  # To: %{"Module.func/1" => "p"}
  defp serialize_cache_for_json(cache) do
    cache
    |> Enum.map(fn {{module, func, arity}, effect} ->
      key = "#{inspect(module)}.#{func}/#{arity}"
      value = effect_to_string(effect)
      {key, value}
    end)
    |> Map.new()
  end

  # Convert effect type to string for JSON serialization
  defp effect_to_string(effect) when is_atom(effect), do: Atom.to_string(effect)

  defp effect_to_string({:s, leaves}) when is_list(leaves) do
    # Side effect with leaves: convert to just "s"
    # (leaves are internal implementation detail)
    "s"
  end

  defp effect_to_string({:e, types}) when is_list(types) do
    # Exception with specific types - just mark as "e"
    # (specific types are complex to serialize and not used in cache lookup)
    "e"
  end

  defp effect_to_string(effect), do: inspect(effect)

  defp output_text(result, opts) do
    module = result.module
    functions = result.functions
    errors = result.errors

    # Header
    Mix.shell().info("═══════════════════════════════════════════════════════════")
    Mix.shell().info("Module: #{inspect(module)}")
    Mix.shell().info("═══════════════════════════════════════════════════════════\n")

    if Enum.empty?(functions) do
      Mix.shell().info("No functions found in module.\n")
    else
      # Sort functions by name and arity
      sorted_functions = Enum.sort_by(functions, fn {{_m, f, a}, _} -> {f, a} end)

      # Apply filter if specified
      filtered_functions =
        case Keyword.get(opts, :filter) do
          nil -> sorted_functions
          filter_type -> filter_by_effect(sorted_functions, filter_type)
        end

      if Enum.empty?(filtered_functions) do
        Mix.shell().info("No functions matching filter criteria.\n")
      else
        Enum.each(filtered_functions, fn {{_m, name, arity}, analysis} ->
          display_function(name, arity, analysis, opts)
        end)
      end
    end

    # Display errors if any
    unless Enum.empty?(errors) do
      Mix.shell().info("\n#{IO.ANSI.yellow()}⚠ Warnings/Errors:#{IO.ANSI.reset()}")
      Mix.shell().info("═══════════════════════════════════════════════════════════\n")

      Enum.each(errors, fn error ->
        {_mod, func, line} = error.location

        Mix.shell().info(
          "  #{IO.ANSI.red()}•#{IO.ANSI.reset()} #{func} (line #{line})\n    #{error.message}\n"
        )
      end)
    end

    # Summary
    Mix.shell().info("\n═══════════════════════════════════════════════════════════")

    counts = count_by_purity(functions)
    pure_count = counts[:p]
    dependent_count = counts[:d]
    lambda_count = counts[:l]
    unknown_count = counts[:u]
    exception_count = counts[:e]
    effectful_count = counts[:s]

    total =
      pure_count + dependent_count + lambda_count + unknown_count + exception_count +
        effectful_count

    Mix.shell().info("Summary: #{total} functions analyzed")
    Mix.shell().info("  #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Pure: #{pure_count}")

    if dependent_count > 0,
      do:
        Mix.shell().info(
          "  #{IO.ANSI.blue()}◐#{IO.ANSI.reset()} Context-dependent: #{dependent_count}"
        )

    if lambda_count > 0,
      do:
        Mix.shell().info(
          "  #{IO.ANSI.cyan()}λ#{IO.ANSI.reset()} Lambda-dependent: #{lambda_count}"
        )

    if unknown_count > 0,
      do: Mix.shell().info("  #{IO.ANSI.magenta()}?#{IO.ANSI.reset()} Unknown: #{unknown_count}")

    if exception_count > 0,
      do: Mix.shell().info("  #{IO.ANSI.red()}⚠#{IO.ANSI.reset()} Exception: #{exception_count}")

    Mix.shell().info("  #{IO.ANSI.yellow()}⚡#{IO.ANSI.reset()} Effectful: #{effectful_count}")

    if not Enum.empty?(errors),
      do: Mix.shell().info("  #{IO.ANSI.red()}⚠#{IO.ANSI.reset()} Errors: #{length(errors)}")

    Mix.shell().info("═══════════════════════════════════════════════════════════\n")
  end

  defp display_function(name, arity, analysis, opts) do
    visibility = if analysis[:visibility] == :defp, do: " (private)", else: ""

    Mix.shell().info("#{IO.ANSI.cyan()}#{name}/#{arity}#{IO.ANSI.reset()}#{visibility}")
    Mix.shell().info("  #{String.duplicate("─", 55)}")

    effect = analysis.effect
    compact_effect = Core.to_compact_effect(effect)
    all_effects = Core.extract_all_effects(effect)

    Mix.shell().info("  #{get_purity_indicator(effect)}")

    # Display all effects if multiple, otherwise just the compact one
    if length(all_effects) > 1 do
      Mix.shell().info("  Effects:")
      Enum.each(all_effects, fn eff ->
        Mix.shell().info("    • #{Formatter.format_compact_effect(eff)}")
      end)
    else
      Mix.shell().info("  Effect: #{Formatter.format_compact_effect(compact_effect)}")
    end

    if opts[:verbose] do
      Mix.shell().info("  Type: #{Formatter.format_type(analysis.type)}")
      Mix.shell().info("  Return: #{Formatter.format_type(analysis.return_type)}")
    end

    display_function_calls(analysis.calls, opts[:verbose])

    if opts[:exceptions] do
      display_exception_info(name, arity, opts)
    end

    Mix.shell().info("")
  end

  defp display_function_calls(calls, _verbose) do
    filtered = filter_noise_calls(calls)

    unless Enum.empty?(filtered) do
      Mix.shell().info("  Calls:")

      filtered
      |> Enum.take(5)
      |> Enum.each(fn {m, f, a} ->
        effect = get_call_effect({m, f, a})
        indicator = get_call_indicator(effect)
        module_name = format_module_name(m)
        Mix.shell().info("    #{indicator} #{module_name}.#{f}/#{a}")
      end)

      if length(filtered) > 5 do
        Mix.shell().info("    ... and #{length(filtered) - 5} more")
      end
    end
  end

  defp get_purity_indicator(effect) do
    compact = Core.to_compact_effect(effect)

    cond do
      Effects.is_pure?(effect) ->
        "#{IO.ANSI.green()}✓ Pure#{IO.ANSI.reset()}"

      compact == :l ->
        "#{IO.ANSI.cyan()}λ Lambda-dependent#{IO.ANSI.reset()}"

      compact == :d or match?({:d, _}, compact) ->
        "#{IO.ANSI.blue()}◐ Context-dependent#{IO.ANSI.reset()}"

      compact == :u ->
        "#{IO.ANSI.magenta()}? Unknown#{IO.ANSI.reset()}"

      match?({:e, _}, compact) or compact == :e ->
        "#{IO.ANSI.red()}⚠ Exception#{IO.ANSI.reset()}"

      true ->
        "#{IO.ANSI.yellow()}⚡ Effectful#{IO.ANSI.reset()}"
    end
  end

  defp get_call_effect({m, f, a}) do
    try do
      Effects.from_mfa({m, f, a})
    rescue
      _ -> {:effect_unknown}
    end
  end

  defp get_call_indicator(effect) do
    compact = Core.to_compact_effect(effect)

    cond do
      Effects.is_pure?(effect) -> IO.ANSI.green() <> "→" <> IO.ANSI.reset()
      compact == :l -> IO.ANSI.cyan() <> "λ" <> IO.ANSI.reset()
      compact == :d or match?({:d, _}, compact) -> IO.ANSI.blue() <> "◐" <> IO.ANSI.reset()
      match?({:e, _}, compact) or compact == :e -> IO.ANSI.red() <> "⚠" <> IO.ANSI.reset()
      compact == :u -> IO.ANSI.magenta() <> "?" <> IO.ANSI.reset()
      true -> IO.ANSI.yellow() <> "⚡" <> IO.ANSI.reset()
    end
  end

  defp filter_by_effect(functions, filter_type) do
    filter_atom =
      case filter_type do
        "p" -> :p
        "s" -> :s
        "l" -> :l
        "d" -> :d
        "e" -> :e
        "u" -> :u
        _ -> nil
      end

    if filter_atom do
      Enum.filter(functions, fn {{_m, _f, _a}, analysis} ->
        compact = Core.to_compact_effect(analysis.effect)

        case filter_atom do
          :p -> Effects.is_pure?(analysis.effect)
          :l -> compact == :l
          :d -> compact == :d or match?({:d, _}, compact)
          :e -> compact == :e or match?({:e, _}, compact)
          :u -> compact == :u
          :s -> match?({:s, _}, compact)
        end
      end)
    else
      functions
    end
  end

  defp format_module_name(module) do
    module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp display_exception_info(_name, _arity, _opts) do
    # Try to get exception information from the existing analysis
    # This would integrate with Litmus.analyze_exceptions if available
    Mix.shell().info(
      "  #{IO.ANSI.faint()}(Exception analysis: run with compiled module)#{IO.ANSI.reset()}"
    )
  end

  defp filter_noise_calls(calls) do
    Enum.reject(calls, fn {module, function, _arity} ->
      module == Kernel and function not in @stateful_kernel_functions
    end)
  end

  defp count_by_purity(functions) do
    initial = %{p: 0, d: 0, l: 0, u: 0, e: 0, s: 0, n: 0}

    Enum.reduce(functions, initial, fn {_mfa, analysis}, acc ->
      compact = Core.to_compact_effect(analysis.effect)

      key =
        cond do
          Effects.is_pure?(analysis.effect) -> :p
          compact == :l -> :l
          compact == :d or match?({:d, _}, compact) -> :d
          compact == :e or match?({:e, _}, compact) -> :e
          compact == :u -> :u
          match?({:s, _}, compact) -> :s
          compact == :n -> :n
          # fallback to unknown
          true -> :u
        end

      Map.update!(acc, key, &(&1 + 1))
    end)
  end

  defp output_json(result, _opts) do
    # Convert to JSON-friendly format
    json_result = %{
      module: inspect(result.module),
      functions:
        Enum.map(result.functions, fn {{m, f, a}, analysis} ->
          %{
            module: inspect(m),
            name: f,
            arity: a,
            effect: Formatter.format_effect(analysis.effect),
            compact_effect: Core.to_compact_effect(analysis.effect) |> compact_effect_to_json(),
            all_effects: Core.extract_all_effects(analysis.effect) |> all_effects_to_json(),
            effect_labels: Effects.to_list(analysis.effect),
            is_pure: Effects.is_pure?(analysis.effect),
            type: Formatter.format_type(analysis.type),
            return_type: Formatter.format_type(analysis.return_type),
            visibility: analysis[:visibility] || :def,
            calls:
              Enum.map(analysis.calls, fn {cm, cf, ca} ->
                %{module: inspect(cm), function: cf, arity: ca}
              end),
            line: analysis.line
          }
        end),
      errors:
        Enum.map(result.errors, fn error ->
          {mod, func, line} = error.location

          %{
            type: error.type,
            message: error.message,
            location: %{module: inspect(mod), function: func, line: line}
          }
        end)
    }

    Mix.shell().info(Jason.encode!(json_result, pretty: true))
  end

  # Convert compact effect to JSON-serializable format
  defp compact_effect_to_json(:p), do: "p"
  defp compact_effect_to_json(:l), do: "l"
  defp compact_effect_to_json(:d), do: "d"
  defp compact_effect_to_json(:u), do: "u"
  defp compact_effect_to_json(:n), do: "n"
  defp compact_effect_to_json({:s, list}), do: %{type: "s", calls: list}
  defp compact_effect_to_json({:d, list}), do: %{type: "d", calls: list}
  defp compact_effect_to_json({:e, types}), do: %{type: "e", exceptions: types}
  defp compact_effect_to_json(other), do: inspect(other)

  # Convert all_effects to JSON-serializable format
  defp all_effects_to_json(effects) when is_list(effects) do
    Enum.map(effects, fn
      {:s, list} -> %{type: "s", calls: list}
      {:d, list} -> %{type: "d", calls: list}
      {:e, types} -> %{type: "e", exceptions: types}
      :p -> "p"
      :l -> "l"
      :u -> "u"
      :n -> "n"
      other -> inspect(other)
    end)
  end

  defp all_effects_to_json(effect), do: [compact_effect_to_json(effect)]
end
