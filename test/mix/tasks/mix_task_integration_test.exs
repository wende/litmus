defmodule Mix.Tasks.IntegrationTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  @moduledoc """
  Integration tests for mix tasks to catch runtime bugs that compile-time checks miss.

  These tests verify that:
  - Mix tasks run without crashing
  - Output formatting works correctly
  - JSON output is valid
  - Command-line flags work as expected
  """

  describe "mix effect" do
    test "basic analysis works without crashing" do
      output = capture_io(fn ->
        Mix.Tasks.Effect.run(["test/support/demo.ex"])
      end)

      assert output =~ "Module:"
      refute output =~ "** (Protocol.UndefinedError)"
      refute output =~ "** (FunctionClauseError)"
    end

    test "verbose mode works" do
      output = capture_io(fn ->
        Mix.Tasks.Effect.run(["test/support/demo.ex", "--verbose"])
      end)

      assert output =~ "Type:"
      refute output =~ "** (FunctionClauseError)"
    end

    test "json mode produces valid JSON" do
      json_output = capture_io(fn ->
        Mix.Tasks.Effect.run(["test/support/demo.ex", "--json"])
      end)

      # Should be parseable as JSON
      assert {:ok, parsed} = Jason.decode(json_output)
      assert is_map(parsed)

      # Should have expected structure
      assert Map.has_key?(parsed, "functions")
    end

    test "handles files with edge cases" do
      output = capture_io(fn ->
        Mix.Tasks.Effect.run(["test/support/edge_cases_test.exs"])
      end)

      # Should complete without crashing
      assert output =~ "Module:" or output =~ "functions analyzed"
      refute output =~ "** (Protocol.UndefinedError)"
    end

    test "handles multiple files" do
      output = capture_io(fn ->
        Mix.Tasks.Effect.run(["test/support/demo.ex", "test/support/sample_module.ex"])
      end)

      assert output =~ "Module:"
      refute output =~ "** (FunctionClauseError)"
    end
  end

  describe "mix litmus.merge_explicit" do
    test "merges without crashing" do
      output = capture_io(fn ->
        Mix.Tasks.Litmus.MergeExplicit.run([])
      end)

      # Should complete successfully
      assert output =~ "Merged" or output == ""
      refute output =~ "** (MatchError)"
    end

    test "produces valid JSON output" do
      # Run merge task
      capture_io(fn ->
        Mix.Tasks.Litmus.MergeExplicit.run([])
      end)

      # Verify output file is valid JSON
      std_json = File.read!(".effects/std.json")
      assert {:ok, _parsed} = Jason.decode(std_json)
    end
  end

  describe "mix generate_effects" do
    @tag timeout: 60_000
    @tag :slow
    test "generates dependency cache without crashing" do
      output = capture_io(fn ->
        Mix.Tasks.GenerateEffects.run([])
      end)

      # Should complete (may have no deps)
      refute output =~ "** (UndefinedFunctionError)"
    end
  end

  describe "mix effect.cache.clean" do
    test "cleans cache without crashing" do
      output = capture_io(fn ->
        Mix.Tasks.Effect.Cache.Clean.run([])
      end)

      # Should complete successfully
      refute output =~ "** (File.Error)"
    end
  end
end
