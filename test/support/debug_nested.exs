defmodule Support.EdgeCasesTest do
  def nested_with_effects_at_all_levels(data) do
    IO.puts("Starting processing")

    result =
      Enum.map(data, fn item ->
        IO.puts("Processing item: #{inspect(item)}")

        Enum.filter(item, fn x ->
          File.write!("debug.log", "Checking: #{x}\n", [:append])
          x > 0
        end)
      end)

    IO.puts("Done processing")
    result
  end
end
