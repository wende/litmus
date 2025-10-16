# Litmus - Purity Analysis for Elixir

**Litmus** is an Elixir wrapper for the [PURITY static analyzer](https://github.com/mpitid/purity), bringing purity analysis to the Elixir ecosystem. It can analyze compiled BEAM bytecode to classify functions as pure, side-effect free, or impure.

This project is a practical implementation of concepts from the accompanying [whitepaper on purity analysis for Elixir](./whitepaper.md).

## What is Purity Analysis?

Purity analysis determines whether functions are **referentially transparent** (pure) or have **side effects** (impure). Pure functions:
- Always return the same output for the same input
- Have no observable side effects (no I/O, no state mutations, no process operations)
- Can be safely optimized, memoized, and parallelized

## Purity Levels

Litmus classifies functions into four categories:

- **`:pure`** - Referentially transparent, no side effects, no exceptions
- **`:exceptions`** - Side-effect free but may raise exceptions
- **`:dependent`** - Side-effect free but depends on execution environment (e.g., `node/0`)
- **`:side_effects`** - Has observable side effects (I/O, process operations, etc.)

## Installation

Add `litmus` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:litmus, github: "yourusername/litmus"}
  ]
end
```

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
- **Metaprogramming** - Macros generate different code in different contexts
- **NIFs** - Native code is a black box
- **Process message passing** - Cross-process effects are invisible
- **Hot code loading** - Multiple versions of functions may exist

### 3. Conservative Approximations

PURITY uses conservative analysis:

- **False negatives** - Some pure functions may be marked impure
- **Higher-order functions** with dynamic closures cannot be fully analyzed
- **Unknown functions** are assumed impure by default

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

1. **Core wrapper** (`lib/litmus.ex`) - Main API wrapping PURITY functions
2. **PURITY library** (`purity_source/`) - Erlang static analyzer (forked with type fixes)
3. **Type conversions** - Seamless Erlang ↔ Elixir data structure conversion

### How It Works

1. **Compilation** - Modules must be compiled with `:debug_info` enabled
2. **BEAM Analysis** - PURITY analyzes Core Erlang in the `.beam` files
3. **Call Graph Construction** - Builds dependency graph of function calls
4. **Purity Propagation** - Fixed-point iteration propagates impurity through callers
5. **Result Conversion** - Erlang `dict()` results converted to Elixir maps

## Comparison with Whitepaper

This implementation demonstrates concepts from the [Litmus whitepaper](./whitepaper.md):

| Whitepaper Concept | Implementation |
|-------------------|----------------|
| Conservative static analysis | ✅ Uses PURITY's bytecode analyzer |
| Optional annotations | ⏳ Planned (`@pure` attributes) |
| PLT caching | ⏳ Planned (Litmus.PLT module) |
| Convention-based practices | 📝 Documentation only |
| Elixir stdlib classifications | ✅ Implemented `Litmus.Stdlib` whitelist module |
| Mix tasks | ⏳ Planned (`mix litmus.analyze`) |
| IDE integration | ⏳ Future work |

## Roadmap

- [ ] **Litmus.PLT** - Persistent Lookup Table for caching results
- [x] **Litmus.Stdlib** - ✅ **COMPLETED** - Whitelist-based purity classifications for Elixir standard library
- [x] **Litmus.Pure** - ✅ **COMPLETED** - `pure do...end` macro for compile-time purity enforcement
- [ ] **Mix tasks** - `mix litmus.analyze`, `mix litmus.build_plt`
- [ ] **Litmus.Results** - Pretty-printing and HTML/JSON report generation
- [ ] **ExUnit integration** - Purity assertions in tests
- [ ] **Update PURITY** - Support modern Erlang features (maps, etc.)

## Contributing

Contributions welcome! Areas for improvement:

1. **Update PURITY** to support Erlang maps and modern syntax
2. **Expand stdlib whitelist** - Add more Elixir modules, refine existing classifications
3. **PLT implementation** - Build persistent caching for analysis results
4. **Mix tasks** - CLI tools for analysis and reporting
5. **Documentation** - More usage examples and guides
6. **Performance** - Optimize analysis for large codebases

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
