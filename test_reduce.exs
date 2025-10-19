alias Litmus.Types.Effects

# Test how reduce works with effects
e1 = {:effect_label, :io}
e2 = {:effect_label, :file}
e_var = {:effect_var, :e0}

# Test 1: reduce with empty
result1 = Enum.reduce([e1, e2], {:effect_empty}, &Effects.combine_effects/2)
IO.puts("With empty: #{inspect(result1)}")

# Test 2: reduce with variable
result2 = Enum.reduce([e1, e2], e_var, &Effects.combine_effects/2)
IO.puts("With var: #{inspect(result2)}")
