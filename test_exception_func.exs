alias Litmus.Inference.{Bidirectional, Context}
alias Litmus.Types.Core

# Analyze the exception/0 function
ast = quote do
  raise ArgumentError
end

context = Context.empty()

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
    labels = Core.extract_effect_labels(effect)
    IO.puts("Labels: #{inspect(labels)}")
    compact = Core.to_compact_effect(effect)
    IO.puts("Compact: #{inspect(compact)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
