# Exclude BEAM analysis tests when coverage is enabled
# These tests require reading clean BEAM files which are modified by Cover
exclude_tags =
  if Code.ensure_loaded?(:cover) and function_exported?(:cover, :modules, 0) do
    # Check if any modules are being cover-compiled
    case :cover.modules() do
      [] -> [:spike]
      _ -> [:spike, beam_analysis: true]
    end
  else
    [:spike]
  end

ExUnit.start(exclude: exclude_tags)
