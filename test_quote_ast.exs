ast = quote do
  IO.puts("test")
  :ok
end

IO.puts(inspect(ast, pretty: true))
