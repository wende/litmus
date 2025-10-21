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

  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Formatter
  alias Litmus.Types.{Core, Effects}

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

    Mix.shell().info(
      "Analyzing #{length(app_files)} application files for cross-module effects...\n"
    )

    # Step 3: Analyze all files to build effect cache
    effect_cache = build_effect_cache(app_files)
    Mix.shell().info("Built effect cache with #{map_size(effect_cache)} functions\n")

    # Step 4: Merge dependency and application caches
    full_cache = Map.merge(deps_cache, effect_cache)

    # Step 5: Set runtime cache for cross-module lookups
    Litmus.Effects.Registry.set_runtime_cache(full_cache)

    # Step 6: Analyze the requested file with full context
    Mix.shell().info("Analyzing: #{path}\n")

    result =
      case File.read(path) do
        {:ok, source} ->
          case Code.string_to_quoted(source, file: path, line: 1) do
            {:ok, ast} ->
              ASTWalker.analyze_ast(ast)

            {:error, {line, error, _}} ->
              {:error, {:parse_error, line, error}}
          end

        {:error, reason} ->
          {:error, {:file_error, reason}}
      end

    case result do
      {:ok, analysis} ->
        if opts[:json] do
          output_json(analysis, opts)
        else
          output_text(analysis, opts)
        end

        # Clear runtime cache after displaying results
        Litmus.Effects.Registry.clear_runtime_cache()

      {:error, {:parse_error, line, error}} ->
        Mix.shell().error("Parse error at line #{line}: #{error}")
        Litmus.Effects.Registry.clear_runtime_cache()
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Analysis failed: #{inspect(reason)}")
        Litmus.Effects.Registry.clear_runtime_cache()
        exit({:shutdown, 1})
    end
  end

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
          Jason.decode!(content)

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

    # Create a checksum from dependency names and versions
    checksum_data =
      deps
      |> Enum.sort()
      |> Enum.map(fn app ->
        version = Application.spec(app, :vsn) || '0.0.0'
        "#{app}:#{version}"
      end)
      |> Enum.join(",")

    # Use Erlang's built-in hash function (no external deps needed)
    :erlang.phash2(checksum_data) |> Integer.to_string(16)
  end

  defp analyze_and_cache_deps(checksum) do
    # For now, return empty cache - full dependency analysis can be added later
    # This would involve discovering all dependency modules and analyzing them
    cache = %{}

    # Ensure .effects directory exists
    File.mkdir_p!(".effects")

    # Save cache and checksum
    File.write!(@deps_cache_path, Jason.encode!(cache, pretty: true))
    File.write!(@deps_checksum_path, checksum)

    cache
  end

  defp build_effect_cache(files) do
    Litmus.Effects.Registry.set_permissive_mode(true)

    cache =
      files
      |> Enum.reduce(%{}, &merge_file_effects(&2, &1))

    Litmus.Effects.Registry.set_permissive_mode(false)

    cache
  end

  defp merge_file_effects(acc, file) do
    case analyze_file_safely(file) do
      {:ok, analysis} -> Map.merge(acc, extract_file_effects(analysis))
      :error -> acc
    end
  end

  defp analyze_file_safely(file) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, file: file, line: 1),
         {:ok, analysis} <- ASTWalker.analyze_ast(ast) do
      {:ok, analysis}
    else
      _ -> :error
    end
  end

  defp extract_file_effects(analysis) do
    analysis.functions
    |> Enum.map(fn {{m, f, a}, func_analysis} ->
      {{m, f, a}, Core.to_compact_effect(func_analysis.effect)}
    end)
    |> Map.new()
  end

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
            compact_effect: Core.to_compact_effect(analysis.effect),
            all_effects: Core.extract_all_effects(analysis.effect),
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
end
