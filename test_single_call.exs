alias Litmus.Inference.{Bidirectional, Context}

# Just File.write!
ast = quote(do: File.write!("path", "data"))

context = Context.empty()

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
