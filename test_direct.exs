alias Litmus.Inference.{Bidirectional, Context}

# Get the exact body from the demo.ex function
body_ast = quote do
  IO.puts("Saving: #{message}")
  File.write!(path, message)
  :ok
end

# Create context with parameters like analyze_function does
context = Context.empty()
param_type1 = Bidirectional.VarGen.fresh_type_var()
param_type2 = Bidirectional.VarGen.fresh_type_var()

context = context
  |> Context.add(:message, param_type1)
  |> Context.add(:path, param_type2)

# Now synthesize the body
case Bidirectional.synthesize(body_ast, context) do
  {:ok, body_type, body_effect, _subst} ->
    IO.puts("Body type: #{inspect(body_type)}")
    IO.puts("Body effect: #{inspect(body_effect)}")
    labels = Litmus.Types.Core.extract_effect_labels(body_effect)
    IO.puts("Labels: #{inspect(labels)}")
    compact = Litmus.Types.Core.to_compact_effect(body_effect)
    IO.puts("Compact: #{inspect(compact)}")

  {:error, err} ->
    IO.puts("Error: #{inspect(err)}")
end
