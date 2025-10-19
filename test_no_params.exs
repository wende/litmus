alias Litmus.Inference.{Bidirectional, Context}

# Test without parameters in context - use literal strings
body_ast = quote do
  IO.puts("test")
  File.write!("path", "data")
  :ok
end

context = Context.empty()

case Bidirectional.synthesize(body_ast, context) do
  {:ok, body_type, body_effect, _subst} ->
    IO.puts("Body type: #{inspect(body_type)}")
    IO.puts("Body effect: #{inspect(body_effect)}")

  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
