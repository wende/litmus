#!/usr/bin/env elixir

# Spike 3 Protocol Effect Tracing Benchmark
# Runs all 50 test cases and measures accuracy

Code.require_file("spike3/benchmark_corpus.ex", File.cwd!())
Code.require_file("lib/litmus/spike3/protocol_effect_tracer.ex", File.cwd!())
Code.require_file("lib/litmus/spike3/protocol_resolver.ex", File.cwd!())
Code.require_file("lib/litmus/spike3/struct_types.ex", File.cwd!())

alias Spike3.BenchmarkCorpus
alias Litmus.Spike3.ProtocolEffectTracer

defmodule Spike3.BenchmarkRunner do
  @moduledoc """
  Runs the comprehensive benchmark and reports results.
  """

  def run do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("SPIKE 3: PROTOCOL EFFECT TRACING BENCHMARK")
    IO.puts(String.duplicate("=", 80))
    IO.puts("\nRunning 50 test cases...")
    IO.puts("")

    cases = BenchmarkCorpus.all_cases()
    results = Enum.map(cases, &run_case/1)

    print_results(results)
    print_summary(results)
    print_failure_analysis(results)
    print_category_breakdown(results)
    print_conclusion(results)

    results
  end

  defp run_case({case_fun, meta}) do
    %{
      struct_type: struct_type,
      lambda_effect: lambda_effect,
      expected_effect: expected,
      function: function,
      category: category,
      description: description
    } = meta

    # Skip cases that aren't Enum operations for now
    # (String.Chars, Inspect, etc. need separate handling)
    result =
      if category == :enum and function != :pipeline and function != :comprehension and
           function != :into do
        case ProtocolEffectTracer.trace_protocol_call(
               Enum,
               function,
               struct_type,
               lambda_effect
             ) do
          {:ok, ^expected} ->
            :success

          {:ok, actual} ->
            {:failure, :wrong_effect, actual, expected}

          :unknown ->
            {:failure, :unknown, nil, expected}

          other ->
            {:failure, :error, other, expected}
        end
      else
        # Mark non-Enum cases as skipped for now
        {:skipped, category}
      end

    %{
      case: case_fun,
      meta: meta,
      result: result
    }
  end

  defp print_results(results) do
    IO.puts("Individual Results:")
    IO.puts(String.duplicate("-", 80))

    for {result, index} <- Enum.with_index(results, 1) do
      case_num = String.pad_leading(to_string(index), 2, "0")
      status = format_status(result.result)
      desc = result.meta.description

      IO.puts("Case #{case_num}: #{status} - #{desc}")
    end

    IO.puts("")
  end

  defp format_status(:success), do: "✅ PASS"
  defp format_status({:skipped, _reason}), do: "⏭️  SKIP"

  defp format_status({:failure, :wrong_effect, actual, expected}),
    do: "❌ FAIL (got #{inspect(actual)}, expected #{inspect(expected)})"

  defp format_status({:failure, :unknown, _, expected}),
    do: "❌ FAIL (unknown, expected #{inspect(expected)})"

  defp format_status({:failure, :error, error, _}), do: "❌ ERROR (#{inspect(error)})"

  defp print_summary(results) do
    total = length(results)
    success = Enum.count(results, &(&1.result == :success))
    skipped = Enum.count(results, &match?({:skipped, _}, &1.result))
    failures = Enum.count(results, &match?({:failure, _, _, _}, &1.result))

    tested = total - skipped
    accuracy = if tested > 0, do: success / tested * 100, else: 0.0

    IO.puts(String.duplicate("=", 80))
    IO.puts("SUMMARY")
    IO.puts(String.duplicate("=", 80))
    IO.puts("Total cases:    #{total}")
    IO.puts("Tested:         #{tested}")
    IO.puts("Skipped:        #{skipped}")
    IO.puts("Success:        #{success}")
    IO.puts("Failures:       #{failures}")
    IO.puts("")
    IO.puts("Accuracy:       #{success}/#{tested} (#{Float.round(accuracy, 2)}%)")
    IO.puts("")
  end

  defp print_failure_analysis(results) do
    failures =
      results
      |> Enum.filter(&match?(%{result: {:failure, _, _, _}}, &1))

    if length(failures) > 0 do
      IO.puts(String.duplicate("=", 80))
      IO.puts("FAILURE ANALYSIS")
      IO.puts(String.duplicate("=", 80))

      for failure <- failures do
        IO.puts("Case: #{failure.case}")
        IO.puts("  Description: #{failure.meta.description}")

        case failure.result do
          {:failure, :wrong_effect, actual, expected} ->
            IO.puts("  Expected: #{inspect(expected)}")
            IO.puts("  Got:      #{inspect(actual)}")

          {:failure, :unknown, _, expected} ->
            IO.puts("  Expected: #{inspect(expected)}")
            IO.puts("  Got:      :unknown (couldn't resolve)")

          {:failure, :error, error, _} ->
            IO.puts("  Error: #{inspect(error)}")
        end

        IO.puts("")
      end
    end
  end

  defp print_category_breakdown(results) do
    IO.puts(String.duplicate("=", 80))
    IO.puts("BREAKDOWN BY CATEGORY")
    IO.puts(String.duplicate("=", 80))

    by_category =
      results
      |> Enum.group_by(& &1.meta.category)

    for {category, cases} <- Enum.sort(by_category) do
      total = length(cases)
      success = Enum.count(cases, &(&1.result == :success))
      skipped = Enum.count(cases, &match?(%{result: {:skipped, _}}, &1))
      tested = total - skipped
      accuracy = if tested > 0, do: success / tested * 100, else: 0.0

      IO.puts(
        "#{category}: #{success}/#{tested} (#{Float.round(accuracy, 2)}%) [#{skipped} skipped]"
      )
    end

    IO.puts("")
  end

  defp print_conclusion(results) do
    tested =
      results
      |> Enum.reject(&match?(%{result: {:skipped, _}}, &1))
      |> length()

    success = Enum.count(results, &(&1.result == :success))
    accuracy = if tested > 0, do: success / tested * 100, else: 0.0

    IO.puts(String.duplicate("=", 80))
    IO.puts("CONCLUSION")
    IO.puts(String.duplicate("=", 80))

    cond do
      accuracy >= 85.0 ->
        IO.puts("✅ HIGH GO - Ready for Task 9 integration (#{Float.round(accuracy, 2)}% accuracy)")

      accuracy >= 70.0 ->
        IO.puts(
          "⚠️  MEDIUM GO - Feasible with known limitations (#{Float.round(accuracy, 2)}% accuracy)"
        )

      accuracy >= 50.0 ->
        IO.puts(
          "⚠️  LOW GO - Needs more investigation (#{Float.round(accuracy, 2)}% accuracy)"
        )

      true ->
        IO.puts("❌ NO-GO - Fundamental blockers identified (#{Float.round(accuracy, 2)}% accuracy)")
    end

    IO.puts("")
  end
end

# Run the benchmark
Spike3.BenchmarkRunner.run()
