# Litmus - Purity Analysis and Exception Tracking for Elixir

**Litmus** extends the [PURITY static analyzer](https://github.com/mpitid/purity) with comprehensive exception tracking for Elixir. It analyzes compiled BEAM bytecode to classify functions by purity level and tracks which exceptions they may raise, enabling fine-grained control over exception policies in pure code.

This project demonstrates concepts from the accompanying [whitepaper on purity analysis for Elixir](./whitepaper.md), proving that exception tracking is practical and achievable on the BEAM.

## What is Purity Analysis?

Purity analysis determines whether functions are **referentially transparent** (pure) or have **side effects** (impure). Pure functions:
- Always return the same output for the same input
- Have no observable side effects (no I/O, no state mutations, no process operations)
- Can be safely optimized, memoized, and parallelized

## Purity Levels

Litmus classifies functions into purity levels:

- **`:pure`** - Referentially transparent, no side effects, no exceptions
- **`:exceptions`** - Side-effect free but may raise exceptions
- **`:dependent`** - Side-effect free but depends on execution environment (e.g., `node/0`)
- **`:nif`** - Native code (behavior unknown, conservative assumption)
- **`:side_effects`** - Has observable side effects (I/O, process operations, etc.)
- **`:unknown`** - Cannot be analyzed (dynamic dispatch, missing debug_info)

## Exception Tracking

**New in v0.1.0**: Litmus tracks exceptions independently from purity, distinguishing between:

- **Typed exceptions** (`:error` class) - ArgumentError, KeyError, etc. with known module types
- **Untyped exceptions** (`:throw`/`:exit` classes) - Arbitrary values used for control flow
- **Dynamic exceptions** (`:dynamic`) - Exceptions raised but type cannot be determined statically (e.g., `raise variable`)

Exception information propagates through call graphs and can be queried per-function, enabling compile-time enforcement of exception policies.

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

## Usage

### Basic Analysis

```elixir
# Analyze a single module
{:ok, results} = Litmus.analyze_module(:lists)

# Check if a specific function is pure
Litmus.pure?(results, {:lists, :reverse, 1})
#=> true

Litmus.pure?(results, {:lists, :keydelete, 3})
#=> true

# Get the detailed purity level
{:ok, level} = Litmus.get_purity(results, {:lists, :map, 2})
#=> {:ok, :pure}
```

### Analyzing Multiple Modules

```elixir
# Sequential analysis
{:ok, results} = Litmus.analyze_modules([:lists, :string, :maps])

# Parallel analysis (faster for large codebases)
{:ok, results} = Litmus.analyze_parallel([:lists, :string, :maps])
```

### Finding Missing Information

```elixir
# Identify functions that couldn't be analyzed
%{functions: mfas, primops: prims} = Litmus.find_missing(results)
```

### Exception Tracking

Analyze which exceptions functions may raise:

```elixir
# Analyze exceptions for a module
{:ok, exceptions} = Litmus.analyze_exceptions(MyModule)

# Check if a function can raise a specific exception
Litmus.can_raise?(exceptions, {MyModule, :parse, 1}, ArgumentError)
#=> true

# Check if a function can throw/exit
Litmus.can_throw_or_exit?(exceptions, {MyModule, :parse, 1})
#=> false

# Get detailed exception information
{:ok, info} = Litmus.get_exceptions(exceptions, {MyModule, :parse, 1})
#=> {:ok, %{
#=>   errors: MapSet.new([ArgumentError, KeyError]),
#=>   non_errors: false
#=> }}
```

Exception tracking works by:
1. Identifying calls to `raise`, `throw`, `exit`, and `:erlang.error/1,2`
2. Propagating exceptions through call graphs via fixed-point iteration
3. Analyzing try/catch blocks using Core Erlang AST to subtract caught exceptions
4. Marking dynamic raises (e.g., `raise variable`) as `:dynamic` when types cannot be determined

### Elixir Standard Library Whitelist

For maximum safety, Litmus includes a manually curated **whitelist** of Elixir standard library functions known to be pure. This provides instant purity checks without needing BEAM analysis.

```elixir
# Check if an Elixir stdlib function is whitelisted as pure
Litmus.pure_stdlib?({Enum, :map, 2})
#=> true

Litmus.pure_stdlib?({String, :upcase, 1})
#=> true

# Side-effect functions are not whitelisted
Litmus.pure_stdlib?({IO, :puts, 1})
#=> false

# Dangerous functions are excluded
Litmus.pure_stdlib?({String, :to_atom, 1})
#=> false (mutates atom table!)

# Comprehensive check combining both PURITY analysis and whitelist
Litmus.safe_to_optimize?(results, {Enum, :map, 2})
#=> true
```

#### Whitelist Philosophy

- **Whitelist, not blacklist**: Only explicitly listed functions are considered pure
- **Conservative by default**: Unknown functions return `false` for maximum safety
- **Three whitelist formats**:
  - `:all` - Entire module is pure (e.g., `List`, `Integer`, `Float`)
  - `{:all_except, exceptions}` - All functions except specified ones (e.g., `String` except `to_atom/1`)
  - `%{function: [arities]}` - Selective whitelist (e.g., `Kernel` has only specific functions)

#### Whitelisted Modules

- **Core data structures**: `Enum`, `List`, `Map`, `MapSet`, `Tuple`, `Keyword`, `Range`, `Stream`
- **Strings and numbers**: `String` (except atom conversions), `Integer`, `Float`
- **Date/Time**: `Date`, `Time`, `DateTime` (except `now`/`utc_now`), `NaiveDateTime` (except `now`/`utc_now`)
- **Utilities**: `Path`, `URI`, `Regex`, `Version`, `Exception`
- **Kernel**: Selective whitelist of operators, type checks, and pure operations

#### Explicitly NOT Whitelisted (Side Effects)

- **I/O**: `IO`, `File`, `Port`
- **System**: `System`, `Node`, `Code`
- **Processes**: `Process`, `Agent`, `Task`, `GenServer`, `Registry`
- **Dangerous operations**: `String.to_atom/1`, `String.to_existing_atom/1`, `apply/2`, `send/2`, etc.

See `Litmus.Stdlib` module documentation for complete details and examples.

### Compile-Time Purity Enforcement

Litmus provides a `pure do ... end` macro that enforces purity constraints at **compile time**. Any impure function call within the block will cause a compilation error with detailed diagnostics.

```elixir
import Litmus.Pure

# ✅ This compiles successfully
result = pure do
  [1, 2, 3, 4, 5]
  |> Enum.map(&(&1 * 2))
  |> Enum.filter(&(&1 > 5))
  |> Enum.sum()
end
#=> 24

# ❌ This fails at compile time
pure do
  IO.puts("Hello")  # Compilation error!
end

** (Litmus.Pure.ImpurityError) Impure function calls detected in pure block:

  - IO.puts/1 (I/O operation)

Pure blocks can only call whitelisted pure functions.
See Litmus.Stdlib for the complete whitelist.
```

#### Exception Policies

**New in v0.1.0**: Control which exceptions are allowed in pure blocks:

```elixir
import Litmus.Pure

# Allow specific exceptions in otherwise pure code
result = pure level: :pure, allow_exceptions: [ArgumentError, KeyError] do
  # ✅ Computationally pure but may raise specific exceptions
  Map.fetch!(data, :key) |> String.to_integer!()
end

# Allow any exceptions but forbid I/O
result = pure level: :pure, allow_exceptions: :any do
  # ✅ May raise anything, but no side effects
  Integer.parse!(user_input)
end

# Forbid all exceptions
result = pure level: :pure, allow_exceptions: :none do
  # ❌ Would fail if this could raise
  Enum.sum([1, 2, 3])  # ✅ This is safe
end

# ❌ This fails - KeyError not in allowed list
pure allow_exceptions: [ArgumentError] do
  Map.fetch!(%{}, :missing)  # Raises KeyError!
end

** (Litmus.Pure.ImpurityError) Disallowed exception calls detected in pure block:

  - Map.fetch!/2 (raises: KeyError)

Allowed exceptions: only [ArgumentError]
```

The system uses static analysis to determine which exceptions each function may raise and enforces policies at compile time.

#### How It Works

1. **Macro expansion**: The `pure` macro expands all macros in the code block (including `|>`)
2. **AST analysis**: Extracts all function calls from the expanded AST
3. **Whitelist checking**: Validates each call against `Litmus.Stdlib` whitelist
4. **Compile-time errors**: Raises detailed errors with function classifications if impure calls are found

#### Benefits

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
- **Try/catch fallback** - If Core Erlang extraction fails, caught exceptions not subtracted
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
3. **Try/catch analysis** (`lib/litmus/try_catch.ex`) - Core Erlang AST walking for exception subtraction
4. **Pure macro** (`lib/litmus/pure.ex`) - Compile-time purity and exception enforcement
5. **Stdlib whitelist** (`lib/litmus/stdlib.ex`) - Curated pure function whitelist
6. **PURITY library** (`purity_source/`) - Erlang static analyzer (forked with type fixes)

### How It Works

1. **Compilation** - Modules must be compiled with `:debug_info` enabled
2. **BEAM Analysis** - PURITY analyzes Core Erlang in the `.beam` files
3. **Call Graph Construction** - Builds dependency graph of function calls
4. **Purity Propagation** - Fixed-point iteration propagates impurity through callers
5. **Exception Tracking** - Identifies exception-raising operations and propagates through call graph
6. **Try/Catch Analysis** - Extracts Core Erlang AST to detect try/catch and subtract caught exceptions
7. **Result Conversion** - Erlang `dict()` results converted to Elixir maps with exception information

## Comparison with Whitepaper

This implementation demonstrates concepts from the [Litmus whitepaper](./whitepaper.md):

| Whitepaper Concept | Implementation |
|-------------------|----------------|
| Conservative static analysis | ✅ PURITY's bytecode analyzer extended with exception tracking |
| Exception tracking | ✅ **NEW** - Tracks exception propagation through call graphs |
| Try/catch analysis | ✅ **NEW** - Core Erlang AST analysis subtracts caught exceptions |
| Fine-grained exception policies | ✅ **NEW** - `allow_exceptions` option in pure macro |
| :dynamic vs :unknown distinction | ✅ **NEW** - Semantic hierarchy for analysis failures |
| Elixir stdlib classifications | ✅ `Litmus.Stdlib` whitelist module |
| Compile-time enforcement | ✅ `pure` macro with purity and exception checking |
| Optional annotations | ⏳ Planned (`@pure` attributes) |
| PLT caching | ⏳ Planned (Litmus.PLT module) |
| Mix tasks | ⏳ Planned (`mix litmus.analyze`) |
| IDE integration | ⏳ Future work |

## Roadmap

### Completed ✅

- [x] **Litmus.Stdlib** - Whitelist-based purity classifications for Elixir standard library
- [x] **Litmus.Pure** - `pure do...end` macro for compile-time purity enforcement
- [x] **Litmus.Exceptions** - Exception tracking module with propagation through call graphs
- [x] **Litmus.TryCatch** - Core Erlang AST analysis for try/catch exception subtraction
- [x] **Exception policies** - Fine-grained `allow_exceptions` control in pure macro
- [x] **:dynamic vs :unknown** - Semantic distinction for analysis failures

### Planned ⏳

- [ ] **Litmus.PLT** - Persistent Lookup Table for caching results across compilations
- [ ] **Mix tasks** - `mix litmus.analyze`, `mix litmus.build_plt`
- [ ] **Litmus.Results** - Pretty-printing and HTML/JSON report generation
- [ ] **ExUnit integration** - Purity and exception assertions in tests
- [ ] **@pure annotations** - Optional developer annotations for verification
- [ ] **Update PURITY** - Support modern Erlang features (maps, etc.)
- [ ] **IDE integration** - LSP server with inline purity/exception information

## Contributing

Contributions welcome! Areas for improvement:

1. **Update PURITY** to support Erlang maps and modern syntax
2. **Expand stdlib whitelist** - Add more Elixir modules, refine existing classifications with exception information
3. **Improve exception tracking** - Handle more edge cases in try/catch analysis
4. **PLT implementation** - Build persistent caching for purity and exception results
5. **Mix tasks** - CLI tools for analysis and reporting
6. **ExUnit integration** - Test helpers for asserting purity and exception properties
7. **Documentation** - More usage examples and guides
8. **Performance** - Optimize analysis for large codebases

Run the test suite with `mix test` (220+ tests covering purity and exception tracking).

## License

Litmus is released under the MIT License.

PURITY is released under the GNU Lesser General Public License (LGPL).

## References

- [PURITY - Side-effect analyzer for Erlang](https://github.com/mpitid/purity)
- [Purity in Erlang (Academic Paper)](https://link.springer.com/chapter/10.1007/978-3-642-24276-2_9)
- [Litmus Whitepaper](./whitepaper.md) - Theoretical foundations for purity analysis in Elixir

## Acknowledgments

- **Michael Pitidis** and **Kostis Sagonas** - Original PURITY tool authors
- **Erlang/OTP team** - For the robust BEAM VM and compiler infrastructure
- **Elixir community** - For building on top of Erlang's solid foundations
