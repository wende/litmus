defmodule SampleModule do
  @moduledoc """
  Sample module demonstrating various effects for analysis.
  """

  # Pure functions
  def pure_add(x, y) do
    x + y
  end

  def pure_multiply(x, y) do
    x * y
  end

  defp pure_helper(list) do
    Enum.map(list, fn x -> x * 2 end)
  end

  # IO effects
  def print_greeting(name) do
    IO.puts("Hello, #{name}!")
  end

  def log_message(level, message) do
    IO.puts("[#{level}] #{message}")
  end

  # File effects
  def read_config(path) do
    File.read!(path)
  end

  def save_data(path, data) do
    File.write!(path, data)
  end

  # Mixed effects
  def process_file(input_path, output_path) do
    # File effect
    content = File.read!(input_path)

    # IO effect
    IO.puts("Processing #{byte_size(content)} bytes...")

    # Pure computation
    processed = String.upcase(content)

    # File effect
    File.write!(output_path, processed)

    # IO effect
    IO.puts("Done!")

    :ok
  end

  # Process effects
  def spawn_worker(task) do
    spawn(fn -> execute_task(task) end)
  end

  def send_message(pid, message) do
    send(pid, message)
    :ok
  end

  # Exception effects
  def get_first(list) do
    hd(list)  # Can raise ArgumentError
  end

  def divide(x, y) do
    div(x, y)  # Can raise ArithmeticError
  end

  # Complex control flow
  def conditional_effect(flag, message) do
    if flag do
      IO.puts(message)
    else
      :ok
    end
  end

  def pattern_match_effect(value) do
    case value do
      {:ok, data} ->
        File.write!("output.txt", data)
        :success

      {:error, _reason} ->
        IO.puts("Error occurred")
        :failure

      _ ->
        :unknown
    end
  end

  # Private helper
  defp execute_task(task) do
    IO.puts("Executing: #{inspect(task)}")
    :ok
  end

  # Network effect (if we had network operations)
  # def fetch_data(url) do
  #   HTTPoison.get!(url)
  # end

  # ETS effect
  def store_in_cache(key, value) do
    :ets.insert(:cache, {key, value})
  end

  # Time effect
  def get_timestamp do
    System.system_time(:second)
  end

  # State effect
  def update_counter do
    Agent.update(:counter, fn count -> count + 1 end)
  end

  # Higher-order function
  def higher_order_function(func) do
    func.(10)
  end

end
