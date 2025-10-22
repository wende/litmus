# Objective 007: Source Discovery System

## Objective
Build a comprehensive source discovery system that finds all analyzable files (Elixir, Erlang, BEAM) across different dependency types, build systems, and project structures, ensuring 100% coverage of available sources.

## Description
Current source discovery only finds `deps/*/lib/**/*.ex` files, missing Erlang sources, umbrella apps, non-standard layouts, and compiled-only dependencies. The new system will understand all dependency types (hex, git, path, umbrella), find sources in any location, handle different build systems (mix, rebar3, erlang.mk), and fall back to BEAM files when sources are unavailable.

### Key Problems Solved
- Missing Erlang source files (.erl)
- Umbrella apps not discovered correctly
- Git dependencies with non-standard structure
- Rebar3/erlang.mk projects not handled
- Archives and escript files ignored

## Testing Criteria
1. **Discovery Coverage**
   - Finds 100% of .ex files in any location
   - Finds 100% of .erl files in any location
   - Handles umbrella apps with nested dependencies
   - Discovers sources in git submodules
   - Falls back to BEAM files appropriately

2. **Dependency Types**
   - Hex packages: standard and non-standard layouts
   - Git dependencies: any repository structure
   - Path dependencies: local projects
   - Umbrella apps: nested applications
   - Archives (.ez files)

3. **Build Systems**
   - Mix projects
   - Rebar3 projects
   - Erlang.mk projects
   - Raw OTP applications
   - Hybrid projects

## Detailed Implementation Guidance

### File: `lib/litmus/discovery/source_finder.ex`

```elixir
defmodule Litmus.Discovery.SourceFinder do
  @moduledoc """
  Comprehensive source file discovery across all dependency types.
  """

  def discover_all_sources do
    %{
      project: discover_project_sources(),
      deps: discover_dependency_sources(),
      erlang: discover_erlang_sources(),
      archives: discover_archive_sources()
    }
  end

  defp discover_dependency_sources do
    {:ok, lock} = read_mix_lock()
    deps_path = Mix.Project.deps_path()

    Enum.flat_map(lock, fn {dep_name, dep_info} ->
      discover_dep_sources(dep_name, dep_info, deps_path)
    end)
  end

  defp discover_dep_sources(name, dep_info, deps_path) do
    case dep_info do
      {:hex, _package, version, _hash, _managers, _deps, _hexpm, _hash2} ->
        find_hex_sources(deps_path, name, version)

      {:git, url, ref, opts} ->
        find_git_sources(deps_path, name, url, ref, opts)

      {:path, path, opts} ->
        find_path_sources(path, opts)

      {:umbrella, app_name, opts} ->
        find_umbrella_sources(app_name, opts)

      _ ->
        []
    end
  end
end
```

### Discovery Strategies

1. **Hex Package Discovery**
   ```elixir
   defp find_hex_sources(deps_path, name, version) do
     base = Path.join(deps_path, to_string(name))

     # Priority order
     sources = []

     # 1. Elixir sources (Mix projects)
     sources = sources ++ find_files(base, "lib/**/*.ex")
     sources = sources ++ find_files(base, "lib/**/*.exs")

     # 2. Erlang sources
     sources = sources ++ find_files(base, "src/**/*.erl")
     sources = sources ++ find_files(base, "src/**/*.hrl")

     # 3. Check for umbrella structure
     if File.exists?(Path.join(base, "apps")) do
       sources = sources ++ find_files(base, "apps/*/lib/**/*.ex")
       sources = sources ++ find_files(base, "apps/*/src/**/*.erl")
     end

     # 4. Generated sources (protocol consolidations)
     sources = sources ++ find_files(base, "_build/*/lib/*/ebin/*.beam")

     # 5. Compiled only (no sources)
     if sources == [] do
       find_beam_files(base)
     else
       mark_sources(sources, :source)
     end
   end
   ```

