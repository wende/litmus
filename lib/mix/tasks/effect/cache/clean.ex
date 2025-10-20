defmodule Mix.Tasks.Effect.Cache.Clean do
  @moduledoc """
  Cleans the runtime effect cache.

  The effect system maintains a runtime cache in the `.effects` directory
  to speed up cross-module effect inference. This task clears that cache,
  which is useful when:

  - You've updated the `.effects.json` registry
  - You want to force re-analysis of all modules
  - The cache contains stale or incorrect data

  ## Usage

      mix effect.cache.clean

  ## Examples

      # Clean the cache
      mix effect.cache.clean

      # Clean and rebuild
      mix effect.cache.clean && mix compile
  """

  use Mix.Task

  @shortdoc "Clean the runtime effect cache"

  @impl Mix.Task
  def run(_args) do
    cache_dir = ".effects"

    # Clean cache files
    if File.dir?(cache_dir) do
      cache_files = Path.wildcard(Path.join(cache_dir, "**/*.cache"))

      if cache_files == [] do
        Mix.shell().info("No cache files found in #{cache_dir}")
      else
        Enum.each(cache_files, &File.rm!/1)
        Mix.shell().info("Cleaned #{length(cache_files)} cache file(s) from #{cache_dir}")
      end
    else
      Mix.shell().info("Cache directory #{cache_dir} does not exist")
    end

    # Force recompilation of the Registry module to reload .effects.json
    # The Registry loads effects at compile time using @external_resource
    Mix.shell().info("Recompiling Litmus.Effects.Registry to reload .effects.json...")

    registry_beam = "_build/#{Mix.env()}/lib/litmus/ebin/Elixir.Litmus.Effects.Registry.beam"

    if File.exists?(registry_beam) do
      File.rm!(registry_beam)
      Mix.shell().info("Removed compiled Registry module")
    end

    # Recompile
    Mix.Task.run("compile", ["--force"])

    Mix.shell().info("Effect cache cleaned and registry reloaded successfully")
  end
end
