# Test if raise/1 is found in registry
effect_type = Litmus.Effects.Registry.effect_type({Kernel, :raise, 1})
IO.puts("Effect type: #{inspect(effect_type)}")

# Test the is_kernel check
is_kernel = try do
  effect = Litmus.Effects.Registry.effect_type({Kernel, :raise, 1})
  effect != nil
rescue
  e ->
    IO.puts("Error: #{inspect(e)}")
    false
end

IO.puts("is_kernel: #{inspect(is_kernel)}")
