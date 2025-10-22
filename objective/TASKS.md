# Task to File Mapping

This document maps each task from OBJECTIVE.md to the corresponding implementation file in the objective/ directory.

---

## Group 1: Foundation Infrastructure

### Task 1: Build Complete Dependency Graph
**File**: `001-dependency-graph-builder.md`
- Discovers all sources (project, deps, Erlang)
- Builds module dependency graph
- Detects cycles with Tarjan's algorithm
- Computes topological analysis order
- **Dependencies**: None (can start immediately)

### Task 4: Complete Source Discovery
**File**: `007-source-discovery-system.md`
- Finds .ex files in deps/*/lib
- Finds .erl files in deps/*/src
- Finds .beam files without source
- Handles umbrella apps and path dependencies
- **Dependencies**: None (can start immediately)

### Task 5: Per-Module Cache Strategy
**File**: `006-module-cache-strategy.md`
- Per-module checksums
- Incremental updates
- Dependency tracking
- Invalidation on upstream changes
- **Dependencies**: None (can start immediately)

---

## Group 2: Core Analysis Fixes

### Task 2: Fix AST Walker Dependency Resolution
**File**: `003-recursive-dependency-analysis.md`
- Add `analyze_dependency_if_needed/1` function
- Recursively analyze missing dependencies
- Cache results immediately
- **Dependencies**: Tasks 1, 4

### Task 3: Implement Recursive Analysis with Memoization
**File**: `003-recursive-dependency-analysis.md`
- GenServer for analysis stack
- Maintains analysis stack to detect cycles
- Memoizes results to avoid re-analysis
- Handles provisional typing for recursion
- **Dependencies**: Tasks 1, 4

### Task 10: Captured Function Detection
**File**: `009-captured-function-detection-fix.md`
- Fix bug in `lib/litmus/pure.ex` lines 485-494
- Analyze captures like `&IO.puts/1`
- Return MFA for checking instead of nil
- **Dependencies**: None (bug fix can be done independently)

---

## Group 3: Analysis Replacement

### Task 6: Replace PURITY with Enhanced AST Walker
**File**: `002-complete-ast-analyzer.md`
- Remove all PURITY dependencies
- Handle all Elixir constructs (maps, structs, protocols)
- Analyze Erlang modules via abstract format
- Complete pattern matching support
- Guard analysis for exceptions
- Macro expansion with proper context
- **Dependencies**: Tasks 1, 2, 3, 4, 5

### Task 7: Eliminate All Unknown Classifications
**File**: `008-unknown-classification-elimination.md`
- Try source analysis first
- Fall back to BEAM analysis if no source
- Conservative inference as last resort
- Use naming conventions as hints not conclusions
- Default to :side_effects not :unknown
- **Dependencies**: Tasks 1, 2, 3, 4, 6

### Task 8: Complete Exception Type Tracking
**File**: `002-complete-ast-analyzer.md`
- Track specific exception types through:
  - raise statements
  - throw statements
  - exit statements
  - Guard failures
  - Kernel.!/1 functions
  - Pattern match failures
- Propagate through function calls and try/catch boundaries
- **Dependencies**: Tasks 6, 7

### Task 9: Dynamic Dispatch Analysis
**File**: `008-unknown-classification-elimination.md`
- Track apply/3 calls
- Analyze possible values via data flow
- Use type inference to narrow possibilities
- Mark as :dynamic_dispatch effect type
- **Dependencies**: Tasks 6, 7

---

## Group 4: CPS Transformation

### Task 11: Support All Control Flow Constructs
**File**: `004-cps-transformation-completion.md`
- **Cond expressions** - Thread continuation through all branches
- **With expressions** - Handle pattern matching and early returns
- **Recursive functions** - Pass recursion point through CPS
- **Multi-clause functions** - Each clause gets same continuation structure
- **Try-catch-rescue-after** - Exception handling with CPS
- **Receive blocks** - Message ordering preservation
- **Dependencies**: Tasks 6, 7, 8

---

## Group 5: Compile-Time Integration

### Task 12: Transform Dependency Code at Compile Time
**File**: `004-cps-transformation-completion.md`
- Get module AST
- Convert to Elixir AST
- Apply CPS transformation
- Recompile module
- **Dependencies**: Tasks 11

---

## Group 6: Runtime Enforcement

