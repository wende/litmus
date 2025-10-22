# Litmus Type and Effect System

## Overview

The Litmus Type and Effect System implements a sophisticated bidirectional type inference engine with row-polymorphic effects for Elixir codebases. Based on the comprehensive research in bidirectional effects inference, this system provides:

- **Row-polymorphic effects** with duplicate labels for proper nested handler support
- **Bidirectional type checking** with synthesis and checking modes
- **Gradual effect adoption** through unknown effects (¿)
- **BEAM-specific effect primitives** for actors and message passing
- **Developer-friendly error reporting** with actionable suggestions

## Architecture

### Core Type System (`lib/litmus/types/`)

- **`core.ex`** - Core type definitions with row-polymorphic effects
  - Primitive types: `:int`, `:float`, `:string`, `:bool`, `:atom`, `:pid`
  - Compound types: functions, tuples, lists, maps, unions
  - Effect types: empty (⟨⟩), labels (⟨l⟩), rows (⟨l | ε⟩), variables (μ)
  - Polymorphic types with ∀ quantification

- **`effects.ex`** - Effect operations and utilities
  - Effect combination with duplicate label support
  - Effect removal for handler operations
  - Subeffect checking for polymorphism
  - Conversion between effects and MFAs

- **`unification.ex`** - Robinson's algorithm extended for effects
  - Type unification with occurs checking
  - Effect row unification with unique solutions
  - Support for higher-rank polymorphism

- **`substitution.ex`** - Type substitution machinery
  - Variable substitution application
  - Substitution composition
  - Idempotent substitution normalization

### Bidirectional Inference (`lib/litmus/inference/`)

- **`bidirectional.ex`** - Main inference engine
  - **Synthesis mode (⇒)**: Infers types bottom-up from expressions
  - **Checking mode (⇐)**: Verifies expressions against expected types
  - Let-polymorphism with purity restrictions
  - Higher-rank effect polymorphism support

- **`context.ex`** - Typing context management
  - Variable bindings (name → type)
  - Effect constraint tracking
  - Scope management for polymorphism
  - Standard library pre-definitions

### AST Analysis (`lib/litmus/analyzer/`)

- **`ast_walker.ex`** - Main analysis engine
  - Module and function analysis
  - Type and effect inference for expressions
  - Error collection and reporting
  - Parallel file analysis support

- **`effect_tracker.ex`** - Effect tracking utilities
  - Effect extraction from AST
  - Effect flow analysis
  - Effectful node identification
  - Handler suggestions for testing

## Type System Features

### Row-Polymorphic Effects

The system uses row polymorphism with duplicate labels, following Koka's approach:

```elixir
# Side effects with specific MFAs
{:s, ["File.read/1"]}  # ⟨s(File.read/1)⟩

# Effect row with exception and side effects
{:effect_row, {:e, ["Elixir.ArgumentError"]}, {:s, ["File.read/1"]}}  # ⟨e(ArgumentError) | s(File.read/1)⟩

# Duplicate labels for nested handlers
{:effect_row, :exn, {:effect_row, :exn, {:effect_empty}}}  # ⟨exn | exn⟩
```

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

### Effect Types

The system tracks these effect types:

- **`:pure`** - No side effects
- **`:exn`** - Can raise exceptions (generic)
- **`{:e, [modules]}`** - Can raise specific exception types (e.g., ArgumentError, KeyError)
- **`{:e, [:dynamic]}`** - Can raise exceptions with runtime-determined types
- **`{:s, [MFAs]}`** - Side effects with specific function tracking
- **`{:d, [MFAs]}`** - Dependent effects (environment-dependent) with specific function tracking
- **`:nif`** - Native implemented functions
- **`:lambda`** - Effects depend on passed lambda functions
- **`:unknown`** - Unknown effect (gradual typing)

### Bidirectional Type Inference

The system uses two complementary modes:

**Synthesis Mode** - Infers types from expressions:
```elixir
# Synthesizes: Int × ⟨⟩ Int
def add(x, y) do
  x + y
end
```

**Checking Mode** - Verifies against expected types:
```elixir
# Checks: λx. x + 1 against Int → ⟨⟩ Int
fn x -> x + 1 end : (Int -> Int)
```

### Gradual Effects

Unknown effects (¿) enable incremental adoption:

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

## Usage

### Analyzing Files

```elixir
# Analyze a single file
{:ok, result} = Litmus.Analyzer.ASTWalker.analyze_file("lib/my_module.ex")

# Analyze source code
source = """
defmodule Example do
  def pure_add(x, y), do: x + y

  def effectful_print(x) do
    IO.puts(x)
  end
end
"""

{:ok, result} = Litmus.Analyzer.ASTWalker.analyze_source(source)

# Pretty print results
IO.puts Litmus.Analyzer.ASTWalker.format_results(result)
```

