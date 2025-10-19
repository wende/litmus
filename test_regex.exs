# Test if our regex patterns match the file paths
patterns = ["test/support/", "lib/mix/tasks/"]
files = [
  "test/support/demo.ex",
  "lib/mix/tasks/effect.ex",
  "lib/litmus.ex"
]

for pattern <- patterns do
  regex = Regex.compile!(pattern)
  IO.puts("\nPattern: #{pattern}")
  for file <- files do
    match = Regex.match?(regex, file)
    IO.puts("  #{file}: #{match}")
  end
end