2. **Git Dependency Discovery**
   ```elixir
   defp find_git_sources(deps_path, name, url, ref, opts) do
     base = Path.join(deps_path, to_string(name))

     # Check for sparse checkout
     sparse = Keyword.get(opts, :sparse, false)

     # Check for subdirectory
     subdir = Keyword.get(opts, :subdir, "")

     # Adjust base path
     search_base = Path.join(base, subdir)

     # Look for build file to determine project type
     cond do
       File.exists?(Path.join(search_base, "mix.exs")) ->
         find_mix_project_sources(search_base)

       File.exists?(Path.join(search_base, "rebar.config")) ->
         find_rebar_project_sources(search_base)

       File.exists?(Path.join(search_base, "Makefile")) ->
         find_makefile_project_sources(search_base)

       true ->
         find_all_sources_recursive(search_base)
     end
   end
   ```

3. **Build System Detection**
   ```elixir
   defp detect_build_system(path) do
     cond do
       File.exists?(Path.join(path, "mix.exs")) -> :mix
       File.exists?(Path.join(path, "rebar.config")) -> :rebar3
       File.exists?(Path.join(path, "rebar")) -> :rebar
       File.exists?(Path.join(path, "Makefile")) -> :make
       File.exists?(Path.join(path, "Emakefile")) -> :emake
       true -> :unknown
     end
   end

   defp find_sources_for_build_system(path, :rebar3) do
     # Parse rebar.config for source directories
     {:ok, config} = read_rebar_config(path)
     src_dirs = get_in(config, [:erl_opts, :src_dirs]) || ["src"]

     Enum.flat_map(src_dirs, fn dir ->
       find_files(path, "#{dir}/**/*.{erl,hrl}")
     end)
   end
   ```

4. **Archive Discovery**
   ```elixir
   defp discover_archive_sources do
     # Find .ez archives
     archives = Path.wildcard("#{:code.lib_dir()}/*.ez")

     Enum.flat_map(archives, fn archive ->
       # Extract and analyze archive contents
       {:ok, files} = :zip.list_dir(to_charlist(archive))

       files
       |> Enum.map(fn {:zip_file, path, _, _, _, _} ->
         List.to_string(path)
       end)
       |> Enum.filter(&source_file?/1)
       |> Enum.map(fn file ->
         {:archive, archive, file}
       end)
     end)
   end
   ```

### Source Metadata

```elixir
defmodule Litmus.Discovery.SourceInfo do
  defstruct [
    :path,           # Full path to source file
    :type,           # :elixir, :erlang, :beam, :leex, :yecc
    :module,         # Module name if determinable
    :build_system,   # :mix, :rebar3, :make, etc.
    :dependency,     # Dependency name
    :location        # :project, :deps, :stdlib, :archive
  ]

  def categorize(path) do
    %__MODULE__{
      path: path,
      type: detect_type(path),
      module: extract_module(path),
      build_system: detect_build_system(Path.dirname(path)),
      dependency: extract_dependency(path),
      location: detect_location(path)
    }
  end
end
```

## State of Project After Implementation

### Improvements
- **Source coverage**: From 60% to 100% of available sources
- **Erlang support**: Full discovery of .erl files
- **Build system support**: Mix, Rebar3, Make, and more
- **Dependency types**: All Mix dependency types supported

### New Capabilities
- Analyze Erlang-only dependencies
- Support umbrella applications fully
- Handle non-standard project layouts
- Discover sources in archives
- Analyze protocol consolidations

### Files Modified
- Created: `lib/litmus/discovery/source_finder.ex`
- Created: `lib/litmus/discovery/source_info.ex`
- Created: `lib/litmus/discovery/build_systems.ex`
- Modified: `lib/litmus/analyzer/project_analyzer.ex`
- Created: `test/discovery/source_finder_test.exs`

### Discovery Statistics
```elixir
# After implementation
{:ok, sources} = SourceFinder.discover_all_sources()

# Example output:
%{
  project: [152 files],
  deps: %{
    elixir: [1843 files],
    erlang: [627 files],
    beam_only: [89 files]
  },
  archives: [23 files],
  total: 2734 files
}
```

## Next Recommended Objective

**Objective 008: Unknown Classification Elimination**

With complete source discovery and caching in place, focus on eliminating the remaining :unknown classifications through improved conservative inference, dynamic dispatch analysis, metaprogramming support, and smarter heuristics. This will reduce unknowns from ~5% to near 0%.