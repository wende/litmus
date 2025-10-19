alias Litmus.Inference.{Bidirectional, Context}

context = Context.empty()

# Test File.write!
ast = quote(do: File.write!("path", "data"))

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end

# Also test with variables
param_type1 = Litmus.Inference.Bidirectional.VarGen.fresh_type_var()
param_type2 = Litmus.Inference.Bidirectional.VarGen.fresh_type_var()
context2 = context 
  |> Context.add(:path, param_type1)
  |> Context.add(:message, param_type2)

ast2 = quote(do: File.write!(path, message))

IO.puts("\nWith variables:")
case Bidirectional.synthesize(ast2, context2) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
