# Analyze the entire Elixir standard library for purity and exceptions
# Similar to what the PURITY paper did for Erlang/OTP

defmodule ElixirStdlibAnalysis do
  def run do
    IO.puts("Analyzing Elixir Standard Library...")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("")

    # Get all loaded Elixir modules
    elixir_modules = get_elixir_stdlib_modules()
    
    IO.puts("Found #{length(elixir_modules)} Elixir stdlib modules")
    IO.puts("")

    # Analyze each module
    {results, errors} = analyze_modules(elixir_modules)
    
    # Generate statistics
    stats = generate_statistics(results)
    exception_stats = generate_exception_statistics(results)
    
    # Print results
    print_purity_statistics(stats)
    IO.puts("")
    print_exception_statistics(exception_stats)
    IO.puts("")
    print_module_summaries(results)
    IO.puts("")
    print_errors(errors)
    
    # Save detailed results
    save_results(results, stats, exception_stats)
  end

  defp get_elixir_stdlib_modules do
    :code.all_loaded()
    |> Enum.map(fn {mod, _} -> mod end)
    |> Enum.filter(fn mod ->
      mod_str = Atom.to_string(mod)
      String.starts_with?(mod_str, "Elixir.") and
        not String.contains?(mod_str, "Test") and
        not String.contains?(mod_str, "Litmus") and
        not String.contains?(mod_str, "Jason") and
        mod != __MODULE__
    end)
    |> Enum.sort()
  end

  defp analyze_modules(modules) do
    IO.puts("Analyzing purity and exceptions for each module...")
    IO.puts("")

    results = Enum.reduce(modules, %{}, fn mod, acc ->
      # Try to analyze each module, catching any errors
      purity_results = try do
        case Litmus.analyze_module(mod) do
          {:ok, res} -> res
          {:error, _} -> %{}
        end
      rescue
        _ -> %{}
      catch
        _ -> %{}
      end

      exception_results = try do
        case Litmus.analyze_exceptions(mod) do
          {:ok, res} -> res
          {:error, _} -> %{}
        end
      rescue
        _ -> %{}
      catch
        _ -> %{}
      end

      if map_size(purity_results) > 0 or map_size(exception_results) > 0 do
        IO.write(".")
      else
        IO.write("x")
      end

      Map.put(acc, mod, %{
        purity: purity_results,
        exceptions: exception_results
      })
    end)

    IO.puts("")
    IO.puts("")

    errors = Enum.filter(results, fn {_, v} ->
      map_size(v.purity) == 0 and map_size(v.exceptions) == 0
    end)

    {results, errors}
  end

  defp generate_statistics(results) do
    all_functions = results
    |> Enum.flat_map(fn {_mod, %{purity: p}} -> Map.to_list(p) end)

    total = length(all_functions)
    
    by_level = all_functions
    |> Enum.group_by(fn {_mfa, level} -> level end)
    |> Enum.map(fn {level, funcs} -> {level, length(funcs)} end)
    |> Map.new()

    %{
      total: total,
      by_level: by_level,
      modules_analyzed: map_size(results)
    }
  end

  defp generate_exception_statistics(results) do
    all_exceptions = results
    |> Enum.flat_map(fn {_mod, %{exceptions: e}} -> Map.to_list(e) end)

    total = length(all_exceptions)
    
    pure_count = all_exceptions
    |> Enum.count(fn {_mfa, info} -> Litmus.Exceptions.pure?(info) end)

    with_errors = all_exceptions
    |> Enum.count(fn {_mfa, info} -> 
      case info.errors do
        :dynamic -> true
        set -> MapSet.size(set) > 0
      end
    end)

    with_throw_exit = all_exceptions
    |> Enum.count(fn {_mfa, info} -> info.non_errors end)

    dynamic_errors = all_exceptions
    |> Enum.count(fn {_mfa, info} -> info.errors == :dynamic end)

    %{
      total: total,
      pure: pure_count,
      with_errors: with_errors,
      with_throw_exit: with_throw_exit,
      dynamic_errors: dynamic_errors
    }
  end

  defp print_purity_statistics(stats) do
    IO.puts("PURITY LEVEL STATISTICS")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Total functions analyzed: #{stats.total}")
    IO.puts("Modules analyzed: #{stats.modules_analyzed}")
    IO.puts("")
    
    levels = [:pure, :exceptions, :dependent, :nif, :side_effects, :unknown]
    
    Enum.each(levels, fn level ->
      count = Map.get(stats.by_level, level, 0)
      percentage = if stats.total > 0, do: count * 100.0 / stats.total, else: 0.0
      IO.puts("  #{level |> to_string() |> String.pad_trailing(15)}: #{String.pad_leading(to_string(count), 6)} (#{:io_lib.format("~5.2f", [percentage])}%)")
    end)
  end

  defp print_exception_statistics(stats) do
    IO.puts("EXCEPTION TRACKING STATISTICS")
    IO.puts("=" |> String.duplicate(80))
    IO.puts("Total functions analyzed: #{stats.total}")
    
    pure_pct = if stats.total > 0, do: stats.pure * 100.0 / stats.total, else: 0.0
    errors_pct = if stats.total > 0, do: stats.with_errors * 100.0 / stats.total, else: 0.0
    throw_pct = if stats.total > 0, do: stats.with_throw_exit * 100.0 / stats.total, else: 0.0
    dynamic_pct = if stats.total > 0, do: stats.dynamic_errors * 100.0 / stats.total, else: 0.0
    
    IO.puts("")
    IO.puts("  Pure (no exceptions)     : #{String.pad_leading(to_string(stats.pure), 6)} (#{:io_lib.format("~5.2f", [pure_pct])}%)")
    IO.puts("  Raises typed errors      : #{String.pad_leading(to_string(stats.with_errors), 6)} (#{:io_lib.format("~5.2f", [errors_pct])}%)")
    IO.puts("  Can throw/exit           : #{String.pad_leading(to_string(stats.with_throw_exit), 6)} (#{:io_lib.format("~5.2f", [throw_pct])}%)")
    IO.puts("  Dynamic exceptions       : #{String.pad_leading(to_string(stats.dynamic_errors), 6)} (#{:io_lib.format("~5.2f", [dynamic_pct])}%)")
  end

  defp print_module_summaries(results) do
    IO.puts("MODULE SUMMARIES (Top 20 by function count)")
    IO.puts("=" |> String.duplicate(80))
    
    summaries = results
    |> Enum.map(fn {mod, %{purity: p, exceptions: e}} ->
      purity_counts = p
      |> Enum.group_by(fn {_mfa, level} -> level end)
      |> Enum.map(fn {level, funcs} -> {level, length(funcs)} end)
      |> Map.new()

      exception_pure = e
      |> Enum.count(fn {_mfa, info} -> Litmus.Exceptions.pure?(info) end)

      {mod, %{
        total: map_size(p),
        purity: purity_counts,
        exception_pure: exception_pure
      }}
    end)
    |> Enum.sort_by(fn {_mod, summary} -> summary.total end, :desc)
    |> Enum.take(20)

    Enum.each(summaries, fn {mod, summary} ->
      pure = Map.get(summary.purity, :pure, 0)
      exceptions = Map.get(summary.purity, :exceptions, 0)
      side_effects = Map.get(summary.purity, :side_effects, 0)
      
      IO.puts("  #{inspect(mod) |> String.pad_trailing(30)}: #{String.pad_leading(to_string(summary.total), 4)} funcs | Pure: #{String.pad_leading(to_string(pure), 3)} | Exc: #{String.pad_leading(to_string(exceptions), 3)} | SE: #{String.pad_leading(to_string(side_effects), 3)} | No-exc: #{summary.exception_pure}")
    end)
  end

  defp print_errors(errors) do
    if length(errors) > 0 do
      IO.puts("MODULES THAT COULDN'T BE ANALYZED")
      IO.puts("=" |> String.duplicate(80))
      Enum.each(errors, fn {mod, _} ->
        IO.puts("  #{inspect(mod)}")
      end)
    end
  end

  defp save_results(results, stats, exception_stats) do
    filename = "elixir_stdlib_analysis.md"

    # Calculate percentages
    pure_pct = if stats.total > 0, do: Map.get(stats.by_level, :pure, 0) * 100.0 / stats.total, else: 0.0
    se_pct = if stats.total > 0, do: Map.get(stats.by_level, :side_effects, 0) * 100.0 / stats.total, else: 0.0
    dep_pct = if stats.total > 0, do: Map.get(stats.by_level, :dependent, 0) * 100.0 / stats.total, else: 0.0
    unk_pct = if stats.total > 0, do: Map.get(stats.by_level, :unknown, 0) * 100.0 / stats.total, else: 0.0

    exc_pure_pct = if exception_stats.total > 0, do: exception_stats.pure * 100.0 / exception_stats.total, else: 0.0
    exc_errors_pct = if exception_stats.total > 0, do: exception_stats.with_errors * 100.0 / exception_stats.total, else: 0.0
    exc_throw_pct = if exception_stats.total > 0, do: exception_stats.with_throw_exit * 100.0 / exception_stats.total, else: 0.0
    exc_dynamic_pct = if exception_stats.total > 0, do: exception_stats.dynamic_errors * 100.0 / exception_stats.total, else: 0.0

    # Generate module details sorted by function count
    module_rows = results
    |> Enum.map(fn {mod, %{purity: p}} ->
      purity_counts = p
      |> Enum.group_by(fn {_mfa, level} -> level end)
      |> Enum.map(fn {level, funcs} -> {level, length(funcs)} end)
      |> Map.new()

      pure = Map.get(purity_counts, :pure, 0)
      side_effects = Map.get(purity_counts, :side_effects, 0)
      dependent = Map.get(purity_counts, :dependent, 0)
      unknown = Map.get(purity_counts, :unknown, 0)
      total = map_size(p)

      "| #{inspect(mod)} | #{total} | #{pure} | #{side_effects} | #{dependent} | #{unknown} |"
    end)
    |> Enum.sort_by(fn line ->
      # Extract total count for sorting
      [_, _, total_str | _] = String.split(line, "|")
      -(String.trim(total_str) |> String.to_integer())
    end)
    |> Enum.join("\n")

    content = """
    # Elixir Standard Library Purity Analysis

    **Generated:** #{DateTime.utc_now() |> DateTime.to_iso8601()}

    ## Purity Statistics

    | Metric | Count | Percentage |
    |--------|-------|------------|
    | **Total functions** | #{:io_lib.format("~B", [stats.total]) |> to_string() |> String.replace(",", ",")} | 100.00% |
    | **Modules analyzed** | #{stats.modules_analyzed} | - |

    ### By Purity Level

    | Purity Level | Functions | Percentage |
    |--------------|-----------|------------|
    | Pure | #{Map.get(stats.by_level, :pure, 0)} | #{:io_lib.format("~.2f", [pure_pct])}% |
    | Side Effects | #{Map.get(stats.by_level, :side_effects, 0)} | #{:io_lib.format("~.2f", [se_pct])}% |
    | Dependent | #{Map.get(stats.by_level, :dependent, 0)} | #{:io_lib.format("~.2f", [dep_pct])}% |
    | Unknown | #{Map.get(stats.by_level, :unknown, 0)} | #{:io_lib.format("~.2f", [unk_pct])}% |

    ## Exception Statistics

    | Exception Type | Functions | Percentage |
    |----------------|-----------|------------|
    | **Total analyzed** | #{exception_stats.total} | 100.00% |
    | Pure (no exceptions) | #{exception_stats.pure} | #{:io_lib.format("~.2f", [exc_pure_pct])}% |
    | Raises typed errors | #{exception_stats.with_errors} | #{:io_lib.format("~.2f", [exc_errors_pct])}% |
    | Can throw/exit | #{exception_stats.with_throw_exit} | #{:io_lib.format("~.2f", [exc_throw_pct])}% |
    | Dynamic exceptions | #{exception_stats.dynamic_errors} | #{:io_lib.format("~.2f", [exc_dynamic_pct])}% |

    ## Module Analysis

    | Module | Functions | Pure | Side Effects | Dependent | Unknown |
    |--------|-----------|------|--------------|-----------|---------|
    #{module_rows}

    ---

    *Analysis performed using [Litmus](https://github.com/wende/litmus) v0.1.0*
    """

    File.write!(filename, content)
    IO.puts("Detailed results saved to #{filename}")
  end
end

# Run the analysis
ElixirStdlibAnalysis.run()
