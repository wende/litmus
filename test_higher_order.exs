# Test to understand how higher-order functions are analyzed

defmodule TestMod do
  def higher_order_function(func) do
    func.(10)
  end

  def another_higher_order(f, g) do
    x = f.(5)
    g.(x)
  end

  def mixed_effects(func) do
    IO.puts("Before")
    result = func.(10)
    IO.puts("After")
    result
  end
end

# Analyze
Mix.Tasks.Effect.run(["test_higher_order.exs"])
