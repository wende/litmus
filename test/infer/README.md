# Effect Inference Tests

This directory contains comprehensive tests for the Litmus effect inference system.

## Test Files

### 1. `infer_test.exs`
Original test file covering basic effect inference scenarios:
- Pure functions (arithmetic, string ops, list ops)
- Lambda effect propagation (pure and effectful)
- Function capture (pure and effectful)
- Mixed lambdas and captures
- Higher-order functions with side effects
- Side effects (File, IO, ETS)
- Exceptions
- Complex nested cases

### 2. `edge_cases_test.exs`
Comprehensive edge cases discovered during development:
- **Lambda-dependent functions**: Higher-order functions that should be classified as `l` instead of `u`
- **Block expressions**: Multi-statement blocks combining multiple effects
- **Exception effects**: Explicit raises and stdlib exceptions
- **Module aliases**: Compile-time constructs that should not produce effects
- **Unknown effects**: `apply` with runtime-determined functions
- **Variables with context**: Variables with module context atoms
- **Cross-module calls**: Effect propagation across module boundaries
- **String interpolation**: Binary construction with and without effects
- **If/Case expressions**: Conditional effects and branch combining
- **Pipe operators**: Effect propagation through pipelines
- **Dependent effects**: Context-dependent operations (Process dict, ETS, time)
- **Complex nesting**: Multiple levels of higher-order functions

### 3. `regression_test.exs`
Regression tests documenting specific bugs that were fixed:

#### Bug #1: Higher-Order Functions Marked as Unknown
- **Problem**: `def foo(func), do: func.(10)` was classified as unknown (u)
- **Fix**: Added `classify_effect/2` to detect lambda-dependent functions
- **Test**: `bug_1_higher_order_function/1` → Expected: `λ Lambda-dependent`

#### Bug #2: Block Expressions Marked as Unknown
- **Problem**: Multi-statement blocks like `IO.puts(x); File.write!(y)` were unknown
- **Fix**: Moved `__block__` pattern before local call pattern
- **Test**: `bug_2_log_and_save/2` → Expected: `⚡ Effectful`

#### Bug #3: Variables Not Recognized
- **Problem**: Variables with module context `{name, _, Elixir}` weren't recognized
- **Fix**: Changed pattern to handle any atom context
- **Test**: `bug_3_variables_with_context/2` → Expected: `✓ Pure`

#### Bug #4: Exception Functions Marked as Unknown
- **Problem**: `raise ArgumentError` was unknown because `ArgumentError` produced effect var
- **Fix**: Added `__aliases__` pattern for compile-time constructs
- **Test**: `bug_4_exception_with_module_alias/0` → Expected: `⚠ Exception`

#### Bug #5: Apply Marked as Effectful
- **Problem**: `Kernel.apply/2` was marked as side effects (s)
- **Fix**: Changed to unknown (u) in `.effects.json`
- **Test**: `bug_5_unknown_apply/0` → Expected: `? Unknown`

#### Bug #6: Cross-Module Lambda Indicators Wrong
- **Problem**: Cached lambda-dependent functions showed `?` instead of `λ`
- **Fix**: Updated `effect_type/1` to handle compact effect formats
- **Test**: Cross-module calls show correct `λ` indicator

#### Bug #7: Test Support Not in Cache
- **Problem**: `test/support` modules weren't analyzed in dev env
- **Fix**: Changed `discover_app_files/0` to always include if exists
- **Test**: SampleModule functions now in cache

#### Bug #8: Enum.reduce Marked as Unknown
- **Problem**: `Enum.reduce/3` was marked as unknown (u)
- **Fix**: Changed to lambda-dependent (l) in `.effects.json`
- **Test**: `bug_8_reduce_with_pure_lambda/1` → Expected: `✓ Pure`

## Running the Tests

Analyze any test file with the effect analyzer:

```bash
# Analyze edge cases
mix effect test/infer/edge_cases_test.exs

# Analyze regression tests
mix effect test/infer/regression_test.exs

# Analyze original tests
mix effect test/infer/infer_test.exs
```

## Expected Results

### Effect Categories

- **✓ Pure** (`p`): No side effects, deterministic
- **λ Lambda-dependent** (`l`): Effects depend on lambda parameters
- **◐ Context-dependent** (`d`): Reads from execution environment (time, process dict, ETS)
- **? Unknown** (`u`): Effects cannot be determined statically (apply, runtime calls)
- **⚠ Exception** (`e`): Can raise exceptions
- **⚡ Effectful** (`s`): Has side effects (IO, File, Process, Network, etc.)

### Call Indicators

- **→** Pure call
- **λ** Lambda-dependent call
- **?** Unknown call
- **⚠** Exception call
- **⚡** Effectful call

## Key Features Tested

1. **Lambda Effect Propagation**: Effects from lambdas are correctly extracted and combined
2. **Function Capture**: Both pure and effectful captures work correctly
3. **Higher-Order Functions**: Correctly classified as lambda-dependent
4. **Block Expressions**: Multi-statement blocks combine effects properly
5. **Exception Handling**: Explicit raises and stdlib exceptions detected
6. **Cross-Module Analysis**: Effects propagate correctly across modules
7. **Effect Combining**: Multiple effects in one function combine correctly
8. **Nested Contexts**: Deep nesting of higher-order functions works
9. **Conditional Effects**: If/case expressions combine branch effects
10. **Pipeline Effects**: Pipe operators propagate effects through chain

## Known Limitations

When analyzing standalone files (not part of a compiled project):

1. **Local function calls** may show as `Kernel.function_name` instead of `ModuleName.function_name`
2. **Nested modules** (like `defmodule Outer do defmodule Inner`) may not be in the cache
3. **Recursive functions** may not have their effects fully resolved

These limitations don't affect compiled projects where all modules are analyzed together.

## Adding New Tests

When adding tests, follow this pattern:

```elixir
@doc """
Brief description of what this tests.

ROOT CAUSE (if regression test): Why the bug occurred.
FIX (if regression test): How it was fixed.
EXPECTED: What effect this should have.
"""
def test_function_name(...) do
  # Implementation
end
```

This documentation helps future maintainers understand the test's purpose and expected behavior.
