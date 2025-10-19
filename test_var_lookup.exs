# Test if variables are in context

alias Litmus.Inference.{Bidirectional, Context}
alias Litmus.Inference.Bidirectional.VarGen

# Create context with parameters
context = Context.empty()
param_type = VarGen.fresh_type_var()
context = Context.add(context, :message, param_type)

# Try to look up the variable
IO.puts("Looking up :message")
result = Context.lookup(context, :message)
IO.puts("Result: #{inspect(result)}")

# Now try analyzing a simple expression using message
ast = quote do: message

case Bidirectional.synthesize(ast, context) do
  {:ok, type, effect, _} ->
    IO.puts("Variable synthesis:")
    IO.puts("  Type: #{inspect(type)}")
    IO.puts("  Effect: #{inspect(effect)}")
  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