### Task 13: Runtime BEAM Modification
**File**: `005-runtime-beam-modifier.md`
- **Approach 1**: AST-level modification (preferred)
- **Approach 2**: Bytecode injection (fallback)
- **Approach 3**: Runtime wrapper (last resort)
- Inject purity checks at function entry
- Load modified module with rollback capability
- **Dependencies**: Tasks 6, 11, 12
- **NOTE**: Requires Spike 1 (BEAM Modification Feasibility) to validate approach

### Task 14: Unified Pure Macro
**File**: `010-unified-pure-macro-rewrite.md`
- Complete rewrite of `lib/litmus/pure.ex`
- Build complete effect registry first
- Transform block with CPS
- Verify NO effects can escape
- Execute with handlers
- **Dependencies**: All previous tasks (6, 7, 11, 12, 13)

---

## Group 7: Validation & Testing

### Task 15: Complete Test Coverage
**Files**: All implementation files
- No effects can escape tests
- All constructs supported tests
- BEAM modification safety tests (isolated)
- End-to-end purity enforcement tests
- Performance benchmarks
- Property-based tests
- **Dependencies**: Progressive (tests written for each task as it's implemented)

---

## Technical Spikes (Week 0 - BEFORE Implementation)

These experiments must be completed BEFORE beginning implementation:

### Spike 1: BEAM Modification Feasibility (3 days)
**Affects**: Task 13 (Runtime BEAM Modifier)
- Test modifying String.upcase/1
- Test on user-defined module
- Test concurrent modification
- **Success Criteria**: Can modify without crashes, <5% overhead
- **If Fails**: Skip Task 13, use compile-time transformation only

### Spike 2: Erlang Abstract Format Conversion (2 days)
**Affects**: Task 6 (Replace PURITY)
- Parse :lists, :maps, :ets, :gen_server
- Convert to analyzable format
- **Success Criteria**: 90% accuracy on common Erlang modules
- **If Fails**: Whitelist common Erlang modules only

### Spike 3: Protocol Dispatch Resolution (2 days)
**Affects**: Task 9 (Dynamic Dispatch Analysis)
- Resolve Enumerable implementations
- Trace effects through protocol calls
- **Success Criteria**: 80% accuracy on user structs
- **If Fails**: Mark all protocol calls as :unknown

### Spike 4: Recursive Dependency Analysis Performance (2 days)
**Affects**: Tasks 1, 2, 3
- Analyze Phoenix project (500+ modules)
- Measure time, memory, cache size
- **Success Criteria**: <30s cold analysis, <1s incremental
- **If Fails**: Implement parallelization, consider depth limits

---

## Critical Path

The minimum required sequence for complete purity enforcement:

```
Technical Spikes (Week 0)
    ↓
Task 1: Dependency Graph (Week 1)
    ↓
Task 4: Source Discovery (Week 1)
    ↓
Task 5: Module Cache (Week 1-2)
    ↓
Task 2 & 3: Recursive Analysis (Week 2)
    ↓
Task 6: Replace PURITY (Week 3-4)
    ↓
Task 7 & 8 & 9: Complete Analysis (Week 4)
    ↓
Task 11: CPS Transformation (Week 5-6)
    ↓
Task 12: Compile-Time Transform (Week 6)
    ↓
Task 13: Runtime BEAM Mod (Week 7)
    ↓
Task 14: Unified Pure Macro (Week 7-8)
    ↓
Task 15: Validation (Week 8)
```

---

## Parallelization Opportunities

Tasks that can be worked on simultaneously by multiple developers:

### Week 1-2:
- **Developer 1**: Task 1 (Dependency Graph)
- **Developer 2**: Task 4 (Source Discovery)
- **Developer 3**: Task 5 (Module Cache)
- **Developer 4**: Task 10 (Captured Function Fix - quick win)

### Week 2-3:
- **Developer 1**: Task 2 (Fix AST Walker)
- **Developer 2**: Task 3 (Recursive Analysis)
- Both developers coordinate closely as these are tightly coupled

### Week 3-4:
- **Developer 1**: Task 6 (Replace PURITY)
- **Developer 2**: Task 7 (Eliminate Unknown)
- **Developer 3**: Task 8 (Exception Tracking)
- **Developer 4**: Task 9 (Dynamic Dispatch)

### Week 5-6:
- **All Developers**: Task 11 (CPS Transformation)
  - Developer 1: cond + with
  - Developer 2: recursive + multi-clause
  - Developer 3: try-catch-rescue-after
  - Developer 4: receive blocks

### Week 7:
- **Developer 1**: Task 13 (BEAM Modifier)
- **Developer 2**: Task 12 (Compile-Time Transform)
- Both feed into Task 14

### Week 8:
- **Developer 1**: Task 14 (Unified Pure Macro)
- **All Developers**: Task 15 (Testing and Validation)

---

## File Dependencies

Each objective file depends on these other files being completed first:

```
001-dependency-graph-builder.md
  ├─ No dependencies

007-source-discovery-system.md
  ├─ No dependencies

006-module-cache-strategy.md
  ├─ No dependencies

009-captured-function-detection-fix.md
  ├─ No dependencies (can be done immediately)

003-recursive-dependency-analysis.md
  ├─ Requires: 001, 007

002-complete-ast-analyzer.md
  ├─ Requires: 001, 003, 007, 006

008-unknown-classification-elimination.md
  ├─ Requires: 002, 003

004-cps-transformation-completion.md
  ├─ Requires: 002, 008

005-runtime-beam-modifier.md
  ├─ Requires: 002, 004
  ├─ Requires: Spike 1 validation

010-unified-pure-macro-rewrite.md
  ├─ Requires: 002, 004, 005, 008
  ├─ Requires: All previous tasks
```

---

## Success Metrics by File

### 001-dependency-graph-builder.md
- ✅ Can analyze Phoenix's 500+ dependencies
- ✅ No circular dependency crashes
- ✅ Topological order is correct

### 002-complete-ast-analyzer.md
- ✅ 0% :unknown classifications (down from 15%)
- ✅ Can handle all Elixir constructs (maps, structs, protocols)
- ✅ 90% accuracy on Erlang modules

### 003-recursive-dependency-analysis.md
- ✅ No "unknown" due to analysis order
- ✅ Handles circular dependencies gracefully
- ✅ <1s incremental analysis

### 004-cps-transformation-completion.md
- ✅ All control flow constructs transform correctly
- ✅ Preserves semantics (test suite passes)
- ✅ Continuations properly threaded

### 005-runtime-beam-modifier.md
- ✅ Can modify user modules without crashes
- ✅ <5% performance overhead
- ✅ Rollback works correctly

### 006-module-cache-strategy.md
- ✅ Incremental updates work
- ✅ Invalidation is correct
- ✅ <500MB memory for large projects

### 007-source-discovery-system.md
- ✅ Finds all dependency sources
- ✅ Handles umbrella apps
- ✅ Handles Erlang projects

### 008-unknown-classification-elimination.md
- ✅ 0% :unknown classifications
- ✅ Conservative inference is safe
- ✅ Dynamic dispatch detected

### 009-captured-function-detection-fix.md
- ✅ `&IO.puts/1` is detected
- ✅ Captured functions blocked in pure blocks
- ✅ All capture forms handled

### 010-unified-pure-macro-rewrite.md
- ✅ 0 effects slip through (7 paths closed)
- ✅ Compile-time verification
- ✅ Runtime enforcement
- ✅ Clear error messages

---

## Implementation Priority

If resources are limited, implement in this priority order:

### Phase 1: Quick Wins (Week 1)
1. **Task 10** (009-captured-function-detection-fix.md) - Bug fix
2. **Task 4** (007-source-discovery-system.md) - Foundation
3. **Task 1** (001-dependency-graph-builder.md) - Foundation

### Phase 2: Core Infrastructure (Week 2-3)
4. **Task 5** (006-module-cache-strategy.md) - Performance
5. **Task 2 & 3** (003-recursive-dependency-analysis.md) - Core fix

### Phase 3: Analysis Enhancement (Week 4-5)
6. **Task 6** (002-complete-ast-analyzer.md) - Replace PURITY
7. **Task 7** (008-unknown-classification-elimination.md) - Eliminate unknowns

### Phase 4: Transformation & Integration (Week 6-8)
8. **Task 11** (004-cps-transformation-completion.md) - Complete CPS
9. **Task 14** (010-unified-pure-macro-rewrite.md) - Integration
10. **Task 13** (005-runtime-beam-modifier.md) - Optional (if Spike 1 succeeds)

---

**Total Tasks**: 15 main tasks + 4 technical spikes
**Total Files**: 10 implementation files
**Estimated Timeline**: 8 weeks
**Team Size**: 1-4 developers
