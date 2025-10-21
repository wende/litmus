defmodule Support.DebugFilter do
  def simple_filter do
    Enum.filter([1, 2], fn x ->
      File.write!("debug.log", "test")
      x > 0
    end)
  end
end
