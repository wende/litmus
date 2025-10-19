# Add debugging to trace effect synthesis

defmodule DebugInference do
  alias Litmus.Inference.Bidirectional
  alias Litmus.Inference.Context
  alias Litmus.Types.Core
  
  def test do
    # Simple block with two side effects  
    ast = quote do
      IO.puts("test")
      File.write!("path", "data")
      :ok
    end
    
    context = Context.empty()
    
    case Bidirectional.synthesize(ast, context) do
      {:ok, type, effect, _subst} ->
        IO.puts("Type: #{inspect(type)}")
        IO.puts("Effect: #{inspect(effect, pretty: true)}")
        IO.puts("Labels: #{inspect(Core.extract_effect_labels(effect))}")
        compact = Core.to_compact_effect(effect)
        IO.puts("Compact: #{inspect(compact)}")
        
      {:error, err} ->
        IO.puts("Error: #{inspect(err)}")
    end
  end
end

DebugInference.test()
