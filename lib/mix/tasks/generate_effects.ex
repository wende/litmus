defmodule Mix.Tasks.GenerateEffects do
  @moduledoc """
  Generates a comprehensive effects registry for all modules in scope.

  This task discovers all modules in the current application and its dependencies,
  analyzes their functions to infer effects, and generates separate registry files
  in the .effects/ directory.

  ## Usage

      mix generate_effects [options]

  ## Options

      --include-deps     Include dependency modules (default: false)
      --include-stdlib   Include stdlib modules from .effects.json

  ## Output

  Creates .effects/ directory with:
    - .effects/generated - Effects for application modules
    - .effects/deps - Effects for dependency modules (if --include-deps)

  ## Examples

      # Generate registry for app modules only
      mix generate_effects

      # Generate including dependencies
      mix generate_effects --include-deps

      # Generate including stdlib
      mix generate_effects --include-stdlib
  """

  use Mix.Task

  alias Litmus.Registry.Builder

  @shortdoc "Generates effects registry for all modules in scope"

  @impl Mix.Task
  def run(args) do
    # Ensure application is compiled and loaded
    Mix.Task.run("compile")
    Mix.Task.run("loadpaths")

    # Load all applications to get all modules
    Mix.Task.run("app.start")

    {opts, _, _} = OptionParser.parse(args,
      switches: [
        include_deps: :boolean,
        include_stdlib: :boolean
      ],
      aliases: []
    )

    include_deps = Keyword.get(opts, :include_deps, false)
    include_stdlib = Keyword.get(opts, :include_stdlib, false)

    Mix.shell().info("╔═══════════════════════════════════════════════════════╗")
    Mix.shell().info("║     Litmus Effects Registry Generator                ║")
    Mix.shell().info("╚═══════════════════════════════════════════════════════╝\n")

    # Create .effects directory
    effects_dir = ".effects"
    File.mkdir_p!(effects_dir)

    # Get application name
    app_name = Mix.Project.config()[:app]

    # Build registries separately for app and deps
    Mix.shell().info("Analyzing application modules...")

    # Get elixirc_paths from mix.exs
    elixirc_paths = Mix.Project.config()[:elixirc_paths] || ["lib"]
    Mix.shell().info("Using elixirc_paths: #{inspect(elixirc_paths)}")

    # Discover modules only from elixirc_paths
    app_modules = discover_modules_from_paths(elixirc_paths)
    Mix.shell().info("Found #{length(app_modules)} application modules")

    app_registry = Builder.build_registry_for_modules(app_modules, include_stdlib: include_stdlib)

    # Export app registry
    app_output = Path.join(effects_dir, "generated")
    Builder.export_to_json(app_registry, app_output)

    {app_pure, app_s, app_e, app_n, app_u} = categorize_effects(app_registry)

    Mix.shell().info("\n✓ Application effects saved to #{app_output}")
    Mix.shell().info("  Total functions: #{map_size(app_registry)}")
    Mix.shell().info("  • Pure (p):          #{app_pure}")
    Mix.shell().info("  • Side effects (s):  #{app_s}")
    Mix.shell().info("  • Exceptions (e):    #{app_e}")
    Mix.shell().info("  • NIFs (n):          #{app_n}")
    Mix.shell().info("  • Unknown (u):       #{app_u}")

    # Build deps registry if requested
    if include_deps do
      Mix.shell().info("\nAnalyzing dependency modules...")
      dep_modules = get_dep_modules(app_name)
      deps_registry = Builder.build_registry_for_modules(dep_modules, include_stdlib: include_stdlib)

      # Export deps registry
      deps_output = Path.join(effects_dir, "deps")
      Builder.export_to_json(deps_registry, deps_output)

      {dep_pure, dep_s, dep_e, dep_n, dep_u} = categorize_effects(deps_registry)

      Mix.shell().info("\n✓ Dependency effects saved to #{deps_output}")
      Mix.shell().info("  Total functions: #{map_size(deps_registry)}")
      Mix.shell().info("  • Pure (p):          #{dep_pure}")
      Mix.shell().info("  • Side effects (s):  #{dep_s}")
      Mix.shell().info("  • Exceptions (e):    #{dep_e}")
      Mix.shell().info("  • NIFs (n):          #{dep_n}")
      Mix.shell().info("  • Unknown (u):       #{dep_u}")
    end

    Mix.shell().info("\n╔═══════════════════════════════════════════════════════╗")
    Mix.shell().info("║     Complete                                          ║")
    Mix.shell().info("╚═══════════════════════════════════════════════════════╝\n")
  end

  defp discover_modules_from_paths(paths) do
    # Find all .ex files in the specified paths
    source_files = Enum.flat_map(paths, fn path ->
      Path.wildcard("#{path}/**/*.ex")
    end)

    # Extract module names from source files
    Enum.flat_map(source_files, fn file ->
      case File.read(file) do
        {:ok, content} ->
          # Extract module names using regex
          Regex.scan(~r/defmodule\s+([\w.]+)/, content)
          |> Enum.map(fn [_, module_name] ->
            # Convert string to module atom
            # For "Demo" -> Demo, for "Litmus.Pure" -> Litmus.Pure
            String.to_atom("Elixir.#{module_name}")
          end)

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end

  defp get_dep_modules(app_name) do
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(fn module ->
      case :application.get_application(module) do
        {:ok, app} -> app != app_name
        _ -> false
      end
    end)
  end

  defp categorize_effects(registry) do
    Enum.reduce(registry, {0, 0, 0, 0, 0}, fn {_mfa, effect}, {p, s, e, n, u} ->
      case effect do
        :p -> {p + 1, s, e, n, u}
        :s -> {p, s + 1, e, n, u}
        :exn -> {p, s, e + 1, n, u}
        :n -> {p, s, e, n + 1, u}
        :u -> {p, s, e, n, u + 1}
        _ -> {p, s, e, n, u + 1}
      end
    end)
  end
end
