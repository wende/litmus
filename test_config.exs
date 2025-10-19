# Test if ExCoveralls reads our skip_files config
Application.put_env(:excoveralls, :config_file, "#{File.cwd!}/coveralls.json")
skip_files = ExCoveralls.Settings.get_skip_files()
IO.puts("Skip files regexes:")
for regex <- skip_files do
  IO.inspect(regex, label: "Regex")
end
