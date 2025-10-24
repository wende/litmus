#!/usr/bin/env elixir

# Spike 4: Recursive Dependency Analysis Performance Benchmark
# Automated script to run performance tests and generate report

# Load dependencies
Code.require_file("lib/litmus/spikes/dependency_analysis_spike.ex", File.cwd!())

alias Litmus.Spikes.DependencyAnalysisSpike

defmodule Spike4.BenchmarkRunner do
  @moduledoc """
  Runs the comprehensive performance benchmark and generates a report.
  """

  def run do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("SPIKE 4: RECURSIVE DEPENDENCY ANALYSIS PERFORMANCE BENCHMARK")
    IO.puts(String.duplicate("=", 80))
    IO.puts("\nStarting benchmark on litmus project...")
    IO.puts("")

    # Run the full benchmark on the litmus project
    results = DependencyAnalysisSpike.run_full_benchmark("lib/**/*.ex")

    # Save results to JSON
    save_results(results)

    # Generate markdown report
    generate_report(results)

    IO.puts("\n✅ Benchmark complete!")
    IO.puts("Results saved to:")
    IO.puts("  - spike4/raw_results.json")
    IO.puts("  - spike4/SPIKE4_RESULTS.md")
    IO.puts("")

    results
  end

  defp save_results(results) do
    # Convert to JSON-friendly format
    json_results = %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      setup: results.setup,
      cold_analysis: %{
        time_seconds: results.cold_analysis.time_seconds,
        modules_analyzed: results.cold_analysis.modules_analyzed,
        files_analyzed: results.cold_analysis.files_analyzed,
        modules_per_second: results.cold_analysis.modules_per_second
      },
      incremental_analysis: %{
        time_seconds: results.incremental_analysis.time_seconds,
        modules_reanalyzed: results.incremental_analysis.modules_reanalyzed,
        modified_file: results.incremental_analysis.modified_file
      },
      memory: %{
        peak_mb: results.memory.peak_mb,
        delta_mb: results.memory.delta_mb
      },
      cache: results.cache,
      bottlenecks: results.bottlenecks,
      decision: Atom.to_string(results.decision)
    }

    json = Jason.encode!(json_results, pretty: true)
    File.write!("spike4/raw_results.json", json)
  end

  defp generate_report(results) do
    decision_emoji = case results.decision do
      :go -> "✅"
      :conditional_go -> "⚠️"
      :no_go -> "❌"
    end

    decision_text = case results.decision do
      :go -> "GO"
      :conditional_go -> "CONDITIONAL GO"
      :no_go -> "NO-GO"
    end

    report = """
    # Spike 4: Recursive Dependency Analysis Performance - Results

    **Date**: #{Date.utc_today() |> Date.to_iso8601()}
    **Status**: #{decision_emoji} **#{decision_text}**
    **Project**: Litmus (self-analysis)

    ---

    ## Executive Summary

    **Decision**: #{decision_emoji} **#{decision_text}**

    #{decision_summary(results)}

    ---

    ## Performance Results

    ### Test Environment

    - **Modules analyzed**: #{results.setup.modules}
    - **Files analyzed**: #{results.setup.files}
    - **Average modules per file**: #{Float.round(results.setup.modules / results.setup.files, 2)}

    ### Cold Analysis (First-time)

    | Metric | Value | Target | Status |
    |--------|-------|--------|--------|
    | Time | #{Float.round(results.cold_analysis.time_seconds, 2)}s | <30s | #{status_icon(results.cold_analysis.time_seconds < 30.0)} |
    | Modules analyzed | #{results.cold_analysis.modules_analyzed} | N/A | ✓ |
    | Speed | #{Float.round(results.cold_analysis.modules_per_second, 2)} modules/s | N/A | ✓ |

    ### Incremental Analysis (After change)

    | Metric | Value | Target | Status |
    |--------|-------|--------|--------|
    | Time | #{Float.round(results.incremental_analysis.time_seconds, 3)}s | <1s | #{status_icon(results.incremental_analysis.time_seconds < 1.0)} |
    | Modules re-analyzed | #{results.incremental_analysis.modules_reanalyzed} | N/A | ✓ |
    | Speedup vs cold | #{Float.round(results.cold_analysis.time_seconds / results.incremental_analysis.time_seconds, 1)}x | N/A | ✓ |

    ### Memory Usage

    | Metric | Value | Target | Status |
    |--------|-------|--------|--------|
    | Peak memory | #{results.memory.peak_mb} MB | <500 MB | #{status_icon(results.memory.peak_mb < 500.0)} |
    | Delta | #{results.memory.delta_mb} MB | N/A | ✓ |

    ### Cache Efficiency

    | Metric | Value |
    |--------|-------|
    | Cache entries | #{results.cache.cache_entries} |
    | Serialized size | #{results.cache.serialized_mb} MB |
    | Per module | #{results.cache.bytes_per_module} bytes |

    ---

    ## Bottleneck Analysis

    Time spent in each phase:

    | Phase | Time (ms) | Percentage |
    |-------|-----------|------------|
    | File reading | #{Float.round(results.bottlenecks.file_reading_ms, 2)} | #{percentage(results.bottlenecks.file_reading_ms, results.bottlenecks.full_analysis_ms)}% |
    | AST parsing | #{Float.round(results.bottlenecks.ast_parsing_ms, 2)} | #{percentage(results.bottlenecks.ast_parsing_ms, results.bottlenecks.full_analysis_ms)}% |
    | Graph building | #{Float.round(results.bottlenecks.graph_building_ms, 2)} | #{percentage(results.bottlenecks.graph_building_ms, results.bottlenecks.full_analysis_ms)}% |
    | **Full analysis** | **#{Float.round(results.bottlenecks.full_analysis_ms, 2)}** | **100%** |

    #{bottleneck_recommendation(results.bottlenecks)}

    ---

    ## Decision Matrix

    #{decision_matrix(results)}

    ---

    ## Recommendations

    #{recommendations(results)}

    ---

    ## Next Steps

    #{next_steps(results)}

    ---

    **Spike Duration**: 2 days (as planned)
    **Confidence Level**: #{confidence_level(results)}
    **Risk Level**: #{risk_level(results)}
    """

    File.write!("spike4/SPIKE4_RESULTS.md", report)
  end

  defp status_icon(true), do: "✅"
  defp status_icon(false), do: "❌"

  defp percentage(part, total) do
    Float.round(part / total * 100, 1)
  end

  defp decision_summary(results) do
    case results.decision do
      :go ->
        """
        All performance criteria met! The recursive dependency analysis system can handle large projects efficiently:

        - ✅ Cold analysis completes in #{Float.round(results.cold_analysis.time_seconds, 2)}s (target: <30s)
        - ✅ Incremental analysis completes in #{Float.round(results.incremental_analysis.time_seconds, 3)}s (target: <1s)
        - ✅ Memory usage is #{results.memory.peak_mb} MB (target: <500 MB)

        **Recommendation**: Proceed with Tasks 1, 2, 3 as planned.
        """

      :conditional_go ->
        """
        Performance is acceptable but could be improved:

        - Cold analysis: #{Float.round(results.cold_analysis.time_seconds, 2)}s (target: <30s) - #{status_text(results.cold_analysis.time_seconds < 30.0)}
        - Incremental: #{Float.round(results.incremental_analysis.time_seconds, 3)}s (target: <1s) - #{status_text(results.incremental_analysis.time_seconds < 1.0)}
        - Memory: #{results.memory.peak_mb} MB (target: <500 MB) - #{status_text(results.memory.peak_mb < 500.0)}

        **Recommendation**: Proceed with Tasks 1, 2, 3 but plan for optimizations.
        """

      :no_go ->
        """
        Performance does not meet criteria:

        - Cold analysis: #{Float.round(results.cold_analysis.time_seconds, 2)}s (target: <30s) - #{status_text(results.cold_analysis.time_seconds < 30.0)}
        - Incremental: #{Float.round(results.incremental_analysis.time_seconds, 3)}s (target: <1s) - #{status_text(results.incremental_analysis.time_seconds < 1.0)}
        - Memory: #{results.memory.peak_mb} MB (target: <500 MB) - #{status_text(results.memory.peak_mb < 500.0)}

        **Recommendation**: Redesign approach before proceeding with Tasks 1, 2, 3.
        """
    end
  end

  defp status_text(true), do: "PASS"
  defp status_text(false), do: "FAIL"

  defp bottleneck_recommendation(bottlenecks) do
    slowest_phase = Enum.max_by([
      {"File reading", bottlenecks.file_reading_ms},
      {"AST parsing", bottlenecks.ast_parsing_ms},
      {"Graph building", bottlenecks.graph_building_ms}
    ], fn {_, time} -> time end)

    {phase, _time} = slowest_phase

    """
    **Primary bottleneck**: #{phase}

    Optimization strategies:
    - **File reading**: Use parallel file I/O, consider caching
    - **AST parsing**: Cache parsed ASTs, use binary format
    - **Graph building**: Optimize Tarjan's algorithm, incremental updates
    """
  end

  defp decision_matrix(results) do
    case results.decision do
      :go ->
        """
        | Criterion | Result | Status |
        |-----------|--------|--------|
        | Cold analysis <30s | #{Float.round(results.cold_analysis.time_seconds, 2)}s | ✅ PASS |
        | Incremental <1s | #{Float.round(results.incremental_analysis.time_seconds, 3)}s | ✅ PASS |
        | Memory <500MB | #{results.memory.peak_mb} MB | ✅ PASS |
        | **Overall** | **All criteria met** | **✅ GO** |
        """

      :conditional_go ->
        """
        | Criterion | Result | Status |
        |-----------|--------|--------|
        | Cold analysis <30s | #{Float.round(results.cold_analysis.time_seconds, 2)}s | #{status_icon(results.cold_analysis.time_seconds < 30.0)} |
        | Incremental <1s | #{Float.round(results.incremental_analysis.time_seconds, 3)}s | #{status_icon(results.incremental_analysis.time_seconds < 1.0)} |
        | Memory <500MB | #{results.memory.peak_mb} MB | #{status_icon(results.memory.peak_mb < 500.0)} |
        | **Overall** | **Acceptable with caveats** | **⚠️ CONDITIONAL** |
        """

      :no_go ->
        """
        | Criterion | Result | Status |
        |-----------|--------|--------|
        | Cold analysis <30s | #{Float.round(results.cold_analysis.time_seconds, 2)}s | #{status_icon(results.cold_analysis.time_seconds < 30.0)} |
        | Incremental <1s | #{Float.round(results.incremental_analysis.time_seconds, 3)}s | #{status_icon(results.incremental_analysis.time_seconds < 1.0)} |
        | Memory <500MB | #{results.memory.peak_mb} MB | #{status_icon(results.memory.peak_mb < 500.0)} |
        | **Overall** | **Criteria not met** | **❌ NO-GO** |
        """
    end
  end

  defp recommendations(results) do
    case results.decision do
      :go ->
        """
        1. **Proceed with implementation** of Tasks 1, 2, 3 as planned
        2. **Monitor performance** as codebase grows
        3. **Consider caching** analysis results to disk for persistence
        4. **Document** performance characteristics for users
        """

      :conditional_go ->
        """
        1. **Implement parallelization** for independent module analysis
        2. **Optimize caching** with incremental updates and invalidation
        3. **Profile hot paths** and optimize critical sections
        4. **Consider lazy loading** - analyze only what's needed
        5. **Proceed with Tasks 1, 2, 3** but plan for optimization sprint
        """

      :no_go ->
        """
        1. **Redesign caching strategy** - simpler, more efficient
        2. **Implement parallelization** from the start (Task pool)
        3. **Add depth limits** for transitive dependency analysis
        4. **Use persistent cache** (disk-based, incremental)
        5. **Consider lazy analysis** - on-demand only
        6. **Re-run spike** after implementing optimizations
        """
    end
  end

  defp next_steps(results) do
    case results.decision do
      :go ->
        """
        ### Immediate
        1. Mark Spike 4 as **COMPLETE - SUCCESS**
        2. Begin Task 1: Build Complete Dependency Graph
        3. Begin Task 4: Complete Source Discovery (can run in parallel)

        ### Week 1-2
        - Implement Tasks 1, 4, 5 (foundation infrastructure)
        - Use proven architecture from this spike

        ### Future
        - Monitor performance in production use
        - Add performance tests to CI
        """

      :conditional_go ->
        """
        ### Immediate
        1. Mark Spike 4 as **COMPLETE - CONDITIONAL SUCCESS**
        2. Plan optimization sprint (1-2 days)
        3. Implement quick wins (parallelization, caching)

        ### Week 1
        - Implement optimizations
        - Re-run benchmark to validate improvements
        - Begin Tasks 1, 4, 5 with optimized approach

        ### Week 2+
        - Complete foundation infrastructure
        - Continue optimization as needed
        """

      :no_go ->
        """
        ### Immediate
        1. Mark Spike 4 as **BLOCKED - PERFORMANCE ISSUES**
        2. Analyze bottlenecks in detail
        3. Design optimization strategy

        ### Week 1
        - Implement parallelization framework
        - Add persistent caching
        - Simplify dependency analysis (depth limits)

        ### Week 2
        - Re-run Spike 4 with optimizations
        - If successful, proceed with Tasks 1-5
        - If still failing, consider alternative architecture
        """
    end
  end

  defp confidence_level(results) do
    case results.decision do
      :go -> "**High** (all criteria met)"
      :conditional_go -> "**Medium** (acceptable with optimizations)"
      :no_go -> "**Low** (fundamental issues identified)"
    end
  end

  defp risk_level(results) do
    case results.decision do
      :go -> "**Low** (proven approach)"
      :conditional_go -> "**Medium** (needs optimization)"
      :no_go -> "**High** (requires redesign)"
    end
  end
end

# Run the benchmark
Spike4.BenchmarkRunner.run()
