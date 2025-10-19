alias Litmus.Inference.{Bidirectional, Context}

context = Context.empty()

# Test just two expressions
ast = quote do
  IO.puts("test")
  :ok
end

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
    labels = Litmus.Types.Core.extract_effect_labels(effect)
    IO.puts("Labels: #{inspect(labels)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
