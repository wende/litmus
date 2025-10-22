defmodule Test.MixHelpers do
  @moduledoc """
  Helper functions for testing Mix tasks to reduce duplication in integration tests.

  This module provides utilities for:
  - Running Mix tasks with captured output
  - Validating task execution results
  - Testing command-line argument handling
  - JSON output validation for Mix tasks
  """

  import ExUnit.CaptureIO
  import ExUnit.Assertions

  @doc """
  Runs a Mix task and captures its output.

  ## Parameters
  - task_module: Module name of the Mix task (e.g., Mix.Tasks.Effect)
  - args: List of arguments to pass to the task

  ## Returns
  - Captured output string
  """
  def run_mix_task(task_module, args \\ []) do
    capture_io(fn ->
      try do
        apply(task_module, :run, [args])
      rescue
        error ->
          # Re-raise with more context
          reraise error, __STACKTRACE__
      end
    end)
  end

  @doc """
  Runs a Mix task with timeout and captures output.

  ## Parameters
  - task_module: Module name of the Mix task
  - args: List of arguments to pass to the task
  - timeout: Timeout in milliseconds (default: 10_000)

  ## Returns
  - {:ok, output} on success, {:error, reason} on timeout
  """
  def run_mix_task_with_timeout(task_module, args \\ [], timeout \\ 10_000) do
    try do
      output =
        Task.async(fn -> run_mix_task(task_module, args) end)
        |> Task.await(timeout)

      {:ok, output}
    rescue
      error -> {:error, error}
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
      :exit, reason -> {:error, reason}
    end
  end

  @doc """
  Runs a Mix task and asserts it completes without crashing.

  ## Parameters
  - task_module: Module name of the Mix task
  - args: List of arguments to pass to the task
  - expected_patterns: Optional list of patterns that should appear in output

  ## Returns
  - Output string for further assertions
  """
  def assert_mix_task_succeeds(task_module, args \\ [], expected_patterns \\ []) do
    output = run_mix_task(task_module, args)

    # Check for common error patterns
    refute output =~ "** (Protocol.UndefinedError)"
    refute output =~ "** (FunctionClauseError)"
    refute output =~ "** (MatchError)"
    refute output =~ "** (UndefinedFunctionError)"
    refute output =~ "** (RuntimeError)"

    # Check for expected patterns if provided
    for pattern <- expected_patterns do
      assert output =~ pattern, "Expected output to contain '#{pattern}', got: #{output}"
    end

    output
  end

  @doc """
  Runs a Mix task and asserts it produces valid JSON output.

  ## Parameters
  - task_module: Module name of the Mix task
  - args: List of arguments to pass to the task (should include --json)
  - expected_keys: Optional list of expected keys in the JSON

  ## Returns
  - Parsed JSON map
  """
  def assert_mix_task_produces_json(task_module, args \\ [], expected_keys \\ []) do
    # Ensure --json is in args
    json_args = if "--json" in args, do: args, else: args ++ ["--json"]

    json_output = run_mix_task(task_module, json_args)

    # Parse and validate JSON
    assert {:ok, parsed} = Jason.decode(json_output),
           "Invalid JSON output: #{json_output}"

    assert is_map(parsed),
           "Expected JSON to be an object, got: #{inspect(parsed)}"

    # Check for expected keys
    for key <- expected_keys do
      assert Map.has_key?(parsed, key),
             "Expected JSON to contain key '#{key}', got: #{inspect(Map.keys(parsed))}"
    end

    parsed
  end

  @doc """
  Tests a Mix task with different flag combinations.

  ## Parameters
  - task_module: Module name of the Mix task
  - base_args: Base arguments to use
  - flags: List of flags to test individually

  ## Returns
  - Map of flag to output
  """
  def test_mix_task_flags(task_module, base_args \\ [], flags \\ []) do
    Enum.reduce(flags, %{}, fn flag, acc ->
      args = base_args ++ [flag]
      output = assert_mix_task_succeeds(task_module, args)
      Map.put(acc, flag, output)
    end)
  end

  @doc """
  Tests a Mix task with multiple files.

  ## Parameters
  - task_module: Module name of the Mix task
  - files: List of file paths to analyze
  - extra_args: Additional arguments to pass

  ## Returns
  - Output string
  """
  def test_mix_task_with_files(task_module, files, extra_args \\ []) do
    args = files ++ extra_args
    assert_mix_task_succeeds(task_module, args)
  end

  @doc """
  Asserts that a Mix task fails with expected error pattern.

  ## Parameters
  - task_module: Module name of the Mix task
  - args: List of arguments to pass to the task
  - expected_error: Expected error pattern (string or regex)
  """
  def assert_mix_task_fails(task_module, args \\ [], expected_error \\ nil) do
    output = run_mix_task(task_module, args)

    if expected_error do
      case expected_error do
        regex when is_struct(regex, Regex) ->
          assert Regex.match?(regex, output),
                 "Expected output to match error pattern #{inspect(regex)}, got: #{output}"

        string ->
          assert output =~ string,
                 "Expected output to contain error '#{string}', got: #{output}"
      end
    end

    # Should contain some indication of failure
    assert output =~ "**" or output =~ "error" or output =~ "Error",
           "Expected error indication in output, got: #{output}"
  end

  @doc """
  Tests Mix task performance by measuring execution time.

  ## Parameters
  - task_module: Module name of the Mix task
  - args: List of arguments to pass to the task
  - max_time_ms: Maximum allowed execution time in milliseconds

  ## Returns
  - {output, execution_time_ms} tuple
  """
  def measure_mix_task_performance(task_module, args \\ [], max_time_ms \\ 5_000) do
    {time_micro, output} = :timer.tc(fn -> run_mix_task(task_module, args) end)
    time_ms = time_micro / 1000

    assert time_ms <= max_time_ms,
           "Task took #{time_ms}ms, expected <= #{max_time_ms}ms"

    {output, time_ms}
  end

  @doc """
  Creates a temporary file with given content for testing.

  ## Parameters
  - content: Content to write to the file
  - extension: File extension (default: ".ex")

  ## Returns
  - {file_path, content} tuple
  """
  def create_temp_file(content, extension \\ ".ex") do
    temp_dir = System.tmp_dir!()
    file_name = "test_#{System.unique_integer()}#{extension}"
    file_path = Path.join(temp_dir, file_name)

    File.write!(file_path, content)
    {file_path, content}
  end

  @doc """
  Cleans up temporary files created for testing.

  ## Parameters
  - file_paths: List of file paths to clean up
  """
  def cleanup_temp_files(file_paths) do
    for file_path <- List.wrap(file_paths) do
      if File.exists?(file_path) do
        File.rm(file_path)
      end
    end
  end

  @doc """
  Tests Mix task with temporary files.

  ## Parameters
  - task_module: Module name of the Mix task
  - file_contents: Map of file names to content
  - extra_args: Additional arguments to pass to the task

  ## Returns
  - {output, file_paths} tuple
  """
  def test_mix_task_with_temp_files(task_module, file_contents, extra_args \\ []) do
    # Create temporary files
    {file_paths, _} =
      Enum.reduce(file_contents, {[], %{}}, fn {file_name, content}, {paths, acc} ->
        {path, _} = create_temp_file(content, Path.extname(file_name))
        {[path | paths], Map.put(acc, file_name, path)}
      end)

    try do
      # Run task with temporary files
      args = file_paths ++ extra_args
      output = assert_mix_task_succeeds(task_module, args)
      {output, file_paths}
    after
      # Cleanup
      cleanup_temp_files(file_paths)
    end
  end

  @doc """
  Validates that Mix task output contains expected structure.

  ## Parameters
  - output: Output string from Mix task
  - expected_structure: Map describing expected output structure

  ## Examples
      expected_structure = %{
        modules: %{
          min_count: 1,
          patterns: ["Module:", "functions analyzed"]
        },
        functions: %{
          patterns: ["Effect:", "Type:"]
        }
      }
  """
  def assert_output_structure(output, expected_structure) do
    for {_section, expectations} <- expected_structure do
      case expectations do
        %{min_count: count, patterns: patterns} ->
          # Check that patterns appear at least the specified number of times
          for pattern <- patterns do
            actual_count = count_substring_occurrences(output, pattern)

            assert actual_count >= count,
                   "Expected pattern '#{pattern}' to appear at least #{count} times, got #{actual_count}"
          end

        %{patterns: patterns} ->
          # Check that patterns appear at least once
          for pattern <- patterns do
            assert output =~ pattern,
                   "Expected output to contain '#{pattern}', got: #{output}"
          end

        %{exact: exact_string} ->
          assert output == exact_string,
                 "Expected exact output '#{exact_string}', got: '#{output}'"

        %{regex: regex} ->
          assert Regex.match?(regex, output),
                 "Expected output to match regex #{inspect(regex)}, got: #{output}"
      end
    end
  end

  defp count_substring_occurrences(string, substring) do
    string
    |> String.split(substring)
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  @doc """
  Tests Mix task with various invalid inputs to ensure proper error handling.

  ## Parameters
  - task_module: Module name of the Mix task
  - invalid_inputs: List of invalid argument lists

  ## Returns
  - Map of input to error output
  """
  def test_mix_task_error_cases(task_module, invalid_inputs) do
    Enum.reduce(invalid_inputs, %{}, fn invalid_args, acc ->
      output = run_mix_task(task_module, invalid_args)
      Map.put(acc, invalid_args, output)
    end)
  end

  @doc """
  Common Mix task test scenarios that can be reused across tasks.
  """
  def common_test_scenarios do
    %{
      basic_args: [["--help"], ["--version"], []],
      file_args: [["nonexistent.ex"], ["test/support/demo.ex"]],
      flag_combinations: [
        ["--verbose"],
        ["--json"],
        ["--verbose", "--json"],
        ["--exceptions"],
        ["--purity"]
      ],
      invalid_args: [
        ["--invalid-flag"],
        ["--json", "extra-arg"],
        []
      ]
    }
  end

end