### Checking Effects

```elixir
# Check if an AST is pure
ast = quote do: 1 + 2
Litmus.Analyzer.EffectTracker.is_pure?(ast)  # true

ast = quote do: File.read!("test.txt")
Litmus.Analyzer.EffectTracker.is_pure?(ast)  # false

# Analyze effects
effect = Litmus.Analyzer.EffectTracker.analyze_effects(ast)
Litmus.Types.Effects.has_effect?(:file, effect)  # true
```

### Working with Types

```elixir
# Create types
int_type = :int
fun_type = Litmus.Types.Core.function_type(:int, Core.empty_effect(), :string)

# Create effects
pure = Litmus.Types.Core.empty_effect()
side_effect = {:s, ["IO.puts/1"]}
combined = {:effect_row, side_effect, {:e, ["Elixir.ArgumentError"]}}

# Unification
{:ok, subst} = Litmus.Types.Unification.unify({:type_var, :a}, :int)
# subst = %{{:type_var, :a} => :int}
```

## Running Tests

```bash
# Run the type system tests
mix test test/analyzer/ast_walker_test.exs

# Run the demo
elixir examples/type_effects_demo.exs
```

## Implementation Status

### ✅ Completed

- Core type system with row polymorphism
- Effect types with duplicate label support
- **Specific exception type tracking** - Tracks ArgumentError, KeyError, etc.
- **Dynamic exception detection** - Marks runtime-determined exceptions
- Unification algorithm for types and effects
- Substitution machinery
- Bidirectional type inference engine
- Context management with scoping
- AST walker for module analysis
- Effect tracking and extraction
- Exception extraction from `raise` statements
- Test suite and demonstrations (374 tests passing)

### 🚧 Future Enhancements

- **Type annotations** - Support for @spec and @type
- **Pattern matching** - Complex pattern analysis
- **Case expressions** - Full case/cond support
- **Module types** - Inter-module type checking
- **Recursive types** - μ-types for recursive data
- **Session types** - For message passing protocols
- **IDE integration** - Language server protocol
- **Effect handlers** - First-class effect handlers
- **Optimization** - Effect-based optimizations
- **Documentation generation** - Effect documentation

## Theory Background

The implementation follows these key theoretical foundations:

1. **Row Polymorphism** (Leijen, 2014)
   - Enables principal type inference
   - Duplicate labels for proper nesting
   - Unique solutions to effect constraints

2. **Bidirectional Typing** (Dunfield & Krishnaswami, 2013)
   - Mode-directed type checking
   - Handles higher-rank polymorphism
   - Better error locality

3. **Gradual Effects** (Bañados Schwerter et al., 2014)
   - Unknown effect ¿ for unannotated code
   - Pay-as-you-go runtime checking
   - Incremental adoption path

4. **BEAM-Specific Design**
   - Message passing as session effects
   - OTP behaviors as effect handlers
   - Process isolation boundaries

## Example Analysis Output

```
=== Analysis Results for DataPipeline ===

Functions:
  run_pipeline/2:
    Type: {t0, t1} -> ⟨file | io | process | e2⟩ :atom
    Effect: ⟨file | io | process⟩

  validate_input/1:
    Type: t0 -> ⟨exn:ArgumentError⟩ t1
    Effect: ⟨exn:ArgumentError⟩
    Detected effects:
      • exn:ArgumentError: May raise ArgumentError

  parse_data/1 (private):
    Type: t3 -> ⟨exn:RuntimeError⟩ t3
    Effect: ⟨exn:RuntimeError⟩

  transform_data/1 (private):
    Type: t5 -> ⟨e6⟩ t7
    Effect: ⟨⟩

Errors:
  None
```

### Specific Exception Type Tracking

The system can track which specific exceptions functions may raise:

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

# Runtime-determined exception
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

## Contributing

The type and effect system is a core component of Litmus. When contributing:

1. Maintain row polymorphism semantics
2. Preserve bidirectional typing invariants
3. Add tests for new effect categories
4. Update documentation for API changes
5. Consider gradual adoption in designs

## References

- [Type and Effect Systems Research](./BIDIRECTION_EFFECTS_INFERENCE.md)
- Koka Language - Row-polymorphic effects
- Dunfield & Krishnaswami (2013) - Complete and Easy Bidirectional Typechecking
- Bañados Schwerter et al. (2014) - Gradual Type-and-Effect Systems

## License

Part of the Litmus project - see main LICENSE file.