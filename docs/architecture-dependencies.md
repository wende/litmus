# Litmus Dependency Architecture

## Project Structure

```
┌─────────────────────────────────────────────────────┐
│                     LITMUS                          │
│          (Elixir Static Analyzer)                   │
│                                                     │
│  Purpose: Analyze purity & effects in Elixir code  │
└─────────────────────────────────────────────────────┘
                        │
                        │ uses
                        ▼
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌───────────────┐              ┌───────────────┐
│    PURITY     │              │     Jason     │
│  (Erlang lib) │              │ (Elixir lib)  │
├───────────────┤              ├───────────────┤
│ Location:     │              │ Location:     │
│ purity_source/│              │ deps/jason/   │
│               │              │               │
│ Files:        │              │ Files:        │
│ *.erl         │              │ *.ex          │
│ (Erlang)      │              │ (Elixir)      │
│               │              │               │
│ Purpose:      │              │ Purpose:      │
│ Analyze BEAM  │              │ JSON encode/  │
│ bytecode      │              │ decode        │
│               │              │               │
│ Usage:        │              │ Usage:        │
│ Tool/Library  │              │ Caching/      │
│ (internal)    │              │ Serialization │
└───────────────┘              └───────────────┘
       │                              │
       │                              │
       ▼                              ▼
  NOT analyzed                   ✅ ANALYZED
  (Erlang code,                  (Elixir code,
   no .ex files)                  has .ex files)
```

## Dependency Types

### 1. PURITY - The Underlying Analyzer

**Type**: Tool/Library dependency
**Language**: Erlang
**Location**: `purity_source/` (path dependency)
**File types**: `.erl` (Erlang source)

**Relationship**:
- Litmus **uses** PURITY to analyze compiled BEAM bytecode
- PURITY is a **tool**, not a library Litmus calls from user code
- Originally from 2011 paper: "Purity in Erlang" (Pitidis & Sagonas)
- Forked and extended by Litmus maintainers

**Analysis**:
- ❌ **NOT analyzed** by Litmus dependency analysis
- Why: Erlang code, no `.ex` files to analyze
- Lives in `purity_source/`, not `deps/`

**Example usage in Litmus**:
```elixir
# Litmus calls PURITY to analyze BEAM files
:purity.analyze_module(:lists)  # Erlang function call
```

### 2. Jason - JSON Library

**Type**: Runtime dependency
**Language**: Elixir
**Location**: `deps/jason/` (Hex package)
**File types**: `.ex` (Elixir source)

**Relationship**:
- Litmus **uses** Jason for JSON serialization
- Used for caching effect data (`.effects/*.json`)
- Standard Elixir JSON library

**Analysis**:
- ✅ **IS analyzed** by Litmus dependency analysis
- Why: Has `.ex` source files in `deps/jason/lib/`
- Effects are cached for user code that calls Jason

**Example usage in Litmus**:
```elixir
# Litmus uses Jason for caching
Jason.encode!(effects_map)

# User code can also call Jason
def my_function(data) do
  Jason.encode!(data)  # Effect is resolved from cache!
end
```

## Dependency Analysis Flow

```
┌──────────────────────────────────────────────────────┐
│ 1. mix effect lib/my_module.ex                       │
└──────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│ 2. Calculate dependency checksum                     │
│    Includes: litmus version + all dependency versions│
│    data = "litmus:0.1.0,jason:1.4.4,purity:0.2,..."  │
│    checksum = hash(data) → "438705C"                 │
└──────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│ 3. Discover dependency source files                  │
│    Looks for: deps/*/lib/**/*.ex                     │
│    Finds: Jason ✅                                    │
│    Skips: PURITY ❌ (no .ex files)                    │
└──────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│ 4. Analyze Jason source files                        │
│    Analyzing 10 dependency source files...           │
│    Cached 34 dependency functions                    │
│    Result: Jason.encode!/2 → "s" (side effect)       │
└──────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│ 5. Save to .effects/deps.cache                       │
│    {                                                  │
│      "Jason.encode!/2": "s",                         │
│      "Jason.decode!/2": "s",                         │
│      ...                                              │
│    }                                                  │
└──────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│ 6. Analyze user code with full cache                 │
│    User calls Jason.encode! → Resolves to "s" ✅     │
└──────────────────────────────────────────────────────┘
```

## Why Two Different Tools?

### PURITY (Erlang)
- **Purpose**: Analyze **compiled BEAM bytecode**
- **Input**: `.beam` files (compiled Erlang/Elixir)
- **Output**: Purity classification (pure/impure)
- **Use case**: When source code unavailable or for Erlang modules
- **Limitation**: Cannot analyze Elixir-specific features (macros, protocols)

### Litmus AST Walker (Elixir)
- **Purpose**: Analyze **Elixir source code**
- **Input**: `.ex` files (Elixir AST)
- **Output**: Full effect types (pure, side effects, lambda, exceptions)
- **Use case**: Analyzing Elixir projects and dependencies with source
- **Advantage**: Understands Elixir semantics, closures, pattern matching

## Complementary Approach

Litmus uses **both** approaches:

```
Elixir source available?
│
├─ YES → Use AST Walker (Litmus.Analyzer.ASTWalker)
│         ├─ Analyze source directly
│         ├─ Track exception types
│         ├─ Handle closures
│         └─ Full effect inference
│
└─ NO  → Use PURITY (via :purity module)
          ├─ Extract abstract code from .beam
          ├─ Analyze bytecode
          ├─ Basic purity classification
          └─ Fallback for compiled-only code
```

## Future: Phase 3 Integration

In **Phase 3**, we'll combine both:

```elixir
# Analyze with priority
case analyze_module(MyModule) do
  # 1. Try source analysis first (best)
  {:ok, source_analysis} -> source_analysis

  # 2. Fall back to BEAM bytecode (good)
  {:no_source, beam_file} ->
    purity_analysis = :purity.analyze_beam(beam_file)

  # 3. Fall back to registry (okay)
  {:no_beam} ->
    Registry.lookup(MyModule)

  # 4. Unknown (conservative)
  _ -> :unknown
end
```

This gives us **maximum coverage**:
- ✅ Elixir deps with source → Full analysis
- ✅ Compiled deps without source → PURITY analysis
- ✅ Erlang stdlib → PURITY analysis
- ✅ Unknown → Conservative assumption

## Summary

| Tool | Language | Analyzes | Input | Output | Current Status |
|------|----------|----------|-------|--------|----------------|
| **Litmus AST Walker** | Elixir | Source code | `.ex` files | Full effects | ✅ Implemented |
| **PURITY** | Erlang | Bytecode | `.beam` files | Basic purity | ✅ Integrated (Phase 1) |
| **Combined** | Both | Source + bytecode | Both | Best available | ⏳ Planned (Phase 3) |

**Current implementation**: Litmus uses AST walker for Elixir source, PURITY available but not yet in main workflow.

**Future**: Seamless fallback from source → bytecode → registry → unknown.
