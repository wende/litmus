# Test: What effect is cached for higher_order_function?

Mix.Task.run("compile")

# Build effect cache
app_files = Mix.Tasks.Effect.discover_app_files()
IO.puts("Found #{length(app_files)} files")

cache = Mix.Tasks.Effect.build_effect_cache(app_files)

mfa = {SampleModule, :higher_order_function, 1}
effect = Map.get(cache, mfa, :not_found)

IO.puts("\nEffect for #{inspect(mfa)}: #{inspect(effect)}")
IO.puts("Is it :l? #{effect == :l}")
