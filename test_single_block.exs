alias Litmus.Inference.{Bidirectional, Context}

# Block with just one expression
ast = quote do
  File.write!("path", "data")
end

context = Context.empty()

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
