1. Returning many effect types ([{e, [Elixir.ArgumentError]}, {d, [Process.alive?/1]}, {s, [File.write/2]}) should be possible
2. Functions like write! should return both types e and s
3. Exception types should be identified the same way effects are
3. Kernel.raise is a special form that allows us to figure out what error is raised (if not unknown)
4. Try..catch should **remove** exception's from scope
