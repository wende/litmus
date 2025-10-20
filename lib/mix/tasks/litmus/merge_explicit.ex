defmodule Mix.Tasks.Litmus.MergeExplicit do
  @moduledoc """
  Merges auto-generated BIFs with explicit manual classifications.

  ## Usage

      mix litmus.merge_explicit

  ## Workflow

  1. Reads `.effects.bifs.json` (auto-generated with unknowns)
  2. Reads `.effects/explicit.json` (manual classifications)
  3. Merges them (explicit overrides unknowns)
  4. Outputs to `.effects/std.json`

  ## Philosophy

  - `.effects.bifs.json` = Auto-extracted BIFs with heuristic classification
  - `.effects/explicit.json` = Human-reviewed classifications (version-controlled)
  - `.effects/std.json` = Final complete stdlib registry (no unknowns)
  """

  use Mix.Task

  @shortdoc "Merge auto-generated BIFs with explicit classifications"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Merging .effects/bottommost.json with .effects.explicit.json...")

    bottommost_path = ".effects/bottommost.json"
    explicit_path = ".effects.explicit.json"
    output_path = ".effects/std.json"

    # Verify input files exist
    unless File.exists?(bottommost_path) do
      IO.puts("Error: #{bottommost_path} not found!")
      IO.puts("Run 'mix litmus.classify_bottommost' first.")
      exit({:shutdown, 1})
    end

    unless File.exists?(explicit_path) do
      IO.puts("Error: #{explicit_path} not found!")
      IO.puts("Create this file with manual classifications for unknown BIFs.")
      exit({:shutdown, 1})
    end

    # Load both files
    bottommost_data = File.read!(bottommost_path) |> Jason.decode!()
    explicit_data = File.read!(explicit_path) |> Jason.decode!()

    # Extract metadata
    bottommost_metadata = Map.get(bottommost_data, "_metadata", %{})
    explicit_metadata = Map.get(explicit_data, "_metadata", %{})

    # Remove metadata for merging
    bottommost_modules = Map.delete(bottommost_data, "_metadata")
    explicit_modules = Map.delete(explicit_data, "_metadata")

    # Merge: explicit overrides bottommost
    merged = deep_merge(bottommost_modules, explicit_modules)

    # Count statistics
    stats = count_effects(merged)

    total_functions =
      Enum.reduce(merged, 0, fn {_module, functions}, acc ->
        acc + map_size(functions)
      end)

    # Create output with new metadata
    output =
      %{
        "_metadata" => %{
          "description" => "Complete Elixir stdlib bottommost function registry",
          "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "source_bottommost" => bottommost_path,
          "source_explicit" => explicit_path,
          "total_modules" => map_size(merged),
          "total_functions" => total_functions,
          "bottommost_generated_at" => Map.get(bottommost_metadata, "generated_at"),
          "explicit_reviewed_at" => Map.get(explicit_metadata, "generated_at"),
          "note" =>
            "This file is auto-generated. Do not edit manually. Update .effects.explicit.json instead."
        }
      }
      |> Map.merge(merged)

    # Write to output
    json_content = Jason.encode!(output, pretty: true)
    File.write!(output_path, json_content)

    IO.puts("\n✓ Merged stdlib registry: #{output_path}")
    IO.puts("  Total modules: #{map_size(merged)}")
    IO.puts("  Total functions: #{total_functions}")
    IO.puts("\n  Effect distribution:")

    Enum.sort_by(stats, fn {_k, v} -> -v end)
    |> Enum.each(fn {effect, count} ->
      IO.puts("    #{effect}: #{count}")
    end)

    # Check for remaining unknowns
    unknowns = stats["u"] || 0

    if unknowns > 0 do
      IO.puts("\n⚠  Warning: #{unknowns} functions still marked as unknown")
      IO.puts("  Review these and add to .effects/explicit.json")
    else
      IO.puts("\n✓ No unknowns remaining!")
    end
  end

  # Deep merge two maps (explicit overrides bifs)
  defp deep_merge(bifs, explicit) do
    Map.merge(bifs, explicit, fn _module, bifs_functions, explicit_functions ->
      Map.merge(bifs_functions, explicit_functions)
    end)
  end

  # Count effect types
  defp count_effects(modules) do
    modules
    |> Enum.flat_map(fn {_module, functions} -> Map.values(functions) end)
    |> Enum.map(&normalize_effect/1)
    |> Enum.frequencies()
  end

  # Normalize effect for counting
  defp normalize_effect(%{"e" => _}), do: "e"
  defp normalize_effect(%{"s" => _}), do: "s"
  defp normalize_effect(%{"d" => _}), do: "d"
  defp normalize_effect(effect) when is_binary(effect), do: effect
end
