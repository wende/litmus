defmodule Mix.Tasks.Litmus.GenerateResolutions do
  @moduledoc """
  Generates resolution mapping from Elixir stdlib functions to bottommost Elixir functions.

  This task should be run manually when the Elixir version changes.
  It traces through Elixir stdlib to find bottommost functions (those that only call Erlang).

  ## Usage

      mix litmus.generate_resolutions

  ## Outputs

  1. `.effects/resolution.json` - Elixir→Elixir wrapper resolutions (e.g., read!/1 → read/1)
  2. `.effects/elixir_bottommost.json` - List of bottommost Elixir functions

  Example resolution.json:

      {
        "Elixir.File": {
          "read!/1": ["File.read/1"],    # Wrapper
          "write!/2": ["File.write/2"]   # Wrapper
        }
      }

  Example elixir_bottommost.json:

      {
        "Elixir.File": ["read/1", "write/2"],      # Bottommost - only call Erlang
        "Elixir.String": ["upcase/1", "trim/1"]    # Bottommost - only call Erlang
      }

  ## Philosophy

  - Bottommost Elixir = functions that only call Erlang/BEAM, no more Elixir
  - Resolution mapping = Elixir → Elixir (e.g., bang variants → regular functions)
  - Effect registry = bottommost Elixir functions only
  """

  use Mix.Task
  alias Litmus.Analyzer.CallGraphTracer

  @shortdoc "Generate Elixir stdlib resolution mappings and bottommost functions"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    IO.puts("Generating Elixir stdlib resolution mappings...")
    IO.puts("This may take a few minutes...\n")

    # Get list of Elixir stdlib modules to trace (seed list)
    seed_modules = get_elixir_stdlib_modules()

    IO.puts("Starting with #{length(seed_modules)} seed modules...")
    IO.puts("Will recursively discover all referenced Elixir modules...\n")

    # Recursively discover and trace all Elixir modules
    {resolution_map, bottommost_functions, stats} = trace_recursive(seed_modules)

    # Export resolution mapping (Elixir → Elixir wrappers only)
    resolution_path = ".effects/resolution.json"
    export_resolution_to_json(resolution_map, stats, resolution_path)

    # Export bottommost Elixir functions
    bottommost_path = ".effects/elixir_bottommost.json"
    export_bottommost_to_json(bottommost_functions, bottommost_path)

    IO.puts("\n✓ Resolution mapping generated: #{resolution_path}")
    IO.puts("  Wrapper functions (Elixir→Elixir): #{stats.wrapper_functions}")
    IO.puts("\n✓ Bottommost functions generated: #{bottommost_path}")
    IO.puts("  Total bottommost Elixir functions: #{stats.bottommost_functions}")
    IO.puts("  Total modules traced: #{stats.modules_traced}")
    IO.puts("  Total functions traced: #{stats.total_functions}")
  end

  @doc """
  Get list of Elixir standard library modules to trace.

  Returns commonly used modules that wrap Erlang functionality.
  """
  def get_elixir_stdlib_modules do
    [
      # Core data structures
      Enum,
      Stream,
      List,
      Tuple,
      Map,
      MapSet,
      Keyword,
      Range,

      # Strings and binaries
      String,
      IO,
      StringIO,

      # File system and I/O
      File,
      Path,
      IO.ANSI,

      # System and OS
      System,
      Port,

      # Process and concurrency
      Process,
      Task,
      Agent,
      GenServer,

      # Exceptions and errors
      Exception,
      Kernel,

      # Application and code
      Application,
      Code,
      Module,

      # Other utilities
      Regex,
      URI,
      Calendar,
      Date,
      Time,
      DateTime,
      NaiveDateTime
    ]
  end

  @doc """
  Recursively discover and trace all Elixir modules.

  Starts with seed modules and traces them. Collects all Elixir modules
  that are referenced in their call graphs. Traces those modules too.
  Repeats until no new modules are discovered.

  Returns `{resolution_map, bottommost_functions, stats}`.
  """
  def trace_recursive(seed_modules) do
    traced = MapSet.new()
    to_trace = MapSet.new(seed_modules)
    resolution_map = %{}
    bottommost_set = MapSet.new()
    stats = %{total: 0, wrapper: 0, bottommost: 0, modules_traced: 0}

    do_trace_recursive(to_trace, traced, resolution_map, bottommost_set, stats)
  end

  defp do_trace_recursive(to_trace, traced, resolution_map, bottommost_set, stats) do
    if MapSet.size(to_trace) == 0 do
      # Done - no more modules to trace
      formatted_stats = %{
        total_functions: stats.total,
        wrapper_functions: stats.wrapper,
        bottommost_functions: stats.bottommost,
        modules_traced: stats.modules_traced
      }

      bottommost_list = MapSet.to_list(bottommost_set)
      {resolution_map, bottommost_list, formatted_stats}
    else
      # Pick a module to trace
      module = Enum.at(to_trace, 0)
      to_trace = MapSet.delete(to_trace, module)
      traced = MapSet.put(traced, module)

      # Trace this module
      case get_module_exports(module) do
        {:ok, exports} ->
          IO.write("#{inspect(module)}")
          # Force flush
          :io.put_chars(:standard_error, "")

          {module_resolutions, module_bottommost, module_stats, discovered_modules} =
            exports
            |> Enum.reduce(
              {%{}, MapSet.new(), %{total: 0, wrapper: 0, bottommost: 0}, MapSet.new()},
              fn {function, arity}, {fn_acc, bottom_acc, fn_stats, disc_acc} ->
                mfa = {module, function, arity}
                fn_stats = %{fn_stats | total: fn_stats.total + 1}

                # Get the calls this function makes
                case CallGraphTracer.get_function_calls(module, function, arity) do
                  {:ok, calls} when is_list(calls) ->
                    # Separate Elixir calls from Erlang calls
                    elixir_calls =
                      Enum.filter(calls, fn {mod, _f, _a} -> is_elixir_module?(mod) end)

                    # Collect newly discovered modules
                    new_modules =
                      elixir_calls
                      |> Enum.map(fn {mod, _f, _a} -> mod end)
                      |> Enum.reject(fn mod ->
                        MapSet.member?(traced, mod) or MapSet.member?(to_trace, mod)
                      end)
                      |> MapSet.new()

                    disc_acc = MapSet.union(disc_acc, new_modules)

                    cond do
                      # No calls at all - it's bottommost (pure or unknown)
                      calls == [] ->
                        {fn_acc, MapSet.put(bottom_acc, mfa),
                         %{fn_stats | bottommost: fn_stats.bottommost + 1}, disc_acc}

                      # Only calls Erlang - it's bottommost
                      elixir_calls == [] ->
                        {fn_acc, MapSet.put(bottom_acc, mfa),
                         %{fn_stats | bottommost: fn_stats.bottommost + 1}, disc_acc}

                      # Calls other Elixir functions - it's a wrapper, create resolution
                      true ->
                        {Map.put(fn_acc, mfa, elixir_calls), bottom_acc,
                         %{fn_stats | wrapper: fn_stats.wrapper + 1}, disc_acc}
                    end

                  {:error, _reason} ->
                    # Can't analyze - treat as bottommost
                    {fn_acc, MapSet.put(bottom_acc, mfa),
                     %{fn_stats | bottommost: fn_stats.bottommost + 1}, disc_acc}
                end
              end
            )

          new_stats = %{
            total: stats.total + module_stats.total,
            wrapper: stats.wrapper + module_stats.wrapper,
            bottommost: stats.bottommost + module_stats.bottommost,
            modules_traced: stats.modules_traced + 1
          }

          # Print module progress
          new_count = MapSet.size(discovered_modules)

          IO.puts(
            " [#{module_stats.bottommost} bottommost, #{module_stats.wrapper} wrappers, +#{new_count} new modules]"
          )

          # Add discovered modules to trace queue
          to_trace = MapSet.union(to_trace, discovered_modules)

          # Merge results and continue
          resolution_map = Map.merge(resolution_map, module_resolutions)
          bottommost_set = MapSet.union(bottommost_set, module_bottommost)

          do_trace_recursive(to_trace, traced, resolution_map, bottommost_set, new_stats)

        {:error, _reason} ->
          IO.puts(" [error]")
          do_trace_recursive(to_trace, traced, resolution_map, bottommost_set, stats)
      end
    end
  end

  @doc """
  Get exported functions from a module.

  Returns `{:ok, [{function, arity}, ...]}` or `{:error, reason}`.
  """
  def get_module_exports(module) do
    try do
      # Get module info
      exports = module.__info__(:functions)
      {:ok, exports}
    rescue
      _ -> {:error, :not_available}
    end
  end

  @doc """
  Export resolution mapping to JSON file (Elixir → Elixir wrappers only).
  """
  def export_resolution_to_json(resolution_map, stats, output_path) do
    # Group by module
    grouped = Enum.group_by(resolution_map, fn {{module, _f, _a}, _calls} -> module end)

    # Convert to JSON-friendly structure
    json_map =
      grouped
      |> Enum.map(fn {module, entries} ->
        module_name = format_module_name(module)

        functions_map =
          entries
          |> Enum.map(fn {{_mod, function, arity}, calls} ->
            function_key = "#{function}/#{arity}"
            call_strings = Enum.map(calls, fn {m, f, a} -> format_mfa(m, f, a) end)
            {function_key, call_strings}
          end)
          |> Map.new()

        {module_name, functions_map}
      end)
      |> Map.new()

    # Add metadata
    output =
      %{
        "_metadata" => %{
          "description" => "Elixir wrapper function resolutions (e.g., read!/1 → read/1)",
          "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "elixir_version" => System.version(),
          "otp_release" => :erlang.system_info(:otp_release) |> List.to_string(),
          "total_functions_traced" => stats.total_functions,
          "wrapper_functions" => stats.wrapper_functions,
          "bottommost_functions" => stats.bottommost_functions,
          "note" =>
            "Only Elixir→Elixir mappings. Bottommost functions are in elixir_bottommost.json"
        }
      }
      |> Map.merge(json_map)

    # Write to file
    json_content = Jason.encode!(output, pretty: true)
    File.write!(output_path, json_content)
  end

  @doc """
  Export bottommost Elixir functions to JSON file.
  """
  def export_bottommost_to_json(bottommost_list, output_path) do
    # Group by module
    grouped =
      bottommost_list
      |> Enum.group_by(fn {module, _f, _a} -> module end)

    # Convert to JSON-friendly structure
    json_map =
      grouped
      |> Enum.map(fn {module, mfas} ->
        module_name = format_module_name(module)

        function_list =
          mfas
          |> Enum.map(fn {_mod, function, arity} -> "#{function}/#{arity}" end)
          |> Enum.sort()

        {module_name, function_list}
      end)
      |> Map.new()

    # Add metadata
    output =
      %{
        "_metadata" => %{
          "description" => "Bottommost Elixir stdlib functions (only call Erlang/BEAM)",
          "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "elixir_version" => System.version(),
          "otp_release" => :erlang.system_info(:otp_release) |> List.to_string(),
          "total_bottommost" => length(bottommost_list),
          "note" =>
            "These functions should be in the effect registry with explicit classifications"
        }
      }
      |> Map.merge(json_map)

    # Write to file
    json_content = Jason.encode!(output, pretty: true)
    File.write!(output_path, json_content)
  end

  # Helper to check if module is Elixir
  defp is_elixir_module?(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.")
  end

  # Helper to format module name for JSON
  defp format_module_name(module) when is_atom(module) do
    module |> Atom.to_string()
  end

  # Helper to format MFA as string
  defp format_mfa(module, function, arity) do
    module_str = if is_atom(module), do: Atom.to_string(module), else: to_string(module)
    # Remove "Elixir." prefix if present
    module_str = String.replace(module_str, "Elixir.", "")
    "#{module_str}.#{function}/#{arity}"
  end
end
