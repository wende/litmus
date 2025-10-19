defmodule Support.Demo do
  @moduledoc "Demo module showing pure and effectful functions"

  # Pure mathematical functions
  def add(x, y), do: x + y

  # List processing (pure)
  def sum_list(list) do
    Enum.reduce(list, 0, &+/2)
  end

  # String processing (pure)
  def uppercase(str) do
    String.upcase(str)
  end

  # IO effects
  def greet(name) do
    IO.puts("Hello, #{name}!")
  end
  
  # Unknown
  def unknown() do
    apply(IO, :puts)  
  end

  # Process effects
  def spawn_task(fun) do
    spawn(fun)
  end

  # Exception effects
  def head_of_list(list) do
    hd(list)
  end
  
  def exception() do
    raise ArgumentError
  end

  # Mixed effects
  def log_and_save(message, path) do
    IO.puts("Saving: #{message}")
    File.write!(path, message)
    :ok
  end

  # Pure function from other module
  def other_module_pure() do
    Support.SampleModule.pure_add(1, 2)
  end

  # Effectful function from other module
  def other_module_effectful() do
    Support.SampleModule.print_greeting("John")
  end

  # Exception from other module
  def other_module_exception() do
    Support.SampleModule.get_first([1, 2, 3])
  end

  def other_module_higher_order_pure() do
    Support.SampleModule.higher_order_function(fn x -> x * 2 end)
  end

  def other_module_higher_order_effectful() do
    Support.SampleModule.higher_order_function(fn x -> IO.puts("Hello, #{x}!") end)
  end
end
