alias Litmus.Inference.{Bidirectional, Context}

context = Context.empty()

# Test each expression individually
exprs = [
  quote(do: IO.puts("test")),
  quote(do: File.write!("path", "data")),
  quote(do: :ok)
]

IO.puts("Individual expressions:")
Enum.with_index(exprs, 1) |> Enum.each(fn {expr, idx} ->
  case Bidirectional.synthesize(expr, context) do
    {:ok, type, effect, _} ->
      IO.puts("#{idx}. Type: #{inspect(type)}, Effect: #{inspect(effect)}")
    {:error, err} ->
      IO.puts("#{idx}. Error: #{inspect(err)}")
  end
end)

# Now test the full block
IO.puts("\nFull block:")
ast = quote do
  IO.puts("test")
  File.write!("path", "data")
  :ok
end

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Type: #{inspect(type)}")
    IO.puts("Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
