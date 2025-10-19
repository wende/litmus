source = """
defmodule TestDemo do
  def log_and_save(message, path) do
    IO.puts("Saving: \#{message}")
    File.write!(path, message)
    :ok
  end
end
"""

{:ok, ast} = Code.string_to_quoted(source)
IO.puts(inspect(ast, pretty: true, limit: :infinity))
