# Spike 4: Recursive Dependency Analysis Performance

**Date**: 2025-01-24
**Status**: ✅ COMPLETE - SUCCESS
**Affects**: Tasks 1, 2, 3 (Dependency Graph Builder, AST Walker, Recursive Analysis)
**Decision**: ✅ GO - All criteria exceeded

---

## Objective

Validate that recursive dependency analysis can handle large projects (500+ modules) efficiently.

**Success Criteria**:
- ✅ Cold analysis: <30s for 500+ modules
- ✅ Incremental analysis: <1s for updates
- ✅ Memory usage: reasonable (<500MB)
- ✅ Cache behavior: effective

---

## Phase 1: Setup Test Environment

### 1.1 Create Phoenix Test Project
- Use `mix phx.new spike4_test_app --no-install` to generate Phoenix app
- OR clone existing Phoenix repo (like Phoenix framework itself)
- Verify module count: should have 500+ modules (including deps)
- Document test environment specs

### 1.2 Create Spike Infrastructure
**File**: `lib/litmus/spikes/dependency_analysis_spike.ex`
- Module with performance testing functions:
  - `count_project_modules/1` - Count total modules in project
  - `measure_cold_analysis/1` - First-time full analysis with timing
  - `measure_incremental_analysis/2` - Re-analysis after single file change
  - `measure_memory_usage/1` - Peak memory during analysis
  - `measure_cache_size/1` - Size of cached results
  - `analyze_bottlenecks/1` - Profile to identify slow operations

---

## Phase 2: Implement Measurement Infrastructure

### 2.1 Performance Metrics Module
Instrumentation for:
- **Time tracking**: Use `:timer.tc/1` for microsecond precision
- **Memory tracking**: Use `:erlang.memory/1` before/after
- **Cache size**: Measure serialized size of results
- **Progress reporting**: Show which modules are being analyzed

### 2.2 Benchmark Runner
**File**: `spike4/run_benchmark.exs`
- Automated script to run all measurements
- Similar to Spike 3's benchmark runner
- Produces structured output (both console and JSON)

---

## Phase 3: Create Test Suite

### 3.1 Test File Structure
**File**: `test/spike4/dependency_analysis_performance_test.exs`

Test groups:
1. **Module Discovery Test** - Count modules in test project
2. **Cold Analysis Test** - First-time analysis timing
3. **Incremental Analysis Test** - Update timing after change
4. **Memory Usage Test** - Peak memory measurement
5. **Cache Efficiency Test** - Validate caching works
6. **Cycle Handling Test** - Performance with circular deps
7. **Summary Test** - Print final recommendation

---

## Phase 4: Run Performance Tests

### 4.1 Execute Benchmark
- Run on Phoenix test app or large project
- Collect all metrics
- Save raw data to `spike4/raw_results.json`

### 4.2 Identify Bottlenecks
If performance doesn't meet criteria:
- Profile with `:eprof` or `:fprof`
- Identify slowest operations
- Check if issue is:
  - File I/O bottleneck
  - AST parsing overhead
  - Dependency resolution
  - Cache lookup inefficiency

---

## Phase 5: Document Results

### 5.1 Results Document
**File**: `spike4/SPIKE4_RESULTS.md`

Sections:
- **Executive Summary** - Pass/fail with key metrics
- **Performance Results** - Tables comparing actual vs target
- **Bottleneck Analysis** - Where time is spent
- **Memory Analysis** - Peak usage and cache size
- **Scalability Assessment** - Projected performance at different scales
- **Edge Cases** - Circular deps, missing modules, etc.
- **Decision Matrix** - Go/No-Go with clear criteria
- **Recommendations** - Next steps based on results

### 5.2 Decision Framework
```
✅ GO DECISION if:
- Cold analysis: <30s for 500+ modules
- Incremental: <1s
- Memory: <500MB
- No critical bottlenecks

⚠️ CONDITIONAL GO if:
- Slightly over targets but acceptable
- Optimization opportunities identified
- Parallelization can help

❌ NO-GO if:
- Fundamentally too slow (>60s cold)
- Memory issues (>1GB)
- Architecture needs redesign
```

---

## Optimization Path (if needed)

**Options**:
1. **Parallelization** - Analyze independent modules concurrently
2. **Lazy Loading** - Only analyze what's needed
3. **Smarter Caching** - Persist to disk, incremental updates
4. **Depth Limits** - Limit transitive dependency depth
5. **Precomputed Registry** - Build effect cache for deps at install time

---

## File Structure

```
spike4/
├── SPIKE4.md                      # This file
├── run_benchmark.exs              # Automated benchmark runner
├── SPIKE4_RESULTS.md              # Final results and decision
└── raw_results.json               # Raw performance data

lib/litmus/spikes/
└── dependency_analysis_spike.ex   # Core spike implementation

test/spike4/
└── dependency_analysis_performance_test.exs  # Test suite
```

---

## Timeline

- **Setup**: 30 minutes
- **Implementation**: 1-2 hours
- **Testing**: 30 minutes
- **Documentation**: 30 minutes
- **Total**: ~3-4 hours

---

## Key Components to Test

Based on existing code:
1. `DependencyGraph.from_files/1` - Test performance
2. `ProjectAnalyzer.analyze_project/1` - Benchmark it
3. Fixed-point iteration for cycles - Test convergence speed
4. Tarjan's algorithm for SCC detection - Verify not a bottleneck

---

## Next Steps After Spike

**If SUCCESS**: Proceed with Tasks 1, 2, 3 as planned
**If CONDITIONAL**: Implement optimizations, then proceed
**If FAILURE**: Redesign approach (simpler caching, depth limits, parallel analysis)
