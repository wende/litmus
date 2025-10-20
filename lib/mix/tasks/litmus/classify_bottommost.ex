defmodule Mix.Tasks.Litmus.ClassifyBottommost do
  @moduledoc """
  Classifies bottommost Elixir stdlib functions with heuristic effect types.

  ## Usage

      mix litmus.classify_bottommost

  ## Output

  Creates `.effects/bottommost.json` with all bottommost Elixir functions
  from `.effects/elixir_bottommost.json`, with automatic effect classification.

  Classifications are heuristic and should be reviewed/adjusted in `.effects.explicit.json`.
  """

  use Mix.Task

  @shortdoc "Classify bottommost Elixir stdlib functions"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Classifying bottommost Elixir stdlib functions...")

    bottommost_path = ".effects/elixir_bottommost.json"

    unless File.exists?(bottommost_path) do
      IO.puts("Error: .effects/elixir_bottommost.json not found!")
      IO.puts("Run 'mix litmus.generate_resolutions' first.")
      exit({:shutdown, 1})
    end

    bottommost_data = File.read!(bottommost_path) |> Jason.decode!()

    # Extract all bottommost functions by module
    bottommost_functions =
      bottommost_data
      |> Map.delete("_metadata")
      |> Enum.flat_map(fn {module_name, function_list} ->
        module = parse_module_name(module_name)

        Enum.map(function_list, fn func_arity ->
          {function, arity} = parse_function_arity(func_arity)
          {module, function, arity}
        end)
      end)

    IO.puts("Found #{length(bottommost_functions)} bottommost Elixir functions")

    # Group by module
    by_module = Enum.group_by(bottommost_functions, fn {module, _function, _arity} -> module end)

    # Classify each function
    effects_map =
      by_module
      |> Enum.map(fn {module, module_functions} ->
        functions_map =
          module_functions
          |> Enum.map(fn {_module, function, arity} ->
            effect = classify_function(module, function, arity)
            {"#{function}/#{arity}", effect}
          end)
          |> Map.new()

        module_name = format_module_name(module)
        {module_name, functions_map}
      end)
      |> Map.new()

    # Add metadata
    output =
      %{
        "_metadata" => %{
          "description" =>
            "Bottommost Elixir stdlib functions with heuristic effect classifications",
          "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "total_functions" => length(bottommost_functions),
          "note" => "Review and adjust classifications in .effects.explicit.json"
        }
      }
      |> Map.merge(effects_map)

    # Write to file
    output_path = ".effects/bottommost.json"
    json_content = Jason.encode!(output, pretty: true)
    File.write!(output_path, json_content)

    IO.puts("\n✓ Classified bottommost functions to: #{output_path}")
    IO.puts("  Total modules: #{map_size(by_module)}")
    IO.puts("  Total functions: #{length(bottommost_functions)}")

    # Show statistics
    all_effects = Map.values(effects_map) |> Enum.flat_map(&Map.values/1)

    stats = Enum.frequencies(all_effects)
    IO.puts("\n  Classification summary:")

    Enum.sort_by(stats, fn {_k, v} -> -v end)
    |> Enum.each(fn {effect, count} ->
      IO.puts("    #{effect}: #{count}")
    end)

    IO.puts("\n⚠  Next steps:")
    IO.puts("  1. Review #{output_path} and move corrections to .effects.explicit.json")
    IO.puts("  2. Run 'mix litmus.merge_explicit' to generate final registry")
    IO.puts("  3. Run tests to verify")
  end

  # Parse module name from string (handles "Elixir.ModuleName" format)
  defp parse_module_name("Elixir." <> rest), do: Module.concat([rest])
  defp parse_module_name(name), do: String.to_atom(name)

  # Parse "function/arity" into {function, arity}
  # Handles operators like "//2" by finding the LAST "/" to get arity
  defp parse_function_arity(func_arity_str) do
    case String.reverse(func_arity_str) |> String.split("/", parts: 2) do
      [reversed_arity, reversed_name] ->
        function_str = String.reverse(reversed_name)
        arity_str = String.reverse(reversed_arity)
        {String.to_atom(function_str), String.to_integer(arity_str)}
    end
  end

  # Format module name for JSON output
  defp format_module_name(module) when is_atom(module) do
    Atom.to_string(module)
  end

  # Classify an Elixir stdlib function based on heuristics
  defp classify_function(module, function, _arity) do
    module_str = Atom.to_string(module)
    function_str = Atom.to_string(function)

    cond do
      # File module - side effects
      module_str == "Elixir.File" ->
        cond do
          function_str in [
            "read",
            "write",
            "read!",
            "write!",
            "open",
            "close",
            "rm",
            "rm_rf",
            "mkdir",
            "mkdir_p",
            "exists?",
            "dir?",
            "regular?",
            "stat",
            "stat!",
            "ls",
            "ls!",
            "cd",
            "cd!",
            "cwd",
            "cwd!"
          ] ->
            "s"

          true ->
            "u"
        end

      # IO module - side effects
      module_str == "Elixir.IO" ->
        "s"

      # String module - mostly pure
      module_str == "Elixir.String" ->
        "p"

      # Enum module - lambda-dependent for map/filter/etc
      module_str == "Elixir.Enum" ->
        cond do
          function_str in [
            "map",
            "filter",
            "reduce",
            "flat_map",
            "reject",
            "each",
            "find",
            "all?",
            "any?",
            "sort_by",
            "group_by",
            "uniq_by"
          ] ->
            "l"

          # Functions like count, reverse, etc are pure
          true ->
            "p"
        end

      # Stream module - lambda-dependent
      module_str == "Elixir.Stream" ->
        "l"

      # List/Tuple/Map - pure
      module_str in [
        "Elixir.List",
        "Elixir.Tuple",
        "Elixir.Map",
        "Elixir.MapSet",
        "Elixir.Keyword"
      ] ->
        "p"

      # Process module - side effects and dependent
      module_str == "Elixir.Process" ->
        cond do
          function_str in ["get", "get_keys", "info", "list", "alive?", "whereis"] -> "d"
          # put, send, spawn, etc
          true -> "s"
        end

      # System module - dependent and side effects
      module_str == "Elixir.System" ->
        cond do
          function_str in [
            "system_time",
            "monotonic_time",
            "unique_integer",
            "os_time",
            "get_env",
            "fetch_env",
            "fetch_env!"
          ] ->
            "d"

          # cmd, halt, etc
          true ->
            "s"
        end

      # Task/Agent/GenServer - side effects
      module_str in ["Elixir.Task", "Elixir.Agent", "Elixir.GenServer"] ->
        "s"

      # Port - side effects
      module_str == "Elixir.Port" ->
        "s"

      # Application/Code/Module - side effects
      module_str in ["Elixir.Application", "Elixir.Code", "Elixir.Module"] ->
        "s"

      # Regex - pure (compiled regexes are memoized, effectively pure)
      module_str == "Elixir.Regex" ->
        "p"

      # URI/Path - pure
      module_str in ["Elixir.URI", "Elixir.Path"] ->
        "p"

      # Date/Time/Calendar - mostly pure (creating dates/times)
      module_str in [
        "Elixir.Date",
        "Elixir.Time",
        "Elixir.DateTime",
        "Elixir.NaiveDateTime",
        "Elixir.Calendar"
      ] ->
        cond do
          # Reading system time
          function_str in ["utc_now", "now"] -> "d"
          true -> "p"
        end

      # Kernel - various
      module_str == "Elixir.Kernel" ->
        cond do
          # Exception-raising functions
          function_str in ["raise", "reraise", "exit", "throw"] -> "e"
          # Side effects
          function_str in ["send", "spawn", "spawn_link", "spawn_monitor"] -> "s"
          # Dependent
          function_str in ["self", "node", "make_ref"] -> "d"
          # Lambda-dependent
          function_str in ["apply"] -> "l"
          # Pure (most operators, type checks, etc)
          true -> "p"
        end

      # Range - pure
      module_str == "Elixir.Range" ->
        "p"

      # StringIO - side effects (mutable buffer)
      module_str == "Elixir.StringIO" ->
        "s"

      # Exception - pure (just data structures)
      module_str == "Elixir.Exception" ->
        "p"

      # Default: mark as unknown - needs manual review
      true ->
        "u"
    end
  end
end
