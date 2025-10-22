# Litmus - Purity Analysis and Exception Tracking for Elixir

**Litmus** is a comprehensive static analysis tool for Elixir that provides four powerful capabilities:

1. **Purity Analysis** - Classifies functions as pure or impure by analyzing BEAM bytecode
2. **Exception Tracking** - Tracks which exceptions each function may raise
3. **Algebraic Effects** - Mock and intercept side effects for testing using compile-time transformation
4. **Bidirectional Type Inference** - Infers effect types directly from Elixir source code with lambda effect propagation

Built on the [PURITY static analyzer](https://github.com/mpitid/purity), Litmus extends it with exception tracking and a powerful effects system, proving that fine-grained effect analysis is practical on the BEAM.

## Table of Contents

- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [What is Purity Analysis?](#what-is-purity-analysis)
  - [Effect Types Reference](#effect-types-reference)
  - [Analysis Result Levels](#analysis-result-levels)
- [Four Main Features](#four-main-features)
  - [1. Purity Analysis](#1-purity-analysis)
  - [2. Exception Tracking](#2-exception-tracking)
  - [3. Algebraic Effects System](#3-algebraic-effects-system)
  - [4. Bidirectional Type Inference](#4-bidirectional-type-inference)
- [Mix Tasks](#mix-tasks)
- [Termination Analysis](#termination-analysis)
- [Installation](#installation)
- [Known Limitations](#known-limitations)

## Quick Start

```elixir
# Add to mix.exs
{:litmus, github: "wende/litmus", tag: "v0.1.0"}

# Analyze a module for purity
{:ok, results} = Litmus.analyze_module(:lists)
Litmus.pure?(results, {:lists, :reverse, 1})  #=> true

# Enforce purity at compile-time
import Litmus.Pure
pure do
  [1, 2, 3] |> Enum.map(&(&1 * 2)) |> Enum.sum()
end

# Mock side effects for testing
import Litmus.Effects
effect do
  File.read!("config.json")
catch
  {File, :read!, _} -> ~s({"test": "data"})
end
```

## Core Concepts

### What is Purity Analysis?

Purity analysis determines whether functions are **referentially transparent** (pure) or have **side effects** (impure). Pure functions:
- Always return the same output for the same input
- Have no observable side effects (no I/O, no state mutations, no process operations)
- Can be safely optimized, memoized, and parallelized

### Effect Types Reference

Litmus uses a standardized set of **effect types** stored in `.effects.json` to classify all standard library functions:

| Type | Name | Description | Examples |
|------|------|-------------|----------|
| **`"p"`** | Pure | Referentially transparent, no side effects | `Enum.map/2`, `String.upcase/1`, `+/2` |
| **`"d"`** | Dependent | Depends on execution environment/context | `node/0`, `self/0` |
| **`"n"`** | NIF | Native code, behavior unknown | `:crypto` functions |
| **`"s"`** | Stateful | Writes/modifies state | `File.write!/2`, `IO.puts/1`, `send/2` |
| **`"l"`** | Lambda | May inherit effects from passed functions | `Enum.map/2` (higher-order) |
| **`"u"`** | Unknown | Cannot be analyzed | Dynamic dispatch, missing debug_info |
| **`{"e", [...]}`** | Exceptions | May raise specific exceptions | `{"e", ["Elixir.ArgumentError"]}` |

**Note:** Functions can have multiple effect types. For example, `Enum.map/2` is both `"p"` (pure when given pure functions) and `"l"` (lambda - inherits effects from the function argument).

### Analysis Result Levels

When analyzing compiled modules, Litmus returns one of these **analysis result levels**:

- **`:pure`** - Referentially transparent, no side effects, no exceptions
- **`:exceptions`** - Side-effect free but may raise exceptions
- **`:lambda`** - Side-effect free but may inherit effects from passed functions
- **`:dependent`** - Side-effect free but depends on execution environment (e.g., `node/0`)
- **`:nif`** - Native code (behavior unknown, conservative assumption)
- **`:side_effects`** - Has observable side effects (I/O, process operations, etc.)
- **`:unknown`** - Cannot be analyzed (dynamic dispatch, missing debug_info)

## Four Main Features

### 1. Purity Analysis

Analyze BEAM bytecode to determine if functions are pure or have side effects.

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

**Elixir Standard Library Whitelist:** Litmus includes a manually curated whitelist of pure stdlib functions for instant checking without bytecode analysis:

```elixir
Litmus.pure_stdlib?({Enum, :map, 2})     #=> true
Litmus.pure_stdlib?({String, :upcase, 1}) #=> true
Litmus.pure_stdlib?({IO, :puts, 1})       #=> false
```

**Compile-Time Enforcement:** Use the `pure` macro to enforce purity at compile time:

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

Track which exceptions each function may raise, independently from purity analysis.

**Exception Types:**
- **Typed exceptions** (`:error` class) - ArgumentError, KeyError, etc. with known module types
- **Untyped exceptions** (`:throw`/`:exit` classes) - Arbitrary values used for control flow
- **Dynamic exceptions** (`:dynamic`) - Type cannot be determined statically (e.g., `raise variable`)

```elixir
# Analyze exceptions for a module
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

**Exception Policies:** Control which exceptions are allowed in pure blocks:

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

Mock and intercept side effects for testing using continuation-passing style (CPS) transformation at compile time.

**Basic Usage:**

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

**How It Works:** The `effect` macro transforms your code using continuation-passing style (CPS):

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

**Key Features:**

```elixir
# Control flow with effects (if/else)
effect do
  x = if use_cache?, do: File.read!("cache.txt"), else: fetch!()
  process(x)
catch
  {File, :read!, _} -> "cached"
end

# Variable capture in handlers
effect do
  File.write!("log.txt", "message")
catch
  {File, :write!, [path, content]} ->
    assert path == "log.txt"  # Can inspect arguments
    :ok
end
```

**Testing Benefits:**
- No filesystem access, no network calls, deterministic tests
- Fast tests with no I/O waiting
- Clear test intent through effect signatures
- Zero runtime overhead (compile-time transformation)

**Current Limitations:** `case`, `cond`, `with` expressions, effects in `Enum.map`, and nested closures not yet supported. See `test/effects/` for examples.

### 4. Bidirectional Type Inference

Analyze Elixir source code directly to infer effect types with support for lambda effect propagation in higher-order functions.

**Key Capabilities:**

- Analyzes AST directly (no BEAM bytecode required)
- Infers effect types for user-defined functions
- **Lambda effect propagation** - Correctly tracks how effects flow through higher-order functions like `Enum.map`
- **Cross-module analysis** - Understands effects across your entire application
- **Compile-time integration** - Results available during compilation

**Basic Usage:**

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

**Lambda Effect Propagation:**

```elixir
# These functions analyze correctly with lambda effect propagation:

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

**Mix Task:**

Use `mix effect` to analyze files from the command line:

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

The analysis automatically discovers and analyzes all application source files to understand cross-module effects.

## Mix Tasks

Litmus provides `mix effect` for analyzing Elixir source files directly from the command line.

### mix effect

Analyzes an Elixir file and displays all functions with their inferred effect types and exceptions.

**Usage:**

```bash
mix effect path/to/file.ex [options]
```

**Options:**

| Option | Short | Description |
|--------|-------|-------------|
| `--verbose` | `-v` | Show detailed analysis including type information and all function calls |
| `--json` | | Output results in JSON format for tool integration |
| `--exceptions` | | Include exception tracking from BEAM analysis |
| `--purity` | | Include purity analysis from PURITY bytecode analyzer |

**Examples:**

```bash
# Basic effect analysis
mix effect lib/my_module.ex

# Verbose output with detailed types
mix effect lib/my_module.ex --verbose

# JSON output for automated processing
mix effect lib/my_module.ex --json

# Include exception tracking
mix effect lib/my_module.ex --exceptions

# Full analysis with PURITY bytecode and exceptions
mix effect lib/my_module.ex --purity --exceptions
```

**How It Works:**

1. Discovers all application source files to understand cross-module effects
2. Analyzes dependencies to build effect cache
3. Infers effect types for all functions in the target file
4. Displays results with effect types in compact notation (`:p`, `:s`, `:l`, `:d`, `:u`)
5. Optionally includes PURITY bytecode analysis and exception information

## Termination Analysis

Litmus can verify that functions terminate (don't loop infinitely), separate from purity analysis.

### Checking Termination

Use the termination analysis API:

```elixir
# Analyze a module for termination
{:ok, results} = Litmus.analyze_termination(:lists)

# Check if a function terminates
Litmus.terminates?(results, {:lists, :reverse, 1})  #=> true

# Get termination status
{:ok, status} = Litmus.get_termination(results, {:lists, :reverse, 1})
#=> {:ok, :terminating}
```

### Stdlib Whitelist

Check if stdlib functions terminate without analysis:

```elixir
# Pure stdlib functions that terminate
Litmus.Stdlib.terminates?({Enum, :map, 2})      #=> true
Litmus.Stdlib.terminates?({List, :reverse, 1})  #=> true

# Non-terminating generators and servers
Litmus.Stdlib.terminates?({Stream, :cycle, 1})        #=> false
Litmus.Stdlib.terminates?({Process, :sleep, 1})       #=> false
Litmus.Stdlib.terminates?({GenServer, :call, 2})      #=> false
Litmus.Stdlib.terminates?({Task, :await, 2})         #=> false
```

### Compile-Time Enforcement

Use the `pure` macro with `require_termination: true` to enforce termination at compile time:

```elixir
import Litmus.Pure

# ✅ This compiles successfully
result = pure require_termination: true do
  [1, 2, 3]
  |> Enum.map(&(&1 * 2))
  |> Enum.sum()
end

# ❌ This fails at compile time - Stream.cycle never terminates
pure require_termination: true do
  Stream.cycle([1, 2, 3]) |> Enum.take(3)
end

# ❌ This fails - Process.sleep blocks indefinitely
pure require_termination: true do
  Process.sleep(1000)
end
```

### Non-Terminating Functions

These stdlib functions are known to not terminate:

**Generators (infinite sequences):**
- `Stream.cycle/1`, `Stream.iterate/2`, `Stream.unfold/2`, `Stream.repeatedly/1`
- `Integer.digits/1` with 0 (edge case)

**Blocking Operations:**
- `Process.sleep/1`, `Process.wait_timeout/0`
- `GenServer.call/2`, `GenServer.call/3` (waits for response)
- `Task.await/1`, `Task.await/2` (waits for completion)
- `Agent.get/2` (can wait on agent operations)

**Loops:**
- `Process.monitor/1` with selective receive
- Any function with unbounded recursion

## Installation

Add `litmus` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:litmus, github: "wende/litmus", tag: "v0.1.0"}
  ]
end
```

Run `mix deps.get` to install.

## Advanced Topics

### Standard Library Whitelist

**Whitelisted modules** (pure): `Enum`, `List`, `Map`, `MapSet`, `Tuple`, `String` (except atom conversions), `Integer`, `Float`, `Date`, `Time`, `Path`, `URI`, `Regex`, etc.

**NOT whitelisted** (impure): `IO`, `File`, `System`, `Process`, `Agent`, `Task`, or dangerous operations like `String.to_atom/1`.

See `Litmus.Stdlib` for complete details.

### How Exception Tracking Works

Exception tracking propagates through call graphs by:
1. Identifying calls to `raise`, `throw`, `exit`, and `:erlang.error/1,2`
2. Propagating exceptions via fixed-point iteration
3. Marking dynamic raises (e.g., `raise variable`) as `:dynamic`

**Note:** Try/catch blocks are not currently analyzed (conservative analysis - may over-report exceptions). This will be implemented in the bidirectional effect system.

### How the Pure Macro Works

- **Zero runtime cost**: All checks happen at compile time
- **Detailed error messages**: Shows exactly which functions are impure and why
- **Safe by default**: Only whitelisted stdlib functions are allowed
- **Macro-aware**: Correctly handles `|>`, `case`, `with`, and other Elixir macros

#### Limitations

The `pure` macro can only detect impurity from:
- Direct function calls visible in the AST
- Functions in the stdlib whitelist

It **cannot detect** impurity from:
- Dynamic dispatch (`apply/3`, function variables)
- Your own custom functions (unless you add them to the whitelist)
- NIFs or external code
- Code generated by macros you don't control

For these cases, combine with runtime PURITY analysis using `analyze_module/2`.

#### Practical Examples

```elixir
import Litmus.Pure

# Pure data transformation
users = [
  %{name: "Alice", age: 30},
  %{name: "Bob", age: 25},
  %{name: "Charlie", age: 35}
]

adults = pure do
  users
  |> Enum.filter(fn u -> Map.get(u, :age) >= 30 end)
  |> Enum.map(fn u -> Map.get(u, :name) end)
end
#=> ["Alice", "Charlie"]

# Fails compilation: side effects
pure do
  File.read!("config.txt")  # ❌ File.read!/1 (I/O operation)
end

# Fails compilation: dangerous operation
pure do
  String.to_atom("user_input")  # ❌ String.to_atom/1 (mutates atom table)
end
```

See `Litmus.Pure` module documentation for more examples.

## Known Limitations

### 1. PURITY Version Compatibility

PURITY was developed in 2011 for Erlang R14, before several modern Erlang features existed:

- **Map literals** (added in Erlang R17/2014) are not supported
- **Modern Elixir code** that uses maps will fail to analyze
- **Erlang standard library modules** work perfectly

### 2. Dynamic Language Features

Static analysis cannot handle:

- **Dynamic dispatch** - `apply/3`, module variables
- **Dynamic exception raises** - `raise variable` marked as `:dynamic` (conservative)
- **Metaprogramming** - Macros generate different code in different contexts
- **NIFs** - Native code is a black box
- **Process message passing** - Cross-process effects are invisible
- **Hot code loading** - Multiple versions of functions may exist

### 3. Conservative Approximations

PURITY and exception tracking use conservative analysis:

- **False negatives** - Some pure functions may be marked impure
- **Over-reporting exceptions** - Dynamic raises marked as `:dynamic` (may raise anything)
- **Try/catch blocks not analyzed** - Caught exceptions are still reported (conservative)
- **Higher-order functions** with dynamic closures cannot be fully analyzed
- **Unknown functions** are assumed impure by default

The conservative approach ensures **safety**: we may over-report impurity and exceptions, but we never under-report them. Real-world example: `Jason.decode!` uses `raise error` (variable), so it's marked with `:dynamic` exceptions rather than being completely unanalyzable.

## Example: Analyzing Erlang Modules

```elixir
# Start an iex session
iex -S mix

# Analyze the Erlang lists module
iex> {:ok, results} = Litmus.analyze_module(:lists)
{:ok, %{...}} # 223 functions analyzed

# Check purity of common functions
iex> Litmus.pure?(results, {:lists, :reverse, 1})
true

iex> Litmus.pure?(results, {:lists, :map, 2})
true

iex> Litmus.pure?(results, {:lists, :foldl, 3})
true

# View purity levels
iex> results
|> Map.filter(fn {_, level} -> level == :pure end)
|> Map.keys()
|> Enum.take(10)
[
  {:lists, :reverse, 1},
  {:lists, :map, 2},
  {:lists, :filter, 2},
  {:lists, :foldl, 3},
  ...
]
```

## Testing

Run the test script to verify the installation:

```bash
mix run test_litmus.exs
```

Expected output:
```
Testing Litmus wrapper...

1. Analyzing :lists module...
✓ Successfully analyzed 223 functions

First 10 analyzed functions:
  - lists.rufmerge2_2/6: pure
  - lists.umerge3_12_3/6: pure
  ...

✓ All tests passed! Litmus wrapper is working correctly.
```

## Architecture

Litmus consists of:

1. **Core wrapper** (`lib/litmus.ex`) - Main API wrapping PURITY functions with exception tracking
2. **Exception tracking** (`lib/litmus/exceptions.ex`) - Track exception propagation through call graphs
3. **Pure macro** (`lib/litmus/pure.ex`) - Compile-time purity and exception enforcement
4. **Stdlib whitelist** (`lib/litmus/stdlib.ex`) - Curated pure function whitelist
5. **Type system** (`lib/litmus/types/`) - Core types and effect operations
   - **`core.ex`** - Type and effect definitions (`:p`, `:s`, `:l`, `:d`, `:u`, `:n`)
   - **`effects.ex`** - Effect operations and row-polymorphic handling
   - **`unification.ex`** - Type unification for type inference
   - **`substitution.ex`** - Variable substitution and substitution composition
6. **Inference engine** (`lib/litmus/inference/`) - Bidirectional type checking
   - **`bidirectional.ex`** - Synthesis (⇒) and checking (⇐) modes
   - **`context.ex`** - Type context and environment management
7. **AST analyzer** (`lib/litmus/analyzer/`) - Infers effects from Elixir source code
   - **`ast_walker.ex`** - Walks AST and infers effect types for all functions
   - **`effect_tracker.ex`** - Tracks effects and function calls in expressions
8. **Effects system** (`lib/litmus/effects/`) - Algebraic effects with CPS transformation
   - **`effects.ex`** - Main effect macro and handler API
   - **`transformer.ex`** - CPS transformation engine for AST
   - **`registry.ex`** - Effect categorization and tracking
   - **`unhandled_error.ex`** - Exception for unhandled effects
10. **Mix tasks** (`lib/mix/tasks/`) - CLI tooling
    - **`effect.ex`** - `mix effect` command for analyzing source files
    - **`generate_effects.ex`** - Generates effect cache for dependencies
11. **PURITY library** (`purity_source/`) - [Forked Erlang static analyzer](https://github.com/wende/purity) with type fixes and map support

### How It Works

1. **Compilation** - Modules must be compiled with `:debug_info` enabled
2. **BEAM Analysis** - PURITY analyzes Core Erlang in the `.beam` files
3. **Call Graph Construction** - Builds dependency graph of function calls
4. **Purity Propagation** - Fixed-point iteration propagates impurity through callers
5. **Exception Tracking** - Identifies exception-raising operations and propagates through call graph
6. **Result Conversion** - Erlang `dict()` results converted to Elixir maps with exception information

## Comparison with Whitepaper

This implementation demonstrates concepts from the [Litmus whitepaper](./whitepaper.md):

| Whitepaper Concept | Implementation |
|-------------------|----------------|
| Conservative static analysis | ✅ PURITY's bytecode analyzer extended with exception tracking |
| Exception tracking | ✅ **NEW** - Tracks exception propagation through call graphs |
| Try/catch analysis | 🔄 **TODO** - Will be implemented in bidirectional effect system |
| Fine-grained exception policies | ✅ **NEW** - `allow_exceptions` option in pure macro |
| :dynamic vs :unknown distinction | ✅ **NEW** - Semantic hierarchy for analysis failures |
| Elixir stdlib classifications | ✅ `Litmus.Stdlib` whitelist module |
| Compile-time enforcement | ✅ `pure` macro with purity and exception checking |
| Bidirectional type inference | ✅ **NEW** - Infers effect types from source with lambda propagation |
| Mix tasks | ✅ **NEW** - `mix effect` command for source analysis |
| Optional annotations | ⏳ Planned (`@pure` attributes) |
| PLT caching | ⏳ Planned (Litmus.PLT module) |
| IDE integration | ⏳ Future work |

## Roadmap

### Completed ✅

- [x] **Litmus.Stdlib** - Whitelist-based purity classifications for Elixir standard library
- [x] **Litmus.Pure** - `pure do...end` macro for compile-time purity enforcement
- [x] **Litmus.Exceptions** - Exception tracking module with propagation through call graphs
- [x] **Exception policies** - Fine-grained `allow_exceptions` control in pure macro
- [x] **:dynamic vs :unknown** - Semantic distinction for analysis failures

### Recently Added 🎉

- [x] **Litmus.Effects** - Algebraic effects system using continuation-passing style (CPS)
- [x] **Effect handlers** - Mock and intercept side effects for testing
- [x] **Control flow transformation** - `if/else` expressions with effects
- [x] **Anonymous function support** - Transform closures with effects in their bodies
- [x] **Effect tracking** - Full effect tracking for testing and analysis
- [x] **Bidirectional type inference** - Infers effect types from source code with lambda effect propagation
- [x] **Higher-order function support** - Correctly analyzes effects in `Enum.map`, `Enum.filter`, callbacks, etc.
- [x] **Mix task** - `mix effect` command for analyzing Elixir files with cross-module effect tracking
- [x] **Termination analysis** - Detects non-terminating functions and enforces termination at compile time

### Planned ⏳

- [ ] **Advanced effect features** - `case`, `cond`, `with` expressions in effect macro
- [ ] **Nested closure tracking** - Functions returning functions with effects in effect macro
- [ ] **Litmus.PLT** - Persistent Lookup Table for caching results across compilations
- [ ] **Litmus.Results** - Pretty-printing and HTML/JSON report generation
- [ ] **ExUnit integration** - Purity and exception assertions in tests
- [ ] **@pure annotations** - Optional developer annotations for verification
- [ ] **Update PURITY** - Support modern Erlang features (maps, etc.)
- [ ] **IDE integration** - LSP server with inline purity/exception information

## Contributing

Contributions welcome! Areas for improvement:

1. **Update PURITY** to support Erlang maps and modern syntax
2. **Expand stdlib whitelist** - Add more Elixir modules, refine existing classifications with exception information
3. **Try/catch analysis** - Implement exception handling in bidirectional effect system
4. **PLT implementation** - Build persistent caching for purity and exception results
5. **Mix tasks** - CLI tools for analysis and reporting
6. **ExUnit integration** - Test helpers for asserting purity and exception properties
7. **Documentation** - More usage examples and guides
8. **Performance** - Optimize analysis for large codebases

Run the test suite with `mix test` (**374 tests** covering purity analysis, exception tracking, bidirectional type inference, lambda effect propagation, and algebraic effects - 100% passing).

## License

Litmus is released under the MIT License.

PURITY is released under the GNU Lesser General Public License (LGPL).

## References

- [PURITY - Side-effect analyzer for Erlang](https://github.com/mpitid/purity) (Original by Pitidis & Sagonas)
- [PURITY Fork](https://github.com/wende/purity) (Used by Litmus with type fixes and map support)
- [Purity in Erlang (Academic Paper)](https://link.springer.com/chapter/10.1007/978-3-642-24276-2_9)
- [Litmus Whitepaper](./whitepaper.md) - Theoretical foundations for purity analysis in Elixir

## Acknowledgments

- **Michael Pitidis** and **Kostis Sagonas** - Original PURITY tool authors
- **Erlang/OTP team** - For the robust BEAM VM and compiler infrastructure
- **Elixir community** - For building on top of Erlang's solid foundations
