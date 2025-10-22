# Litmus Purity Enforcement - Objective Breakdown

This directory contains the detailed breakdown of the complete purity enforcement roadmap from OBJECTIVE.md, divided into 10 independent, implementable features.

## Overview

The goal is to achieve **complete purity enforcement** across project code and dependencies, eliminating all unknowns and preventing any effects from slipping through the `pure do...catch...end` construct.

**Current State**:
- ~15% functions marked :unknown
- 7 major effect leakage paths
- Incomplete dependency analysis
- Limited language construct support

**Target State**:
- 0% unknown classifications
- 0 effect leakage paths
- 100% dependency coverage
- Complete language support

## Objectives

### Foundation Phase (Weeks 1-2)

#### [001 - Dependency Graph Builder](001-dependency-graph-builder.md)
Build complete dependency graph for optimal analysis order.
- **Impact**: Reduces unknowns from ~15% to ~10%
- **Priority**: HIGH
- **Dependencies**: None

#### [006 - Module Cache Strategy](006-module-cache-strategy.md)
Per-module caching with incremental updates.
- **Impact**: 10x faster re-analysis
- **Priority**: HIGH
- **Dependencies**: 001

#### [007 - Source Discovery System](007-source-discovery-system.md)
Find all analyzable files across any project structure.
- **Impact**: 100% source coverage
- **Priority**: HIGH
- **Dependencies**: None

### Analysis Phase (Weeks 3-4)

#### [002 - Complete AST Analyzer](002-complete-ast-analyzer.md)
Replace PURITY with modern AST-based analyzer.
- **Impact**: Eliminates 40% of unknowns
- **Priority**: CRITICAL
- **Dependencies**: 001, 007

#### [003 - Recursive Dependency Analysis](003-recursive-dependency-analysis.md)
Automatically analyze dependencies on-demand.
- **Impact**: Reduces unknowns from ~10% to ~5%
- **Priority**: HIGH
- **Dependencies**: 001, 002

#### [008 - Unknown Classification Elimination](008-unknown-classification-elimination.md)
Conservative inference to eliminate remaining unknowns.
- **Impact**: Reduces unknowns from ~5% to <1%
- **Priority**: MEDIUM
- **Dependencies**: 002, 003

### Transformation Phase (Weeks 5-6)

#### [004 - CPS Transformation Completion](004-cps-transformation-completion.md)
Support all control flow constructs in effect macro.
- **Impact**: 100% language coverage for effects
- **Priority**: HIGH
- **Dependencies**: None (parallel work)

#### [009 - Captured Function Detection Fix](009-captured-function-detection-fix.md)
Fix bug allowing captured functions to bypass checks.
- **Impact**: Closes major effect leakage path
- **Priority**: CRITICAL
- **Dependencies**: None (bug fix)

### Integration Phase (Weeks 7-8)

#### [005 - Runtime BEAM Modifier](005-runtime-beam-modifier.md)
Modify dependency bytecode for runtime enforcement.
- **Impact**: 100% effect enforcement
- **Priority**: MEDIUM (risky)
- **Dependencies**: Spike required first

#### [010 - Unified Pure Macro Rewrite](010-unified-pure-macro-rewrite.md)
Complete rewrite integrating all improvements.
- **Impact**: Brings everything together
- **Priority**: CRITICAL
- **Dependencies**: All previous objectives

## Implementation Order

### Recommended Sequence

1. **Week 0**: Technical spikes (BEAM modification, protocol resolution)
2. **Week 1**: 001 (Dependency Graph) + 007 (Source Discovery)
3. **Week 2**: 006 (Cache Strategy) + 009 (Capture Fix - quick win)
4. **Week 3**: 002 (Complete AST Analyzer)
5. **Week 4**: 003 (Recursive Analysis) + 008 (Unknown Elimination)
6. **Week 5**: 004 (CPS Completion)
7. **Week 6**: Continue 004 + Start 005 (if spike successful)
8. **Week 7**: 010 (Unified Pure Macro)
9. **Week 8**: Integration testing and polish

### Parallel Tracks

These can be worked on independently:
- **Track A**: 001 → 003 → 006 (Analysis infrastructure)
- **Track B**: 004 (CPS transformation)
- **Track C**: 009 (Bug fix - immediate)

## Success Metrics

| Metric | Current | Target | Objective(s) |
|--------|---------|--------|--------------|
| Unknown classifications | ~15% | 0% | 002, 003, 008 |
| Effect leakage paths | 7 | 0 | 009, 010, 005 |
| Dependency coverage | 60% | 100% | 001, 007 |
| Language constructs | 70% | 100% | 004 |
| Re-analysis time | Minutes | Seconds | 006 |
| Source discovery | deps/*/lib/**/*.ex | All sources | 007 |

## Risk Assessment

### High Risk Items

1. **BEAM Modification (005)**: May not be feasible
   - **Mitigation**: Spike first, have fallback plan

2. **Performance Impact**: Analysis might be too slow
   - **Mitigation**: Parallel implementation, caching

3. **Breaking Changes**: Might break existing code
   - **Mitigation**: Feature flags, gradual rollout

### Critical Dependencies

- Objective 010 depends on most others
- Objectives 002 and 009 are critical path
- Objective 005 requires spike validation

## Quick Start

To begin implementation:

1. Read [OBJECTIVE.md](../OBJECTIVE.md) for full context
2. Run technical spikes (see objective 005)
3. Start with objective 009 (quick bug fix)
4. Implement objectives 001 and 007 in parallel
5. Follow recommended sequence above

## Status Tracking

| Objective | Status | Started | Completed | Notes |
|-----------|--------|---------|-----------|-------|
| 001 | Not Started | - | - | |
| 002 | Not Started | - | - | |
| 003 | Not Started | - | - | |
| 004 | Not Started | - | - | |
| 005 | Needs Spike | - | - | |
| 006 | Not Started | - | - | |
| 007 | Not Started | - | - | |
| 008 | Not Started | - | - | |
| 009 | Not Started | - | - | Critical bug |
| 010 | Not Started | - | - | |

## Notes

- Each objective file contains implementation details marked as TBD where more investigation is needed
- Objectives are designed to be as independent as possible
- Time estimates are conservative and assume single developer
- All objectives include comprehensive testing criteria