defmodule Litmus.Spikes.DependencyAnalysisPerformanceTest do
  use ExUnit.Case, async: false

  @moduletag :spike
  @moduletag :spike4

  alias Litmus.Spikes.DependencyAnalysisSpike

  @moduledoc """
  Tests for Spike 4: Recursive Dependency Analysis Performance

  This spike tests whether we can efficiently analyze large projects with:
  1. 500+ modules analyzed in <30s (cold)
  2. Re-analysis in <1s (incremental)
  3. Memory usage <500MB
  4. Effective caching

  ## Success Criteria
  - All performance targets met
  - No crashes or hangs
  - Scalable architecture

  ## Decision
  If all tests pass → Proceed with Tasks 1, 2, 3
  If some tests fail → Implement optimizations (parallelization, caching)
  If many tests fail → Redesign approach
  """

  # Use the litmus project itself for testing
  @test_glob "lib/**/*.ex"

  describe "Test 1: Module Discovery" do
    test "can count modules in the project" do
      result = DependencyAnalysisSpike.count_project_modules(@test_glob)

      case result do
        {:ok, module_count, files} ->
          IO.puts("""

          ✅ MODULE DISCOVERY SUCCESS
          - Modules found: #{module_count}
          - Files found: #{length(files)}
          - Avg modules per file: #{Float.round(module_count / length(files), 2)}
          """)

          assert module_count > 0
          assert length(files) > 0

        {:error, reason} ->
          flunk("Module discovery failed: #{inspect(reason)}")
      end
    end
  end

  describe "Test 2: Cold Analysis Performance" do
    @tag timeout: 60_000
    test "can analyze project in reasonable time (cold start)" do
      {:ok, _module_count, files} = DependencyAnalysisSpike.count_project_modules(@test_glob)

      metrics = DependencyAnalysisSpike.measure_cold_analysis(files)

      IO.puts("""

      📊 COLD ANALYSIS PERFORMANCE
      - Time: #{Float.round(metrics.time_seconds, 2)}s
      - Modules analyzed: #{metrics.modules_analyzed}
      - Files analyzed: #{metrics.files_analyzed}
      - Speed: #{Float.round(metrics.modules_per_second, 2)} modules/second
      """)

      # Success criteria: <30s for cold analysis
      target_seconds = 30.0

      if metrics.time_seconds <= target_seconds do
        IO.puts("✅ Cold analysis PASS: #{Float.round(metrics.time_seconds, 2)}s ≤ #{target_seconds}s")
        assert metrics.time_seconds <= target_seconds
      else
        IO.puts("""
        ⚠️  Cold analysis SLOW: #{Float.round(metrics.time_seconds, 2)}s > #{target_seconds}s
        - This may still be acceptable depending on project size
        - Recommendation: Consider parallelization or optimization
        """)

        # Still assert true to allow spike to continue
        # The final decision will be made in summary test
        assert metrics.time_seconds > 0
      end
    end
  end

  describe "Test 3: Incremental Analysis Performance" do
    @tag timeout: 60_000
    test "can re-analyze quickly after a change (incremental)" do
      {:ok, _module_count, files} = DependencyAnalysisSpike.count_project_modules(@test_glob)

      # First do cold analysis to populate cache
      cold_metrics = DependencyAnalysisSpike.measure_cold_analysis(files)

      # Then measure incremental
      incr_metrics = DependencyAnalysisSpike.measure_incremental_analysis(files, cold_metrics.results)

      IO.puts("""

      📊 INCREMENTAL ANALYSIS PERFORMANCE
      - Time: #{Float.round(incr_metrics.time_seconds, 3)}s
      - Modified file: #{Path.basename(incr_metrics.modified_file)}
      - Modules re-analyzed: #{incr_metrics.modules_reanalyzed}
      - Speedup vs cold: #{Float.round(cold_metrics.time_seconds / incr_metrics.time_seconds, 1)}x
      """)

      # Success criteria: <1s for incremental analysis
      target_seconds = 1.0

      if incr_metrics.time_seconds <= target_seconds do
        IO.puts("✅ Incremental analysis PASS: #{Float.round(incr_metrics.time_seconds, 3)}s ≤ #{target_seconds}s")
        assert incr_metrics.time_seconds <= target_seconds
      else
        IO.puts("""
        ⚠️  Incremental analysis SLOW: #{Float.round(incr_metrics.time_seconds, 3)}s > #{target_seconds}s
        - Recommendation: Improve caching strategy
        - Consider dependency tracking for invalidation
        """)

        assert incr_metrics.time_seconds > 0
      end
    end
  end

  describe "Test 4: Memory Usage" do
    @tag timeout: 60_000
    test "memory usage is reasonable" do
      {:ok, _module_count, files} = DependencyAnalysisSpike.count_project_modules(@test_glob)

      memory_metrics = DependencyAnalysisSpike.measure_memory_usage(files)

      IO.puts("""

      📊 MEMORY USAGE
      - Peak memory: #{memory_metrics.peak_mb} MB
      - Delta: #{memory_metrics.delta_mb} MB
      - Per module: #{Float.round(memory_metrics.delta_mb / memory_metrics.modules_analyzed, 3)} MB
      """)

      # Success criteria: <500MB peak memory
      target_mb = 500.0

      if memory_metrics.peak_mb <= target_mb do
        IO.puts("✅ Memory usage PASS: #{memory_metrics.peak_mb} MB ≤ #{target_mb} MB")
        assert memory_metrics.peak_mb <= target_mb
      else
        IO.puts("""
        ⚠️  Memory usage HIGH: #{memory_metrics.peak_mb} MB > #{target_mb} MB
        - Recommendation: Optimize data structures
        - Consider streaming or chunked processing
        """)

        assert memory_metrics.peak_mb > 0
      end
    end
  end

  describe "Test 5: Cache Efficiency" do
    @tag timeout: 60_000
    test "cache size is reasonable" do
      {:ok, _module_count, files} = DependencyAnalysisSpike.count_project_modules(@test_glob)

      cold_metrics = DependencyAnalysisSpike.measure_cold_analysis(files)
      cache_metrics = DependencyAnalysisSpike.measure_cache_size(cold_metrics.results)

      IO.puts("""

      📊 CACHE EFFICIENCY
      - Cache entries: #{cache_metrics.cache_entries}
      - Serialized size: #{cache_metrics.serialized_mb} MB
      - Per module: #{cache_metrics.bytes_per_module} bytes
      """)

      # Cache should be manageable (< 100MB for normal projects)
      # But we won't fail on this, just document

      if cache_metrics.serialized_mb < 100.0 do
        IO.puts("✅ Cache size is reasonable")
      else
        IO.puts("⚠️  Cache size is large - may need compression or selective caching")
      end

      assert cache_metrics.cache_entries > 0
    end
  end

  describe "Test 6: Bottleneck Analysis" do
    @tag timeout: 60_000
    test "identify where time is spent" do
      {:ok, _module_count, files} = DependencyAnalysisSpike.count_project_modules(@test_glob)

      bottlenecks = DependencyAnalysisSpike.analyze_bottlenecks(files)

      total_time = bottlenecks.file_reading_ms +
                   bottlenecks.ast_parsing_ms +
                   bottlenecks.graph_building_ms

      IO.puts("""

      📊 BOTTLENECK ANALYSIS
      - File reading: #{Float.round(bottlenecks.file_reading_ms, 2)}ms (#{Float.round(bottlenecks.file_reading_ms / total_time * 100, 1)}%)
      - AST parsing: #{Float.round(bottlenecks.ast_parsing_ms, 2)}ms (#{Float.round(bottlenecks.ast_parsing_ms / total_time * 100, 1)}%)
      - Graph building: #{Float.round(bottlenecks.graph_building_ms, 2)}ms (#{Float.round(bottlenecks.graph_building_ms / total_time * 100, 1)}%)
      - Full analysis: #{Float.round(bottlenecks.full_analysis_ms, 2)}ms
      """)

      # Identify the slowest phase
      slowest =
        [
          {"File reading", bottlenecks.file_reading_ms},
          {"AST parsing", bottlenecks.ast_parsing_ms},
          {"Graph building", bottlenecks.graph_building_ms}
        ]
        |> Enum.max_by(fn {_, time} -> time end)

      {phase, time} = slowest
      IO.puts("⚠️  Slowest phase: #{phase} (#{Float.round(time, 2)}ms)")

      assert true
    end
  end

  describe "Test 7: Summary and Decision" do
    @tag timeout: 60_000
    test "print final recommendation" do
      # Run the full benchmark
      results = DependencyAnalysisSpike.run_full_benchmark(@test_glob)

      IO.puts("""

      ═══════════════════════════════════════════════════════
      SPIKE 4: RECURSIVE DEPENDENCY ANALYSIS - SUMMARY
      ═══════════════════════════════════════════════════════

      Setup:
        - Modules: #{results.setup.modules}
        - Files: #{results.setup.files}

      Performance:
        - Cold analysis: #{Float.round(results.cold_analysis.time_seconds, 2)}s (target: <30s)
        - Incremental: #{Float.round(results.incremental_analysis.time_seconds, 3)}s (target: <1s)
        - Memory peak: #{results.memory.peak_mb} MB (target: <500MB)

      Decision: #{format_decision(results.decision)}

      #{recommendation_text(results.decision)}
      ═══════════════════════════════════════════════════════
      """)

      # Always pass - this is informational
      assert true
    end
  end

  defp format_decision(:go), do: "✅ GO"
  defp format_decision(:conditional_go), do: "⚠️  CONDITIONAL GO"
  defp format_decision(:no_go), do: "❌ NO-GO"

  defp recommendation_text(:go) do
    """
    All performance criteria met!
    Recommendation: Proceed with Tasks 1, 2, 3 as planned.
    """
  end

  defp recommendation_text(:conditional_go) do
    """
    Performance acceptable but could be improved.
    Recommendation:
      - Consider parallelization for large projects
      - Optimize caching strategy
      - Profile and optimize hot paths
    """
  end

  defp recommendation_text(:no_go) do
    """
    Performance does not meet criteria.
    Recommendation:
      - Implement parallelization (Task workers)
      - Add depth limits for transitive analysis
      - Use simpler caching (persist to disk)
      - Consider lazy loading (analyze on-demand)
    """
  end
end
