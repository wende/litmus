alias Litmus.Inference.{Bidirectional, Context}

# Test synthesizing ArgumentError
ast = {:__aliases__, [alias: false], [:ArgumentError]}

context = Context.empty()

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
