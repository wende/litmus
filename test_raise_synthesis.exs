alias Litmus.Inference.{Bidirectional, Context}

# Test synthesizing just "raise ArgumentError" 
ast = {:raise, [context: Elixir], [{:__aliases__, [alias: false], [:ArgumentError]}]}

context = Context.empty()

IO.puts("Synthesizing: #{inspect(ast)}")

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Success!")
    IO.puts("  Type: #{inspect(type)}")
    IO.puts("  Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
