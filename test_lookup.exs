alias Litmus.Types.Effects

# Test lookup after analysis
effect = Effects.from_mfa({SampleModule, :pure_add, 2})
IO.puts("SampleModule.pure_add/2: #{inspect(effect)}")

# Check if it's pure
is_pure = Effects.is_pure?(effect)
IO.puts("is_pure?: #{inspect(is_pure)}")

compact = Litmus.Types.Core.to_compact_effect(effect)
IO.puts("compact: #{inspect(compact)}")
