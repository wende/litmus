defmodule Mix.Tasks.IntegrationTest do
  use ExUnit.Case
  import Test.MixHelpers
  import ExUnit.CaptureIO

  describe "mix effect" do
    test "runs without crashing on simple file" do
      # Create a temporary test file
      test_file = "test_temp.exs"

      File.write!(test_file, """
      defmodule TestTemp do
        def add(x, y), do: x + y
        def greet(name), do: IO.puts("Hello, \#{name}")
      end
      """)

      try do
        # Test that the command runs without crashing
        output = run_mix_task(Mix.Tasks.Effect, [test_file])
        assert output =~ "TestTemp" or output =~ "add" or output =~ "greet"
      after
        File.rm(test_file)
      end
    end

    test "works with absolute paths" do
      test_file = Path.absname("test_temp.exs")

      File.write!(test_file, """
      defmodule TestTemp do
        def identity(x), do: x
      end
      """)

      try do
        # Test with absolute path
        output = run_mix_task(Mix.Tasks.Effect, [test_file])
        assert output =~ "TestTemp" or output =~ "identity"
      after
        File.rm(test_file)
      end
    end

    test "accepts various flags" do
      test_file = "test_temp.exs"

      File.write!(test_file, """
      defmodule TestTemp do
        def add(x, y), do: x + y
      end
      """)

      try do
        # Test with --verbose flag
        run_mix_task(Mix.Tasks.Effect, [test_file, "--verbose"])

        # Test with --json flag
        run_mix_task(Mix.Tasks.Effect, [test_file, "--json"])

        # Test with --exceptions flag
        run_mix_task(Mix.Tasks.Effect, [test_file, "--exceptions"])
      after
        File.rm(test_file)
      end
    end
  end

  describe "mix litmus.merge_explicit" do
    test "merges without crashing" do
      output = assert_mix_task_succeeds(Mix.Tasks.Litmus.MergeExplicit, [])
      assert output =~ "Merged" or output == ""
    end

    test "produces valid JSON output" do
      # Run merge task
      assert_mix_task_succeeds(Mix.Tasks.Litmus.MergeExplicit, [])

      # Verify output file is valid JSON
      std_json = File.read!(".effects/std.json")
      assert {:ok, _parsed} = Jason.decode(std_json)
    end
  end

  describe "mix generate_effects" do
    @tag timeout: 60_000
    @tag :slow
    test "generates dependency cache without crashing" do
      output = assert_mix_task_succeeds(Mix.Tasks.GenerateEffects, [])

      # Should complete (may have no deps)
      refute output =~ "** (UndefinedFunctionError)"
    end
  end

  describe "mix effect.cache.clean" do
    test "cleans cache without crashing" do
      output =
        capture_io(fn ->
          Mix.Tasks.Effect.Cache.Clean.run([])
        end)

      # Should complete successfully
      refute output =~ "** (File.Error)"
    end
  end
end
