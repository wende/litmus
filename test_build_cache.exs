# Check what format build_effect_cache produces
alias Litmus.Inference.{Bidirectional, Context}
alias Litmus.Types.Core

# Simulate analyzing SampleModule.get_first/1
source = """
defmodule TestModule do
  def test_func(list) do
    hd(list)
  end
end
"""

{:ok, ast} = Code.string_to_quoted(source)
{:ok, result} = Litmus.Analyzer.ASTWalker.analyze_ast(ast)

# Get the effect for test_func
{_mfa, func_analysis} = Enum.find(result.functions, fn {{_m, f, _a}, _} -> f == :test_func end)

compact = Core.to_compact_effect(func_analysis.effect)
IO.puts("Compact effect: #{inspect(compact)}")
IO.puts("Type: #{inspect(compact |> (&is_tuple(&1) or is_atom(&1)).())}")
