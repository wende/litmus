# Simple test to see what effect is produced
alias Litmus.Analyzer.ASTWalker

source = """
defmodule TestDemo do
  def log_and_save(message, path) do
    IO.puts("Saving: \#{message}")
    File.write!(path, message)
    :ok
  end
end
"""

{:ok, ast} = Code.string_to_quoted(source)
{:ok, result} = ASTWalker.analyze_ast(ast)

# Print the analysis for log_and_save/2
{_mfa, analysis} = Enum.find(result.functions, fn {{_m, f, a}, _} -> f == :log_and_save and a == 2 end)

IO.puts("Effect: #{inspect(analysis.effect, pretty: true)}")
IO.puts("Calls: #{inspect(analysis.calls)}")

# Check what the effect converts to
compact = Litmus.Types.Core.to_compact_effect(analysis.effect)
IO.puts("Compact: #{inspect(compact)}")
