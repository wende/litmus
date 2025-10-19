alias Litmus.Types.Effects

# Check what effect Kernel.raise/1 has
effect = Effects.from_mfa({Kernel, :raise, 1})
IO.puts("Kernel.raise/1 effect: #{inspect(effect)}")

compact = Litmus.Types.Core.to_compact_effect(effect)
IO.puts("Compact: #{inspect(compact)}")
