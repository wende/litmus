alias Litmus.Inference.{Bidirectional, Context}

context = Context.empty()

# Test synthesizing :ok
ast = :ok

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
