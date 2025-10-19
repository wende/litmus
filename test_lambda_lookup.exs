alias Litmus.Types.Effects

# After an analysis run, check what these return
effects = [
  {Enum, :reduce, 3},
  {SampleModule, :higher_order_function, 1}
]

Enum.each(effects, fn mfa = {m, f, a} ->
  effect = Effects.from_mfa(mfa)
  compact = Litmus.Types.Core.to_compact_effect(effect)
  IO.puts("#{m}.#{f}/#{a}: effect=#{inspect(effect)}, compact=#{inspect(compact)}")
end)
