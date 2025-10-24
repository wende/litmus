# CLAUDE.md - Litmus Project Context

> **Purpose**: This document provides comprehensive context about the Litmus project for AI assistants and developers working with the codebase.

**Last Updated**: 2025-10-21
**Project Version**: v0.1.0

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Core Concepts](#core-concepts)
3. [Architecture](#architecture)
4. [Four Main Features](#four-main-features)
5. [Type and Effect System](#type-and-effect-system)
6. [Implementation Status](#implementation-status)
7. [Usage Guide](#usage-guide)
8. [Development Guidelines](#development-guidelines)
9. [Technical Background](#technical-background)
10. [Known Limitations](#known-limitations)

---

## Project Overview

Litmus is a comprehensive static analysis tool for Elixir that provides **four powerful capabilities**:

1. **Purity Analysis** - Classifies functions as pure or impure by analyzing BEAM bytecode
2. **Exception Tracking** - Tracks which exceptions each function may raise
3. **Algebraic Effects** - Mock and intercept side effects for testing using compile-time CPS transformation
4. **Bidirectional Type Inference** - Infers effect types directly from Elixir source code with lambda effect propagation

### Key Statistics

- **87.30%** of Elixir stdlib functions are pure
- **3,243** stdlib functions analyzed
- **134** modules in stdlib coverage
- **10** Kernel functions with specific exception types tracked

### Theoretical Foundation

Built on academic research and practical implementations:
- PURITY static analyzer (Pitidis & Sagonas, 2011) - BEAM bytecode analysis
- Row-polymorphic effects (Leijen, Koka) - Principal type inference
- Bidirectional typing (Dunfield & Krishnaswami, 2013) - Higher-rank polymorphism
- Gradual effects (Bañados Schwerter et al., 2014) - Incremental adoption for dynamic languages

---

## Core Concepts

### What is Purity Analysis?

Purity analysis determines whether functions are **referentially transparent** (pure) or have **side effects** (impure).

**Pure functions**:
- Always return the same output for the same input
- Have no observable side effects (no I/O, no state mutations, no process operations)
- Can be safely optimized, memoized, and parallelized

**Example**:
```elixir
# Pure - always returns same result for same input
def add(x, y), do: x + y

# Impure - performs I/O side effect
def log(msg), do: IO.puts(msg)

# Impure - depends on external state
def current_time(), do: DateTime.utc_now()
```

### Effect Types Reference

Litmus uses a standardized set of **effect types** stored in `.effects.json`:

| Type | Name | Description | Examples |
|------|------|-------------|----------|
| **`"p"`** | Pure | Referentially transparent, no side effects | `String.upcase/1`, `+/2` |
| **`"d"`** | Dependent | Depends on execution environment/context | `node/0`, `self/0`, `System.system_time/0` |
| **`"n"`** | NIF | Native code, behavior unknown | `:crypto` functions |
| **`"s"`** | Stateful | Writes/modifies state | `File.write!/2`, `IO.puts/1`, `send/2` |
| **`"l"`** | Lambda | May inherit effects from passed functions | `Enum.map/2` (higher-order) |
| **`"u"`** | Unknown | Cannot be analyzed | Dynamic dispatch, missing debug_info |
| **`{"e", [...]}`** | Exceptions | May raise specific exceptions | `{"e", ["Elixir.ArgumentError"]}` |

### Analysis Result Levels

When analyzing compiled modules, Litmus returns these **analysis result levels**:

- **`:pure`** - Referentially transparent, no side effects, no exceptions
- **`:exceptions`** - Side-effect free but may raise exceptions
- **`:lambda`** - Side-effect free but may inherit effects from passed functions
- **`:dependent`** - Side-effect free but depends on execution environment
- **`:nif`** - Native code (behavior unknown, conservative assumption)
- **`:side_effects`** - Has observable side effects (I/O, process operations, etc.)
- **`:unknown`** - Cannot be analyzed (dynamic dispatch, missing debug_info)

### Exception Model

Elixir/Erlang has **three exception classes**:

1. **`:error`** - Typed exceptions with module names (ArgumentError, KeyError, etc.)
2. **`:throw`** - Untyped control flow mechanism (early returns)
3. **`:exit`** - Process termination signals

All are caught with try/catch:
```elixir
try do
  code()
catch
  :error, exception -> # catches raises (typed)
  :throw, value -> # catches throws (untyped)
  :exit, reason -> # catches exits
end
```

---

## Architecture

### Project Structure

```
litmus/
├── lib/
│   ├── litmus.ex                    # Main API wrapper
│   ├── litmus/
│   │   ├── exceptions.ex            # Exception tracking
│   │   ├── pure.ex                  # Compile-time purity enforcement
│   │   ├── stdlib.ex                # Curated pure function whitelist
│   │   ├── types/                   # Type system
│   │   │   ├── core.ex             # Type and effect definitions
│   │   │   ├── effects.ex          # Effect operations and row polymorphism
│   │   │   ├── unification.ex      # Type unification algorithm
│   │   │   └── substitution.ex     # Variable substitution
│   │   ├── inference/              # Bidirectional type checking
│   │   │   ├── bidirectional.ex    # Synthesis (⇒) and checking (⇐) modes
│   │   │   └── context.ex          # Type context and environment
│   │   ├── analyzer/               # AST analysis
│   │   │   ├── ast_walker.ex       # Main AST analysis engine
│   │   │   └── effect_tracker.ex   # Effect tracking utilities
│   │   ├── effects/                # Algebraic effects system
│   │   │   ├── effects.ex          # Main effect macro and handler API
│   │   │   ├── transformer.ex      # CPS transformation engine
│   │   │   ├── registry.ex         # Effect categorization
│   │   │   └── unhandled_error.ex  # Exception for unhandled effects
│   │   └── registry/
│   │       └── builder.ex          # Effect registry builder
│   └── mix/tasks/
│       ├── effect.ex                # `mix effect` command
│       └── generate_effects.ex     # Generate effect cache
├── purity_source/                   # PURITY Erlang analyzer (forked)
├── test/                            # Comprehensive test suite
├── docs/                            # Documentation
└── .effects.json                    # Stdlib effect registry

```

### Core Components

#### 1. PURITY Library Integration (`purity_source/`)
- Forked Erlang static analyzer from 2011
- Analyzes BEAM bytecode (Core Erlang)
- Extended with type fixes and map support
- Provides foundation for purity analysis

#### 2. Type System (`lib/litmus/types/`)
- **`core.ex`**: Type and effect definitions (`:p`, `:s`, `:l`, `:d`, `:u`, `:n`)
- **`effects.ex`**: Effect operations and row-polymorphic handling
- **`unification.ex`**: Type unification for type inference
- **`substitution.ex`**: Variable substitution and composition

#### 3. Bidirectional Inference (`lib/litmus/inference/`)
- **`bidirectional.ex`**: Synthesis (⇒) and checking (⇐) modes
- **`context.ex`**: Type context and environment management
- Handles higher-rank polymorphism
- Enables lambda effect propagation

#### 4. AST Analyzer (`lib/litmus/analyzer/`)
- **`ast_walker.ex`**: Walks AST and infers effect types
- **`effect_tracker.ex`**: Tracks effects and function calls in expressions
- Analyzes Elixir source code directly (no BEAM required)
- Cross-module analysis with caching

#### 5. Algebraic Effects (`lib/litmus/effects/`)
- **`effects.ex`**: Main effect macro and handler API
- **`transformer.ex`**: CPS transformation engine for AST
- **`registry.ex`**: Effect categorization and tracking
- Enables mocking side effects for testing

#### 6. Mix Tasks (`lib/mix/tasks/`)
- **`effect.ex`**: `mix effect` command for analyzing source files
- **`generate_effects.ex`**: Generates effect cache for dependencies
- JSON and verbose output modes
- IDE integration support

---

## Four Main Features

### 1. Purity Analysis

**Analyze BEAM bytecode to determine if functions are pure or have side effects.**

```elixir
# Analyze a single module
{:ok, results} = Litmus.analyze_module(:lists)

# Check if a function is pure
Litmus.pure?(results, {:lists, :reverse, 1})  #=> true

# Get detailed purity level
{:ok, level} = Litmus.get_purity(results, {:lists, :map, 2})
#=> {:ok, :pure}

# Analyze multiple modules in parallel
{:ok, results} = Litmus.analyze_parallel([:lists, :string, :maps])
```

**Elixir Standard Library Whitelist**:
```elixir
Litmus.pure_stdlib?({Enum, :map, 2})     #=> true
Litmus.pure_stdlib?({String, :upcase, 1}) #=> true
Litmus.pure_stdlib?({IO, :puts, 1})       #=> false
```

**Compile-Time Enforcement**:
```elixir
import Litmus.Pure

# ✅ This compiles successfully
result = pure do
  [1, 2, 3]
  |> Enum.map(&(&1 * 2))
  |> Enum.filter(&(&1 > 5))
  |> Enum.sum()
end

# ❌ This fails at compile time
pure do
  IO.puts("Hello")  # Compilation error!
end
```

### 2. Exception Tracking

**Track which exceptions each function may raise, independently from purity analysis.**

**Status**: ✅ **Specific exception type tracking implemented** in bidirectional inference system.

**Exception Types**:
- **Typed exceptions** (`:error` class) - ArgumentError, KeyError, etc. (✅ tracked)
- **Untyped exceptions** (`:throw`/`:exit` classes) - Arbitrary values (planned)
- **Dynamic exceptions** (`:dynamic`) - Type cannot be determined statically (✅ tracked)

**Current Implementation (AST-based)**:
```elixir
# Analyze source code with mix effect
$ mix effect lib/my_module.ex

# Or programmatically
{:ok, result} = Litmus.Analyzer.ASTWalker.analyze_file("lib/my_module.ex")

# Check exception types for a function
func = result.functions[{MyModule, :validate!, 1}]
func.effect
#=> {:e, ["Elixir.ArgumentError"]}

# Extract exception types
Litmus.Types.Effects.extract_exception_types(func.effect)
#=> ["Elixir.ArgumentError"]
```

**Examples**:
```elixir
# Specific exception type
def validate!(data) do
  raise ArgumentError, "invalid data"
end
# Effect: {:e, ["Elixir.ArgumentError"]}

# Multiple exception types
def process!(data) do
  if invalid?(data) do
    raise ArgumentError, "invalid"
  else
    raise KeyError, key: :missing
  end
end
# Effect: {:e, ["Elixir.ArgumentError", "Elixir.KeyError"]}

# Dynamic exception (runtime-determined)
def handle!(error) do
  raise error
end
# Effect: {:e, [:dynamic]}

# String raise (defaults to RuntimeError)
def fail!(msg) do
  raise msg
end
# Effect: {:e, ["Elixir.RuntimeError"]}
```

**Planned (BEAM bytecode analysis)**:
```elixir
# Analyze exceptions for compiled modules
{:ok, exceptions} = Litmus.analyze_exceptions(MyModule)

# Check if a function can raise a specific exception
Litmus.can_raise?(exceptions, {MyModule, :parse, 1}, ArgumentError)
#=> true

# Get detailed exception information
{:ok, info} = Litmus.get_exceptions(exceptions, {MyModule, :parse, 1})
#=> {:ok, %{
#=>   errors: MapSet.new([ArgumentError, KeyError]),
#=>   non_errors: false
#=> }}
```

**Exception Policies**:
```elixir
# Allow specific exceptions in pure code
pure allow_exceptions: [ArgumentError, KeyError] do
  Map.fetch!(data, :key) |> String.to_integer!()
end

# Allow any exceptions but forbid I/O
pure allow_exceptions: :any do
  Integer.parse!(user_input)
end

# Forbid all exceptions (default)
pure allow_exceptions: :none do
  Enum.sum([1, 2, 3])  # ✅ Safe
end
```

### 3. Algebraic Effects System

**Mock and intercept side effects for testing using CPS transformation at compile time.**

```elixir
import Litmus.Effects

# Test file operations without touching the filesystem
result = effect do
  content = File.read!("config.json")
  parsed = Jason.decode!(content)
  File.write!("output.txt", parsed["result"])
  :ok
catch
  {File, :read!, ["config.json"]} -> ~s({"result": "test data"})
  {File, :write!, ["output.txt", "test data"]} -> :ok
end

assert result == :ok
```

**How It Works**:
The `effect` macro transforms your code using continuation-passing style (CPS):

```elixir
# You write:
effect do
  x = File.read!("a.txt")
  y = String.upcase(x)
  File.write!("b.txt", y)
catch
  {File, :read!, _} -> "mocked"
end

# It transforms to (conceptually):
handler.({File, :read!, ["a.txt"]}, fn x ->
  y = String.upcase(x)  # Pure code runs normally
  handler.({File, :write!, ["b.txt", y]}, fn result -> result end)
end)
```

**Key Features**:
- Control flow with effects (if/else)
- Variable capture in handlers
- Zero runtime overhead (compile-time transformation)

### 4. Bidirectional Type Inference

**Analyze Elixir source code directly to infer effect types with lambda effect propagation.**

**Key Capabilities**:
- Analyzes AST directly (no BEAM bytecode required)
- Infers effect types for user-defined functions
- **Lambda effect propagation** - Correctly tracks how effects flow through higher-order functions
- **Cross-module analysis** - Understands effects across your entire application
- **Compile-time integration** - Results available during compilation

**Basic Usage**:
```elixir
alias Litmus.Analyzer.ASTWalker
alias Litmus.Types.Core

# Analyze a source file
{:ok, source} = File.read("lib/my_module.ex")
{:ok, ast} = Code.string_to_quoted(source)
{:ok, result} = ASTWalker.analyze_ast(ast)

# Get effect information for a function
mfa = {MyModule, :process, 1}
func_analysis = result.functions[mfa]

# Check effect type (compact notation: :p, :s, :l, :d, :u)
effect_type = Core.to_compact_effect(func_analysis.effect)
```

**Lambda Effect Propagation**:
```elixir
# Pure function with pure lambda - result is pure (:p)
pure_map = Enum.map([1, 2, 3], fn x -> x * 2 end)

# Pure function with effectful lambda - result is effectful (:s)
effectful_map = Enum.map([1, 2, 3], fn x ->
  IO.puts(x)  # Side effect
  x * 2
end)

# Lambda-dependent function - caller determines effects
def process_items(items, processor) do
  Enum.map(items, processor)  # Effect depends on what processor does
end
```

**Mix Task**:
```bash
# Analyze a single file
mix effect lib/my_module.ex

# Verbose output with types
mix effect lib/my_module.ex --verbose

# Include exception information
mix effect lib/my_module.ex --exceptions

# JSON output for tooling
mix effect lib/my_module.ex --json

# Include PURITY bytecode analysis
mix effect lib/my_module.ex --purity
```

---

## Type and Effect System

### Row-Polymorphic Effects

The system uses **row polymorphism with duplicate labels**, following Koka's approach:

```elixir
# Side effects with specific MFAs
{:s, ["File.read/1"]}  # ⟨s(File.read/1)⟩

# Effect row with exception and side effects
{:effect_row, {:e, ["Elixir.ArgumentError"]}, {:s, ["File.read/1"]}}  # ⟨e(ArgumentError) | s(File.read/1)⟩

# Duplicate labels for nested handlers
{:effect_row, :exn, {:effect_row, :exn, {:effect_empty}}}  # ⟨exn | exn⟩
```

**Why duplicate labels?**
Duplicate labels enable proper handling of nested effect contexts:

```elixir
try do
  try do
    dangerous_operation()  # Can throw
  catch
    :inner -> handle_inner()  # Can also throw
  end
catch
  :outer -> handle_outer()  # Removes outer exception effect
end
```

### Bidirectional Type Inference

The system uses **two complementary modes**:

**Synthesis Mode (⇒)** - Infers types from expressions:
```elixir
# Synthesizes: Int × ⟨⟩ Int
def add(x, y) do
  x + y
end
```

**Checking Mode (⇐)** - Verifies against expected types:
```elixir
# Checks: λx. x + 1 against Int → ⟨⟩ Int
fn x -> x + 1 end : (Int -> Int)
```

### Gradual Effects

**Unknown effects (¿)** enable incremental adoption:

```elixir
# Unannotated function gets unknown effect
def legacy_function(x) do
  some_complex_logic(x)  # Effect: ¿
end

# Can call from annotated code with runtime checks
def new_function(x) do
  result = legacy_function(x)  # Runtime check inserted
  process_pure(result)
end
```

### Closure Types

**Closures** represent functions returned from other functions, with tracked captured and return effects:

```elixir
# Closure type: {:closure, param_type, captured_effect, return_effect}
# Where:
# - param_type: Type of parameters when called
# - captured_effect: Effects from variables captured in outer scope
# - return_effect: Effects when the closure is called

def make_logger(target) do
  # Returns a closure that captures 'target'
  fn message -> IO.puts("#{target}: #{message}") end
end

# Analyzing this function:
# - Captured effect: empty (target is pure data)
# - Return effect: side effects from IO.puts/1
# - Closure type: {:closure, :string, {:effect_empty}, {:s, ["IO.puts/1"]}}

# When the closure is called:
logger = make_logger("MyApp")
logger.("Hello")  # Knows this has side effects
```

**Key Differences from Function Types**:
- **Function types** `{:function, arg, effect, return}`: effect = what happens when called
- **Closure types** `{:closure, arg, captured, return}`: captured = from outer scope, return = when called

This enables proper tracking of effects through higher-order functions and functional composition patterns.

### Pattern Matching in All Contexts

**Full pattern matching support** enables destructuring in lambdas, case expressions, and function definitions:

**Lambda Pattern Matching**:
```elixir
# Tuple destructuring
Enum.map([{1, 2}, {3, 4}], fn {a, b} -> a + b end)

# List destructuring
Enum.map([[1, 2], [3, 4]], fn [h|t] -> h end)

# Map destructuring
Enum.map([%{x: 1, y: 2}], fn %{x: val} -> val end)

# Multi-clause lambdas
f = fn
  0 -> :zero
  n -> n * 2
end
```

**Case Expression Pattern Matching**:
```elixir
case data do
  {a, b} when a > 0 -> a + b        # Tuple with guard
  [h|t] -> h                         # List head|tail
  %{key: value} -> value             # Map extraction
  _ -> :default
end
```

**Function Definition Pattern Matching**:
```elixir
# Tuple patterns
def process({:ok, value}) do
  value
end

def process({:error, msg}) do
  msg
end

# List recursion with patterns
def sum([]) do
  0
end

def sum([h|t]) do
  h + sum(t)
end

# Mixed patterns and simple parameters
def combine({a, b}, x, [h|_t]) do
  a + b + x + h
end

# Guards with pattern variables
def check({x, y}) when x + y > 0 do
  :positive
end
```

**Key Features**:
- ✅ Variables bound in patterns are available in body expressions
- ✅ Nested patterns (tuples, lists, maps) work correctly
- ✅ Multi-clause functions with different patterns
- ✅ Guard expressions with pattern variable references
- ✅ Type inference for pattern-bound variables
- ✅ Full integration with effect tracking

### Unification Algorithm

Extended Robinson's algorithm with effect row unification:
- Type unification with occurs checking
- Effect row unification with unique solutions
- Support for higher-rank polymorphism
- O(n log n) complexity with union-find optimizations

---

## Implementation Status

### ✅ Completed Features

- [x] **Litmus.Stdlib** - Whitelist-based purity classifications
- [x] **Litmus.Pure** - `pure do...end` macro for compile-time enforcement
- [x] **Litmus.Exceptions** - Exception tracking with propagation
- [x] **Exception policies** - Fine-grained `allow_exceptions` control
- [x] **:dynamic vs :unknown** - Semantic distinction for analysis failures
- [x] **Litmus.Effects** - Algebraic effects with CPS transformation
- [x] **Effect handlers** - Mock and intercept side effects
- [x] **Control flow transformation** - `if/else` expressions with effects
- [x] **Bidirectional type inference** - Effect types from source code
- [x] **Lambda effect propagation** - Higher-order function support
- [x] **Mix task** - `mix effect` command with cross-module tracking
- [x] **Termination analysis** - Detects non-terminating functions
- [x] **Specific exception tracking** - Tracks specific exception types (ArgumentError, KeyError, etc.)
- [x] **Wildcard effect classification** - Module-level effect annotations in `.effects.explicit.json`
- [x] **Multi-effect extraction** - Functions can have multiple simultaneous effect types tracked (PDR 001/002)
- [x] **Conservative severity ordering** - Safety-first precedence: Unknown > NIF > Side > Dependent > Exception > Lambda > Pure
- [x] **Closure type system** - Closure types with captured and return effects (PDR 006)
- [x] **Closure application handling** - Proper effect tracking when closures are called
- [x] **Nested closure tracking** - Functions returning functions with effects
- [x] **Pattern matching in lambdas** - Tuple, list, map, struct destructuring in lambda parameters
- [x] **Pattern matching in case expressions** - Full pattern support with variable binding
- [x] **Pattern matching in function definitions** - Pattern destructuring in function heads
- [x] **Multi-clause lambdas** - Support for lambdas with multiple clauses
- [x] **Guard expression analysis** - Infrastructure for analyzing guard effects and exceptions

### 🔄 In Progress

- [ ] **Guard exception tracking** - Full exception tracking through guard expressions
- [ ] **Advanced effect features** - `case`, `cond`, `with` in effect macro

### ⏳ Planned

- [ ] **Litmus.PLT** - Persistent Lookup Table for caching results
- [ ] **Litmus.Results** - Pretty-printing and HTML/JSON reports
- [ ] **ExUnit integration** - Purity and exception assertions in tests
- [ ] **@pure annotations** - Optional developer annotations for verification
- [ ] **Update PURITY** - Support modern Erlang features (maps, etc.)
- [ ] **IDE integration** - LSP server with inline purity/exception information

### Test Status

**Current**: ✅ **801 tests passing (100%)**

**Coverage**:
- Unit tests: 23 passing (ExUnit)
- Pattern matching tests: 48 dedicated tests
- Lambda pattern tests: 20 dedicated tests
- Function definition pattern tests: 21 dedicated tests
- Effect analysis: 94+ functions analyzed across multiple test files
- Exception edge cases: 40+ functions, 31 comprehensive tests
- Lambda exception propagation: 4 dedicated tests
- Closure tracking tests: 9 dedicated tests
- Bugs fixed and verified: 10+ major bugs
- Test files: `test/analyzer/ast_walker_test.exs`, `test/analyzer/function_pattern_test.exs`, `test/infer/*.exs`, `test/support/*.exs`

---

## Usage Guide

### Installation

Add to `mix.exs`:
```elixir
def deps do
  [
    {:litmus, github: "wende/litmus", tag: "v0.1.0"}
  ]
end
```

### Analyzing Modules

```elixir
# Analyze for purity
{:ok, results} = Litmus.analyze_module(:lists)
Litmus.pure?(results, {:lists, :reverse, 1})  #=> true

# Analyze for exceptions
{:ok, exceptions} = Litmus.analyze_exceptions(String)
Litmus.can_raise?(exceptions, {String, :to_integer, 1}, ArgumentError)
#=> true

# Combined analysis
{:ok, results} = Litmus.analyze_with_exceptions(MyModule)
```

### Using the Pure Macro

```elixir
import Litmus.Pure

# Basic purity enforcement
result = pure do
  [1, 2, 3]
  |> Enum.map(&(&1 * 2))
  |> Enum.sum()
end

# With exception policy
result = pure allow_exceptions: [ArgumentError] do
  Map.fetch!(data, :key) |> String.to_integer!()
end

# With termination requirement
result = pure require_termination: true do
  Enum.map([1, 2, 3], &(&1 * 2))  # ✅ Terminates
end
```

### Using Effect Handlers

```elixir
import Litmus.Effects

# Define effectful code
eff = effect do
  config = File.read!("config.json")
  data = Jason.decode!(config)
  File.write!("output.txt", data["result"])
end

# Test with mocks
Effects.run(eff, fn
  {File, :read!, ["config.json"]} ->
    ~s({"result": "test data"})
  {File, :write!, ["output.txt", data]} ->
    assert data == "test data"
    :ok
end)

# Production with passthrough
Effects.run(eff, :passthrough)
```

### Using Mix Effect Task

```bash
# Basic analysis
mix effect lib/my_module.ex

# With verbose type information
mix effect lib/my_module.ex --verbose

# JSON output for tooling
mix effect lib/my_module.ex --json > analysis.json

# Include exceptions
mix effect lib/my_module.ex --exceptions

# Full analysis
mix effect lib/my_module.ex --purity --exceptions --verbose
```

### Interpreting Effect Output

```
═══════════════════════════════════════════════════════════
Module: MyModule
═══════════════════════════════════════════════════════════

process_data/1
  ───────────────────────────────────────────────────────
  ⚡ Effectful
  Effects: ⟨file | io⟩
    Detected effects:
      • file: File system operations
      • io: Input/output operations
  Calls:
    ⚡ Elixir.File.read!/1
    ⚡ Elixir.IO.puts/1
    → Elixir.String.upcase/1

Summary: 1 function analyzed
  ✓ Pure: 0
  ⚡ Effectful: 1
```

**Indicators**:
- **✓** Pure call
- **λ** Lambda-dependent call
- **⚡** Effectful call
- **⚠** Exception call
- **?** Unknown call

---

## Development Guidelines

### Adding New Stdlib Functions to Registry

**Registry File Structure**:
- **`.effects/bottommost.json`** - Auto-generated with heuristic classification (don't edit)
- **`.effects.explicit.json`** - Manual human-reviewed classifications (edit this!)
- **`.effects/std.json`** - Final merged registry (auto-generated via `mix litmus.merge_explicit`)

**Workflow**:

1. **Locate the function**: Determine module, function, arity
2. **Classify effect**: Determine effect type (p, s, l, d, u, n, e)
3. **Update `.effects.explicit.json`** (two syntaxes):

   **Individual functions**:
   ```json
   {
     "Elixir.MyModule": {
       "my_function/2": "p",
       "other_function/1": "s"
     }
   }
   ```

   **Module-level wildcard** (all functions have same effect):
   ```json
   {
     "Elixir.IO.ANSI": "*p"
   }
   ```

   **Wildcard with overrides** (most functions same, some different):
   ```json
   {
     "Elixir.Macro": {
       "*": "p",
       "unique_var/2": "d"
     }
   }
   ```

4. **Regenerate merged registry**:
   ```bash
   mix litmus.merge_explicit
   ```

5. **Test**: Add test case verifying correct classification
6. **Document**: Update documentation if adding new effect category

**When to use wildcards**:
- Pure utility modules (escape codes, formatting functions)
- Exception struct modules (all `__struct__/0`, `message/1` functions are pure)
- Modules where most/all functions share the same effect type

### Effect Type Guidelines

- **`"p"` (Pure)**: No side effects, deterministic, referentially transparent
- **`"s"` (Side effects)**: Performs I/O, modifies state, spawns processes
- **`"l"` (Lambda)**: Higher-order function inheriting effects from arguments
- **`"d"` (Dependent)**: Reads from environment (time, process dict, ETS, node info)
- **`"u"` (Unknown)**: Dynamic dispatch, cannot be analyzed statically
- **`"n"` (NIF)**: Native code, conservative assumption
- **`{"e", [modules]}`**: Raises specific exception modules

### Testing New Features

```bash
# Run all tests
mix test

# Run specific test file
mix test test/analyzer/ast_walker_test.exs

# Test effect inference
mix effect test/infer/edge_cases_test.exs

# Run with trace
mix test --trace
```

### Code Organization

**When adding new functionality**:
1. **Types first**: Update `lib/litmus/types/` if changing type system
2. **Inference next**: Update `lib/litmus/inference/` for type checking changes
3. **Analysis**: Update `lib/litmus/analyzer/` for AST walking
4. **API last**: Update `lib/litmus.ex` for public API changes
5. **Tests always**: Add tests for all new functionality

### Documentation Standards

All public functions must have:
- `@doc` with clear description
- `@spec` with type signature
- Examples showing usage
- Notes about limitations or edge cases

### Commit Message Guidelines

**IMPORTANT**: Never include these lines in commit messages:
```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

These attribution lines should be omitted from all commits in this project.

---

## Technical Background

### Theoretical Foundations

**Row Polymorphism** (Leijen, 2014):
- Enables principal type inference
- Duplicate labels for proper nesting
- Unique solutions to effect constraints

**Bidirectional Typing** (Dunfield & Krishnaswami, 2013):
- Mode-directed type checking
- Handles higher-rank polymorphism
- Better error locality

**Gradual Effects** (Bañados Schwerter et al., 2014):
- Unknown effect ¿ for unannotated code
- Pay-as-you-go runtime checking
- Incremental adoption path

**BEAM-Specific Design**:
- Message passing as session effects
- OTP behaviors as effect handlers
- Process isolation boundaries

### Key Research Papers

1. **"Purity in Erlang"** (Pitidis & Sagonas, 2011)
   - PURITY analyzer for BEAM bytecode
   - Conservative static analysis
   - Call graph construction and fixed-point iteration

2. **"Koka: Programming with Row-Polymorphic Effects"** (Leijen, 2014)
   - Row-polymorphic effect system
   - Duplicate labels for effect handlers
   - Efficient compilation to C

3. **"Complete and Easy Bidirectional Typechecking"** (Dunfield & Krishnaswami, 2013)
   - Bidirectional type inference algorithm
   - Higher-rank polymorphism support
   - Proof-theoretic foundations

4. **"Gradual Type-and-Effect Systems"** (Bañados Schwerter et al., 2014)
   - Unknown effects for dynamic languages
   - Runtime checking at boundaries
   - Pay-as-you-go semantics

### Implementation Insights

**Why CPS for Effects?**
- BEAM-friendly (no special continuation support needed)
- Compile-time transformation (zero runtime overhead)
- True algebraic effects (handlers can manipulate continuations)
- Composable (effects and handlers compose naturally)

**Why Bidirectional Typing?**
- Handles higher-rank polymorphism decidably
- Better error messages (local inference)
- Enables checking mode for annotations
- Synthesis mode for inference

**Why Row Polymorphism?**
- Principal type inference (unique most general types)
- Proper nested handler support
- Efficient unification algorithm
- Natural composition of effects

---

## Known Limitations

### 1. PURITY Version Compatibility

PURITY was developed in 2011 for Erlang R14:
- **Map literals** (added R17/2014) not supported by PURITY bytecode analyzer
- **`:maps` module functions** - Whitelisted in `.effects.explicit.json` (manually classified as pure)
- **NIF stubs** - Functions using `erlang:nif_error/1` require explicit whitelist entries
- **Modern Elixir code** with maps can be analyzed via bidirectional inference (AST-based)
- **Pre-R17 Erlang stdlib modules** work perfectly with PURITY

### 2. Dynamic Language Features

Static analysis cannot handle:
- **Dynamic dispatch** - `apply/3`, module variables
- **Dynamic exceptions** - `raise variable` marked as `:dynamic`
- **Metaprogramming** - Macros generate different code in different contexts
- **NIFs** - Native code is a black box
- **Process message passing** - Cross-process effects invisible
- **Hot code loading** - Multiple function versions may exist

### 3. Conservative Approximations

PURITY and exception tracking use conservative analysis:
- **False negatives** - Some pure functions marked impure
- **Over-reporting exceptions** - Dynamic raises marked `:dynamic`
- **Try/catch blocks** - Caught exceptions still reported (conservative)
- **Higher-order functions** - Dynamic closures cannot be fully analyzed
- **Unknown functions** - Assumed impure by default

**Safety guarantee**: May over-report impurity/exceptions, never under-report.

### 4. Effect System Limitations

**Not yet implemented**:
- Pattern matching in lambdas
- `case`, `cond`, `with` in effect macro
- Nested closures in effect blocks
- Effects in `Enum.map` callbacks within effect blocks

**Edge cases**:
- Local function calls in standalone analysis show as unknown
- Recursive functions may not fully resolve
- Complex higher-order nesting may be conservative

### 5. Gradual Typing Trade-offs

**Benefits**:
- Incremental adoption possible
- Works with existing codebases
- No massive refactoring required

**Costs**:
- Runtime checks at boundaries
- Unknown effects (¿) less precise than full typing
- Some dynamic code always unknown

---

## Comparison with Academic Whitepaper

| Whitepaper Concept | Implementation Status |
|-------------------|----------------|
| Conservative static analysis | ✅ PURITY's bytecode analyzer extended with exception tracking |
| Exception tracking | ✅ Tracks exception propagation through call graphs |
| Try/catch analysis | 🔄 Will be implemented in bidirectional effect system |
| Fine-grained exception policies | ✅ `allow_exceptions` option in pure macro |
| :dynamic vs :unknown distinction | ✅ Semantic hierarchy for analysis failures |
| Elixir stdlib classifications | ✅ `Litmus.Stdlib` whitelist module |
| Compile-time enforcement | ✅ `pure` macro with purity and exception checking |
| Bidirectional type inference | ✅ Infers effect types from source with lambda propagation |
| Mix tasks | ✅ `mix effect` command for source analysis |
| Optional annotations | ⏳ Planned (`@pure` attributes) |
| IDE integration | ⏳ Future work |

---

## Contributing

### Areas for Improvement

1. **Update PURITY** - Support Erlang maps and modern syntax
2. **Expand stdlib whitelist** - Add more modules, refine classifications
3. **Try/catch analysis** - Implement in bidirectional effect system
5. **Mix tasks** - CLI tools for analysis and reporting
6. **ExUnit integration** - Test helpers for purity/exception assertions
7. **Documentation** - More examples and guides
8. **Performance** - Optimize for large codebases

### Running the Test Suite

```bash
# All tests
mix test

# With coverage
mix test --cover

# Specific test file
mix test test/analyzer/ast_walker_test.exs

# Effect inference tests
mix effect test/infer/edge_cases_test.exs
mix effect test/infer/regression_test.exs
mix effect test/infer/infer_test.exs
```

**Current Status**: ✅ **374 tests, 0 failures (100% passing)**

### Project Links

- **Main Repository**: https://github.com/wende/litmus
- **PURITY Fork**: https://github.com/wende/purity
- **Academic Paper**: "Purity in Erlang" (Pitidis & Sagonas)
- **Litmus Whitepaper**: `docs/whitepaper.md`

---

## Quick Reference

### Common Commands

```bash
# Analyze a file
mix effect lib/my_module.ex

# Verbose analysis
mix effect lib/my_module.ex --verbose

# JSON output
mix effect lib/my_module.ex --json

# With exceptions
mix effect lib/my_module.ex --exceptions

# Run tests
mix test

# Generate effects cache
mix generate_effects

# Clean effects cache
mix effect.cache.clean
```

### Effect Type Quick Reference

| Symbol | Compact | Name | Meaning |
|--------|---------|------|---------|
| ✓ | `p` | Pure | No effects |
| λ | `l` | Lambda | Inherits from args |
| ◐ | `d` | Dependent | Reads environment |
| ⚡ | `s` | Side effects | I/O, state, processes |
| ⚠ | `e` | Exception | Raises exceptions |
| ? | `u` | Unknown | Cannot analyze |
| 🔧 | `n` | NIF | Native code |

### API Quick Reference

```elixir
# Purity analysis
Litmus.analyze_module(:lists)
Litmus.pure?(results, {Module, :func, 1})
Litmus.pure_stdlib?({Enum, :map, 2})

# Exception tracking
Litmus.analyze_exceptions(MyModule)
Litmus.can_raise?(results, mfa, ArgumentError)
Litmus.get_exceptions(results, mfa)

# Pure macro
import Litmus.Pure
pure do ... end
pure allow_exceptions: [ArgumentError] do ... end
pure require_termination: true do ... end

# Effect handlers
import Litmus.Effects
effect do ... catch {Module, :func, args} -> result end
Effects.run(eff, handler)
```

---

**License**: MIT (Litmus), LGPL (PURITY)
**Version**: v0.1.0
**Last Updated**: 2025-10-19
