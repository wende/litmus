defmodule Litmus.Registry.Builder do
  @moduledoc """
  Builds a comprehensive effects registry for all modules in the current application scope.

  This module discovers all compiled modules (application + dependencies) and analyzes
  their functions to infer effects, generating a complete registry at compile time.
  """

  alias Litmus.Analyzer.ASTWalker
  alias Litmus.Types.Core

  @doc """
  Generates a complete effects registry for all modules in scope.

  Returns a map of `{module, function, arity} => effect_type` where effect_type
  is one of `:p` (pure), `:e` (exceptions), `:d` (dependent), `:l` (lambda-dependent),
  `:n` (nif), `:s` (side effects), or `:u` (unknown).

  ## Options

  - `:include_deps` - Include dependency modules (default: true)
  - `:include_stdlib` - Include stdlib modules already in .effects.json (default: false)
  - `:exclude_modules` - List of module names to exclude
  """
  def build_registry(opts \\ []) do
    include_deps = Keyword.get(opts, :include_deps, true)
    include_stdlib = Keyword.get(opts, :include_stdlib, false)
    exclude_modules = Keyword.get(opts, :exclude_modules, [])

    IO.puts("Building effects registry...")

    modules = discover_modules(include_deps)
    IO.puts("Found #{length(modules)} modules to analyze")

    # Filter out excluded modules and optionally stdlib
    modules =
      Enum.reject(modules, fn mod ->
        mod in exclude_modules or
          (not include_stdlib and is_stdlib_module?(mod))
      end)

    IO.puts("Analyzing #{length(modules)} modules after filtering...")

    # Analyze each module
    registry =
      modules
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {module, idx}, acc ->
        if rem(idx, 10) == 0 do
          IO.write("\rProgress: #{idx}/#{length(modules)} modules")
        end

        case analyze_module(module) do
          {:ok, module_registry} ->
            Map.merge(acc, module_registry)

          {:error, _reason} ->
            # Skip modules that can't be analyzed
            acc
        end
      end)

    IO.puts("\n\nRegistry built with #{map_size(registry)} function entries")
    registry
  end

  @doc """
  Discovers all modules in the current application scope.
  """
  def discover_modules(include_deps \\ true) do
    # Get all loaded modules
    loaded_modules =
      :code.all_loaded()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(&is_atom/1)

    # Also scan ebin directories for compiled modules
    app_name = Mix.Project.config()[:app]
    ebin_path = "_build/#{Mix.env()}/lib/#{app_name}/ebin"

    beam_modules =
      if File.exists?(ebin_path) do
        Path.wildcard("#{ebin_path}/*.beam")
        |> Enum.map(fn path ->
          Path.basename(path, ".beam")
          |> String.to_atom()
        end)
      else
        []
      end

    # Combine and deduplicate
    all_modules = (loaded_modules ++ beam_modules) |> Enum.uniq()

    if include_deps do
      all_modules
    else
      # Filter to only application modules (modules that start with the app namespace)
      app_namespace = app_name |> Atom.to_string() |> Macro.camelize()

      Enum.filter(all_modules, fn mod ->
        mod_str = Atom.to_string(mod)
        # Include modules from our app namespace (e.g., Litmus, Demo, SampleModule)
        # but exclude dependencies (e.g., Mix, Elixir.String, Jason, etc.)
        case mod_str do
          "Elixir." <> rest ->
            # Check if it's from our application
            # Include simple module names like Demo, SampleModule
            String.starts_with?(rest, app_namespace) or
              (not String.contains?(rest, ".") and not is_elixir_stdlib?(mod))

          _ ->
            # Include erlang modules if they're custom (rare)
            false
        end
      end)
    end
  end

  defp is_elixir_stdlib?(module) do
    # Match the comprehensive stdlib list from Registry
    elixir_stdlib = [
      # Core data structures (mostly pure)
      Access,
      Atom,
      Base,
      Bitwise,
      Date,
      DateTime,
      Duration,
      Enum,
      Float,
      Function,
      Integer,
      Keyword,
      List,
      Map,
      MapSet,
      NaiveDateTime,
      Range,
      Regex,
      Stream,
      String,
      StringIO,
      Time,
      Tuple,
      URI,
      Version,

      # I/O and File operations (side effects)
      File,
      File.Stat,
      File.Stream,
      IO,
      IO.ANSI,
      IO.Stream,

      # Process and concurrency (side effects)
      Agent,
      Application,
      Code,
      DynamicSupervisor,
      GenEvent,
      GenServer,
      Node,
      PartitionSupervisor,
      Port,
      Process,
      Registry,
      Supervisor,
      Task,
      Task.Supervisor,

      # System operations (side effects)
      Logger,
      System,

      # Special modules
      Kernel,
      Kernel.SpecialForms,

      # Metaprogramming
      Macro,
      Macro.Env,
      Module,

      # Utilities
      Calendar,
      Config,
      Exception,
      Inspect,
      OptionParser,
      Path,
      Protocol,
      Record
    ]

    erlang_stdlib = [
      :erlang,
      :lists,
      :maps,
      :sets,
      :ordsets,
      :orddict,
      :sofs,
      :gb_sets,
      :gb_trees,
      :queue,
      :proplists,
      :string,
      :binary,
      :unicode,
      :re,
      :file,
      :filename,
      :io,
      :prim_file,
      :inet,
      :inet_db,
      :inet_parse,
      :gen_tcp,
      :gen_udp,
      :ssl,
      :gen_server,
      :gen_event,
      :supervisor,
      :proc_lib,
      :sys,
      :application,
      :ets,
      :dets,
      :persistent_term,
      :atomics,
      :counters,
      :rand,
      :random,
      :os,
      :init,
      :code,
      :error_logger,
      :logger,
      :zlib,
      :rpc,
      :global,
      :global_group,
      :erts_internal,
      :erl_eval,
      :erl_scan,
      :erl_parse
    ]

    module in elixir_stdlib or module in erlang_stdlib
  end

  @doc """
  Builds a registry for a specific list of modules.
  """
  def build_registry_for_modules(modules, opts \\ []) do
    include_stdlib = Keyword.get(opts, :include_stdlib, false)

    # Filter out stdlib modules if requested
    modules =
      if include_stdlib do
        modules
      else
        Enum.reject(modules, &is_stdlib_module?/1)
      end

    # Analyze each module
    modules
    |> Enum.with_index(1)
    |> Enum.reduce(%{}, fn {module, idx}, acc ->
      if rem(idx, 10) == 0 do
        IO.write("\rProgress: #{idx}/#{length(modules)} modules")
      end

      case analyze_module(module) do
        {:ok, module_registry} ->
          Map.merge(acc, module_registry)

        {:error, _reason} ->
          # Skip modules that can't be analyzed
          acc
      end
    end)
  end

  @doc """
  Analyzes a single module and returns its effects registry.
  """
  def analyze_module(module) do
    # Enable permissive mode during analysis to avoid circular dependencies
    Litmus.Effects.Registry.set_permissive_mode(true)

    result =
      try do
        with {:ok, source_file} <- get_source_file(module),
             true <- File.exists?(source_file),
             {:ok, content} <- File.read(source_file),
             {:ok, ast} <- Code.string_to_quoted(content, file: source_file, line: 1),
             {:ok, analysis_result} <- ASTWalker.analyze_ast(ast) do
          # Convert analysis results to registry format
          registry =
            analysis_result.functions
            |> Enum.map(fn {{m, f, a}, analysis} ->
              effect_type = Core.to_compact_effect(analysis.effect)
              {{m, f, a}, effect_type}
            end)
            |> Map.new()

          {:ok, registry}
        else
          error ->
            # Debug: show why source analysis failed
            if System.get_env("DEBUG_REGISTRY") do
              IO.puts("  Failed to analyze #{module} from source: #{inspect(error)}")
            end

            # Fall back to BEAM analysis if source not available
            analyze_module_from_beam(module)
        end
      rescue
        e in ArgumentError ->
          # Handle errors from analyzing already-compiled modules with @ attributes
          if System.get_env("DEBUG_REGISTRY") do
            IO.puts("  Error analyzing #{module} from source (#{inspect(e.message)}), falling back to BEAM")
          end

          analyze_module_from_beam(module)

        e ->
          # For any other error, fall back to BEAM analysis
          if System.get_env("DEBUG_REGISTRY") do
            IO.puts("  Unexpected error analyzing #{module} from source: #{inspect(e)}, falling back to BEAM")
          end

          analyze_module_from_beam(module)
      end

    # Restore strict mode
    Litmus.Effects.Registry.set_permissive_mode(false)

    result
  end

  @doc """
  Analyzes a module from its BEAM bytecode when source is not available.
  Uses PURITY analyzer for actual effect analysis instead of heuristics.
  """
  def analyze_module_from_beam(module) do
    # Try PURITY analysis first (analyzes actual BEAM bytecode)
    # PURITY was written for Erlang in 2011 and may fail on modern Elixir code
    try do
      case Litmus.analyze_module(module) do
        {:ok, purity_results} ->
          # Convert PURITY results to registry format
          # Filter to only proper MFAs (module, function, arity tuples)
          registry =
            purity_results
            |> Enum.filter(fn
              {{m, f, a}, _level} when is_atom(m) and is_atom(f) and is_integer(a) -> true
              _ -> false
            end)
            |> Enum.map(fn {{m, f, a}, purity_level} ->
              # Convert PURITY level to compact effect type
              effect = purity_level_to_effect(purity_level)
              {{m, f, a}, effect}
            end)
            |> Map.new()

          {:ok, registry}

        {:error, _reason} ->
          # PURITY failed, fall back to heuristics
          analyze_with_heuristics(module)
      end
    rescue
      _e ->
        # PURITY crashed on modern Elixir bytecode, fall back to heuristics
        if System.get_env("DEBUG_REGISTRY") do
          IO.puts("  PURITY analysis failed for #{module}, using heuristics")
        end

        analyze_with_heuristics(module)
    end
  end

  defp analyze_with_heuristics(module) do
    with {:ok, exports} <- get_module_exports(module) do
      registry =
        exports
        |> Enum.map(fn {f, a} ->
          effect = infer_effect_from_name(module, f, a)
          {{module, f, a}, effect}
        end)
        |> Map.new()

      {:ok, registry}
    else
      _ -> {:error, :no_beam_info}
    end
  end

  # Convert PURITY purity level to compact effect type
  defp purity_level_to_effect(:pure), do: :p
  defp purity_level_to_effect(:exceptions), do: :exn
  defp purity_level_to_effect(:dependent), do: :d
  defp purity_level_to_effect(:lambda_dependent), do: :l
  defp purity_level_to_effect(:nif), do: :n
  defp purity_level_to_effect(:side_effects), do: :s
  defp purity_level_to_effect(:unknown), do: :u
  defp purity_level_to_effect(_), do: :u

  @doc """
  Gets the source file path for a module.
  """
  def get_source_file(module) do
    case :code.which(module) do
      path when is_list(path) ->
        beam_file = List.to_string(path)
        module_name = module |> Atom.to_string() |> String.replace("Elixir.", "")

        # Try multiple possible source locations
        candidates = [
          # Dependency in deps/ directory
          # _build/dev/lib/jason/ebin/Elixir.Jason.beam -> deps/jason/lib/jason.ex
          beam_file
          |> String.replace(~r/\.beam$/, ".ex")
          |> String.replace(~r/_build\/[^\/]+\/lib\/([^\/]+)\/ebin/, "deps/\\1/lib"),

          # Application module in lib/
          # _build/dev/lib/my_app/ebin/Elixir.MyApp.beam -> lib/my_app.ex
          beam_file
          |> String.replace(~r/\.beam$/, ".ex")
          |> String.replace(~r/_build\/[^\/]+\/lib\/[^\/]+\/ebin/, "lib"),

          # Test support directory (for test modules)
          "test/support/#{Macro.underscore(module_name)}.ex",

          # Root level (for simple modules like Demo)
          "#{Macro.underscore(module_name)}.ex",

          # Lib directory directly
          "lib/#{Macro.underscore(module_name)}.ex"
        ]

        # Return first existing candidate
        case Enum.find(candidates, &File.exists?/1) do
          nil -> {:error, :source_not_found}
          source_file -> {:ok, source_file}
        end

      _ ->
        {:error, :no_beam_file}
    end
  end

  @doc """
  Gets exported functions for a module.
  """
  def get_module_exports(module) do
    try do
      exports = module.__info__(:functions)
      {:ok, exports}
    rescue
      _ ->
        case :code.which(module) do
          path when is_list(path) ->
            case :beam_lib.chunks(path, [:exports]) do
              {:ok, {^module, [{:exports, exports}]}} ->
                {:ok, exports}

              _ ->
                {:error, :no_exports}
            end

          _ ->
            {:error, :no_module}
        end
    end
  end

  @doc """
  Infers effect from function/module naming conventions and patterns.
  """
  def infer_effect_from_name(module, function, _arity) do
    function_str = Atom.to_string(function)
    module_str = Atom.to_string(module)

    cond do
      # Functions with ! typically have side effects or raise
      String.ends_with?(function_str, "!") ->
        if module_str =~ ~r/(File|IO|Agent|Process|GenServer|Task)/ do
          # Side effects
          :s
        else
          # Likely raises
          :exn
        end

      # Functions with ? are typically pure predicates
      String.ends_with?(function_str, "?") ->
        :p

      # Known pure patterns
      function in [:get, :fetch, :take, :put, :update, :delete, :new, :merge, :split, :join] ->
        :p

      # Module-based inference
      String.contains?(module_str, "Enum") or String.contains?(module_str, "List") or
        String.contains?(module_str, "Map") or String.contains?(module_str, "String") or
        String.contains?(module_str, "Tuple") or String.contains?(module_str, "Keyword") or
        String.contains?(module_str, "Range") or String.contains?(module_str, "Stream") ->
        :p

      # Effect modules
      String.contains?(module_str, "File") or String.contains?(module_str, "IO") or
        String.contains?(module_str, "Process") or String.contains?(module_str, "Agent") or
        String.contains?(module_str, "Task") or String.contains?(module_str, "GenServer") ->
        :s

      # Default to unknown for safety
      true ->
        :u
    end
  end

  @doc """
  Checks if a module is from the standard library.
  """
  def is_stdlib_module?(module) do
    stdlib_modules = [
      File,
      IO,
      Process,
      Port,
      Agent,
      Task,
      GenServer,
      Supervisor,
      Application,
      Logger,
      System,
      Code,
      Kernel,
      :erlang,
      :gen_tcp,
      :gen_udp,
      :inet,
      :ssl,
      :ets,
      :dets,
      :rand,
      :random,
      :os
    ]

    module in stdlib_modules
  end

  @doc """
  Exports the registry to JSON format compatible with .effects.json.
  """
  def export_to_json(registry, output_path \\ ".effects.generated.json") do
    # Group by module
    grouped =
      registry
      |> Enum.group_by(
        fn {{m, _f, _a}, _effect} -> module_to_string(m) end,
        fn {{_m, f, a}, effect} -> {"#{f}/#{a}", effect_to_json(effect)} end
      )
      |> Enum.map(fn {module, functions} ->
        {module, Map.new(functions)}
      end)
      |> Map.new()

    # Add metadata
    output =
      Map.put(grouped, "_metadata", %{
        "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "litmus_version" => Mix.Project.config()[:version],
        "total_functions" => map_size(registry)
      })

    json = Jason.encode!(output, pretty: true)
    File.write!(output_path, json)

    IO.puts("Registry exported to #{output_path}")
    :ok
  end

  defp module_to_string(module) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir." <> rest -> "Elixir." <> rest
      name -> name
    end
  end

  defp effect_to_json(:p), do: "p"
  defp effect_to_json(:d), do: "d"
  defp effect_to_json(:l), do: "l"
  defp effect_to_json(:n), do: "n"
  defp effect_to_json(:s), do: "s"
  defp effect_to_json(:u), do: "u"
  defp effect_to_json(:exn), do: %{"e" => ["exn"]}
  defp effect_to_json({:e, types}), do: %{"e" => types}
  # Handle new MFA list formats
  defp effect_to_json({:s, mfas}), do: %{"s" => mfas}
  defp effect_to_json({:d, mfas}), do: %{"d" => mfas}

  @doc """
  Merges a generated registry with the existing .effects.json file.

  The existing registry takes precedence for any conflicts.
  """
  def merge_with_existing(generated_registry, existing_path \\ ".effects.json") do
    if File.exists?(existing_path) do
      {:ok, content} = File.read(existing_path)
      existing = Jason.decode!(content)

      # Convert existing to MFA format
      existing_mfas =
        existing
        |> Enum.reject(fn {key, _} -> String.starts_with?(key, "_") end)
        |> Enum.flat_map(fn {module_name, functions} ->
          module = string_to_module(module_name)

          Enum.map(functions, fn {func_arity, effect} ->
            case String.reverse(func_arity) |> String.split("/", parts: 2) do
              [reversed_arity, reversed_name] ->
                func_name = String.reverse(reversed_name)
                arity = String.reverse(reversed_arity) |> String.to_integer()
                func_atom = String.to_atom(func_name)

                effect_atom =
                  case effect do
                    "p" -> :p
                    "n" -> :n
                    "s" -> :s
                    "u" -> :u
                    %{"e" => _} -> :exn
                    _ -> :u
                  end

                {{module, func_atom, arity}, effect_atom}
            end
          end)
        end)
        |> Map.new()

      # Merge: existing takes precedence
      merged = Map.merge(generated_registry, existing_mfas)

      IO.puts(
        "Merged #{map_size(existing_mfas)} existing entries with #{map_size(generated_registry)} generated entries"
      )

      IO.puts("Total: #{map_size(merged)} entries")

      merged
    else
      IO.puts("No existing registry found, using generated only")
      generated_registry
    end
  end

  defp string_to_module("Elixir." <> rest), do: Module.concat([rest])
  defp string_to_module(name), do: String.to_atom(name)

  @doc """
  Builds a resolution mapping from stdlib functions to their leaf BIFs.

  Returns a map of `{module, function, arity} => [leaf_bif_mfas]`.
  """
  def build_resolution_mapping(stdlib_modules) do
    alias Litmus.Analyzer.CallGraphTracer

    IO.puts("\nBuilding resolution mapping for #{length(stdlib_modules)} stdlib modules...")

    mapping =
      stdlib_modules
      |> Enum.with_index(1)
      |> Enum.reduce(%{}, fn {module, idx}, acc ->
        if rem(idx, 5) == 0 do
          IO.write("\rProgress: #{idx}/#{length(stdlib_modules)} modules")
        end

        case get_module_exports(module) do
          {:ok, exports} ->
            module_mapping =
              exports
              |> Enum.map(fn {function, arity} ->
                mfa = {module, function, arity}

                case CallGraphTracer.trace_to_leaf(module, function, arity) do
                  {:ok, [^mfa]} ->
                    # Resolves to itself - it's a leaf, don't include in mapping
                    nil

                  {:ok, leaves} when leaves != [mfa] ->
                    # Resolves to different leaf(s) - include in mapping
                    {mfa, leaves}

                  _ ->
                    # Error or unknown - don't include
                    nil
                end
              end)
              |> Enum.reject(&is_nil/1)
              |> Map.new()

            Map.merge(acc, module_mapping)

          _ ->
            acc
        end
      end)

    IO.puts("\n\nGenerated resolution mapping for #{map_size(mapping)} functions")
    mapping
  end

  @doc """
  Exports the resolution mapping to JSON format.
  """
  def export_resolution_to_json(mapping, output_path \\ ".effects_resolution.json") do
    # Group by module for readability
    grouped =
      mapping
      |> Enum.group_by(
        fn {{m, _f, _a}, _leaves} -> module_to_string(m) end,
        fn {{_m, f, a}, leaves} ->
          mfa_str = "#{f}/#{a}"

          leaf_strs =
            Enum.map(leaves, fn {lm, lf, la} ->
              "#{module_to_string(lm)}.#{lf}/#{la}"
            end)

          {mfa_str, leaf_strs}
        end
      )
      |> Enum.map(fn {module, functions} ->
        {module, Map.new(functions)}
      end)
      |> Map.new()

    # Add metadata
    output =
      Map.put(grouped, "_metadata", %{
        "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "litmus_version" => Mix.Project.config()[:version],
        "total_resolutions" => map_size(mapping),
        "description" => "Maps stdlib functions to their leaf BIFs"
      })

    json = Jason.encode!(output, pretty: true)
    File.write!(output_path, json)

    IO.puts("Resolution mapping exported to #{output_path}")
    :ok
  end

  @doc """
  Filters a registry to only include leaf BIFs, removing wrapper functions.
  """
  def filter_to_leaf_bifs(registry) do
    alias Litmus.Analyzer.CallGraphTracer

    IO.puts("\nFiltering registry to only leaf BIFs...")

    registry
    |> Enum.filter(fn {{module, function, arity}, _effect} ->
      CallGraphTracer.is_bif?(module, function, arity)
    end)
    |> Map.new()
  end
end
